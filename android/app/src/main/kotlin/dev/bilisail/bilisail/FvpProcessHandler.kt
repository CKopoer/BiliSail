package dev.bilisail.bilisail

import android.content.ComponentName
import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.Process
import android.view.Surface
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.view.TextureRegistry

/** The UI owns textures and Binder supervision, never a native MDK player. */
class FvpProcessHandler private constructor(context: Context, engine: FlutterEngine) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, AutoCloseable {
    companion object {
        private val hosts = java.util.WeakHashMap<FlutterEngine, FvpProcessHandler>()
        // audio_service retains its engine across Activity recreation.
        fun attach(context: Context, engine: FlutterEngine): FvpProcessHandler =
            hosts.getOrPut(engine) { FvpProcessHandler(context, engine) }
    }
    private val engineReference = java.lang.ref.WeakReference(engine)
    private val context = context.applicationContext
    private val registry: TextureRegistry = engine.renderer
    private val handler = Handler(Looper.getMainLooper())
    private val codec = StandardMessageCodec.INSTANCE
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.bilisail/fvp_process")
    private val events = EventChannel(engine.dartExecutor.binaryMessenger, "dev.bilisail/fvp_process/events")
    private var sink: EventChannel.EventSink? = null
    private var remote: Messenger? = null
    private var bound = false
    private var closed = false
    private var workerPid = 0
    private var nextPlayer = 0
    private var nextRequest = 0
    private val players = mutableMapOf<Int, Player>()
    private val pending = mutableMapOf<Int, Pending>()
    private val waiting = mutableListOf<() -> Unit>()
    private var startupTimeout: Runnable? = null

    private class Player(var lost: Boolean = false, var width: Int = 0, var height: Int = 0) {
        var created = false
        var texture: TextureRegistry.SurfaceTextureEntry? = null
        var surface: Surface? = null
        var direct = false
        var frameAcknowledged = false
        fun release() {
            texture?.setOnFrameConsumedListener(null)
            surface?.release(); surface = null
            texture?.release(); texture = null
        }
    }
    private class Pending(val result: MethodChannel.Result, val timeout: Runnable,
                          val success: (Any?) -> Unit)

    private val replies = Messenger(Handler(Looper.getMainLooper()) { message ->
        when (message.what) {
            1 -> {
                workerPid = message.data.getInt("pid")
                startupTimeout?.let { handler.removeCallbacks(it) }; startupTimeout = null
                val queued = waiting.toList(); waiting.clear(); queued.forEach { it() }
            }
            3 -> {
                val call = pending.remove(message.arg1)
                if (call != null) {
                    handler.removeCallbacks(call.timeout)
                    if (message.data.getBoolean("ok")) {
                        val bytes = message.data.getByteArray("payload")
                        call.success(bytes?.let { codec.decodeMessage(java.nio.ByteBuffer.wrap(it)) })
                    } else call.result.error("native_playback", "播放器操作失败", null)
                }
            }
            4 -> {
                val bytes = message.data.getByteArray("payload")
                val value = bytes?.let { codec.decodeMessage(java.nio.ByteBuffer.wrap(it)) }
                if (value is Map<*, *> && players[(value["player"] as? Number)?.toInt()]?.lost == false) {
                    sink?.success(value)
                }
            }
        }
        true
    })

    private val connection = object : ServiceConnection {
        override fun onServiceConnected(name: ComponentName, binder: IBinder) {
            if (closed) return
            remote = Messenger(binder)
            try { remote!!.send(Message.obtain(null, 0).apply { replyTo = replies }) }
            catch (_: android.os.RemoteException) { lost() }
        }
        override fun onServiceDisconnected(name: ComponentName) = lost()
        override fun onBindingDied(name: ComponentName) = lost()
        override fun onNullBinding(name: ComponentName) = lost()
    }

    init {
        channel.setMethodCallHandler(this); events.setStreamHandler(this)
        engine.addEngineLifecycleListener(object : FlutterEngine.EngineLifecycleListener {
            override fun onPreEngineRestart() {
                sink = null
                lost(kill = true)
                players.clear()
            }
            override fun onEngineWillDestroy() { close() }
        })
    }
    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) { sink = eventSink }
    override fun onCancel(arguments: Any?) { sink = null }

    private fun bind(action: () -> Unit) {
        if (workerPid > 0 && remote != null) { action(); return }
        waiting.add(action)
        if (bound) return
        val timeout = Runnable { lost("native_process_timeout", kill = true) }
        startupTimeout = timeout
        handler.postDelayed(timeout, 15000)
        bound = context.bindService(Intent(context, FvpPlaybackService::class.java), connection, Context.BIND_AUTO_CREATE)
        if (!bound) lost()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (closed) { result.error("native_process_exited", "播放器已关闭", null); return }
        if (call.method == "create") {
            if (players.size >= 16) { result.error("player_limit", "播放器数量已达上限", null); return }
            val id = ++nextPlayer
            players[id] = Player()
            bind { request("create", id, mapOf("player" to id), result) {
                players[id]?.created = true; result.success(id)
            } }
            return
        }
        val id = call.argument<Number>("player")?.toInt()
        val player = players[id]
        if (id == null || player == null || player.lost) {
            if (call.method == "dispose") { players.remove(id)?.release(); result.success(null) }
            else result.error("native_process_exited", "播放器异常退出", null)
            return
        }
        if (call.method == "texture") {
            if (player.width !in 1..16384 || player.height !in 1..16384) {
                result.error("native_playback", "无效的画面尺寸", null); return
            }
            if (player.texture != null) { result.success(player.texture!!.id()); return }
            val texture = registry.createSurfaceTexture()
            texture.surfaceTexture().setDefaultBufferSize(player.width, player.height)
            texture.setOnFrameConsumedListener {
                handler.post {
                    if (player.direct && !player.frameAcknowledged && !player.lost && players[id] === player) {
                        // Flutter can consume the initial empty texture (timestamp 0)
                        // before MediaCodec reopens against this Surface. Keep the
                        // video pipe running until a video buffer was acquired.
                        if (texture.surfaceTexture().timestamp <= 0L) return@post
                        player.frameAcknowledged = true
                        try { remote?.send(Message.obtain(null, 5).apply { arg1 = id }) }
                        catch (_: android.os.RemoteException) { lost() }
                    }
                }
            }
            player.texture = texture
            player.surface = Surface(texture.surfaceTexture())
            request("surface", id, mapOf("player" to id), result, player.surface) { result.success(texture.id()) }
        } else {
            @Suppress("UNCHECKED_CAST")
            val args = call.arguments as? Map<String, Any?> ?: emptyMap()
            if (call.method == "prepare") player.direct = args["directSurface"] == true && args["software"] != true
            request(call.method, id, args, result) { value ->
                if (call.method == "prepare" && value is Map<*, *>) {
                    player.width = (value["width"] as? Number)?.toInt() ?: 0
                    player.height = (value["height"] as? Number)?.toInt() ?: 0
                    player.direct = value["direct"] == true
                }
                if (call.method == "dispose") { players.remove(id)?.release() }
                result.success(value)
            }
        }
    }

    private fun request(method: String, player: Int, args: Map<String, Any?>,
                        result: MethodChannel.Result, surface: Surface? = null,
                        success: (Any?) -> Unit = { result.success(it) }) {
        if (remote == null || players[player]?.lost != false) {
            if (method == "create") players.remove(player)?.release()
            result.error("native_process_exited", "播放器异常退出", null); return
        }
        if (pending.size >= 64) { result.error("player_busy", "播放器繁忙", null); return }
        val encoded = codec.encodeMessage(args)!!
        if (encoded.position() > 128 * 1024) { result.error("invalid_source", "播放参数过大", null); return }
        val bytes = ByteArray(encoded.position()); encoded.flip(); encoded.get(bytes)
        val request = ++nextRequest
        val timeout = Runnable {
            if (method == "information") {
                pending.remove(request)?.result?.success(null)
            } else lost("native_process_timeout", kill = true)
        }
        pending[request] = Pending(result, timeout, success)
        val deadline = when (method) { "information" -> 1000L; "dispose" -> 9000L; else -> 40000L }
        handler.postDelayed(timeout, deadline)
        try {
            remote!!.send(Message.obtain(null, 2).apply {
                arg1 = request
                data = Bundle().apply {
                    putString("method", method); putInt("player", player); putByteArray("payload", bytes)
                    if (surface != null) {
                        putParcelable("surface", surface)
                        putInt("width", players[player]!!.width); putInt("height", players[player]!!.height)
                    }
                }
            })
        } catch (_: android.os.RemoteException) { lost() }
    }

    /** Test-package-only experiment: retain the old texture until native detach. */
    fun bindBenchmarkSurface(surface: Surface, result: MethodChannel.Result) {
        val player = players.entries.singleOrNull { !it.value.lost }
        if (closed || player == null || !player.value.direct) {
            result.error("benchmark_unavailable", "需要单个已就绪的直出播放器", null); return
        }
        request("surface", player.key, mapOf("player" to player.key), result, surface) {
            result.success(0L)
        }
    }

    private fun lost(code: String = "native_process_exited", kill: Boolean = false) {
        val exitedPid = workerPid
        // Only the PID supplied by our private bound worker is eligible.
        if (kill && workerPid > 0 && workerPid != Process.myPid()) Process.killProcess(workerPid)
        remote = null; workerPid = 0
        startupTimeout?.let { handler.removeCallbacks(it) }; startupTimeout = null
        if (bound) { context.unbindService(connection); bound = false }
        val exit = if (Build.VERSION.SDK_INT >= 30 && exitedPid > 0) {
            try {
                context.getSystemService(ActivityManager::class.java)
                    .getHistoricalProcessExitReasons(context.packageName, exitedPid, 1)
                    .firstOrNull { it.processName == context.packageName + ":fvp_player" }
            } catch (_: Exception) { null }
        } else null
        for ((id, player) in players) {
            if (!player.lost) {
                player.lost = true; player.release()
                sink?.success(mapOf("player" to id, "kind" to "processExited",
                    "exitStatus" to exit?.status?.takeIf { it > 0 }))
            }
        }
        players.entries.removeAll { !it.value.created }
        val failed = pending.values.toList(); pending.clear()
        failed.forEach { handler.removeCallbacks(it.timeout); it.result.error(code, "播放器异常退出，请重新打开视频", null) }
        val queued = waiting.toList(); waiting.clear(); queued.forEach { it() }
    }

    override fun close() {
        if (closed) return
        closed = true
        engineReference.get()?.let { hosts.remove(it) }
        // Engine teardown must also retire an unreachable/hung native worker.
        lost(kill = true)
        players.values.forEach { it.release() }; players.clear()
        channel.setMethodCallHandler(null); events.setStreamHandler(null); sink = null
    }
}
