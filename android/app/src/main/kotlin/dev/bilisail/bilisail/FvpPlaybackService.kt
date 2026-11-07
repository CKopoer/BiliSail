package dev.bilisail.bilisail

import android.app.Service
import android.app.ActivityManager
import android.content.Intent
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Message
import android.os.Messenger
import android.os.ParcelFileDescriptor
import android.os.Process
import android.view.Surface
import com.mediadevkit.fvp.BiliSailRemoteSurface
import com.mediadevkit.fvp.FvpPlugin
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec

/** Same UID for content permissions, separate address space for native faults. */
class FvpPlaybackService : Service() {
    private lateinit var engine: FlutterEngine
    private lateinit var channel: MethodChannel
    private val codec = StandardMessageCodec.INSTANCE
    private var client: Messenger? = null
    private var ready = false
    private var ownsProcess = false
    private val queued = mutableListOf<Message>()
    private data class Output(val surface: Surface, val width: Int, val height: Int)
    private val outputs = mutableMapOf<Int, Output>()
    private val descriptors = mutableMapOf<String, ParcelFileDescriptor>()
    private var nextLease = 0
    private val incoming = Messenger(Handler(Looper.getMainLooper()) { message ->
        if (message.what == 0) {
            client = message.replyTo
            if (ready) sendReady()
        } else if (message.what == 2) {
            if (ready) execute(message) else if (queued.size < 64) queued.add(Message.obtain(message))
        } else if (message.what == 5 && ready) {
            channel.invokeMethod("frameConsumed", mapOf("player" to message.arg1))
        }
        true
    })

    override fun onCreate() {
        super.onCreate()
        ownsProcess = getSystemService(ActivityManager::class.java).runningAppProcesses
            ?.any { it.pid == Process.myPid() && it.processName == packageName + ":fvp_player" } == true
        if (!ownsProcess) { stopSelf(); return }
        val loader = FlutterInjector.instance().flutterLoader()
        loader.startInitialization(this)
        loader.ensureInitializationComplete(this, null)
        // Deliberately register only the video plugin: no app credentials,
        // database, audio_service engine, or normal app startup in this process.
        engine = FlutterEngine(this, null, false)
        engine.plugins.add(FvpPlugin())
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.bilisail/fvp_worker")
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "ready" -> {
                    ready = true; sendReady()
                    val pending = queued.toList(); queued.clear(); pending.forEach { execute(it) }
                    result.success(null)
                }
                "event" -> { send(4, 0, call.arguments); result.success(null) }
                "bindSurface" -> {
                    val id = call.argument<Number>("player")!!.toInt()
                    val output = outputs[id]
                    if (output == null) result.error("surface_missing", "画面不可用", null)
                    else {
                        BiliSailRemoteSurface.attach(call.argument<Number>("handle")!!.toLong(),
                            surfaceId(id), output.surface, output.width, output.height,
                            call.argument<Boolean>("direct") == true)
                        result.success(null)
                    }
                }
                "unbindSurface" -> {
                    val id = call.argument<Number>("player")!!.toInt()
                    if (outputs.containsKey(id)) {
                        BiliSailRemoteSurface.detach(surfaceId(id))
                        outputs.remove(id)?.surface?.release()
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(engine.dartExecutor.binaryMessenger, "dev.bilisail/download_storage")
            .setMethodCallHandler { call, result -> handleDescriptor(call, result) }
        engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(
            loader.findAppBundlePath(), "package:bili_player/src/fvp_native_player.dart", "fvpWorkerMain"))
    }

    private fun surfaceId(id: Int) = -1L - id.toLong()
    override fun onBind(intent: Intent): IBinder = incoming.binder
    private fun sendReady() {
        try { client?.send(Message.obtain(null, 1).apply { data = Bundle().apply { putInt("pid", Process.myPid()) } }) }
        catch (_: android.os.RemoteException) { stopSelf() }
    }
    private fun send(type: Int, request: Int, value: Any?, ok: Boolean = true) {
        val encoded = codec.encodeMessage(value)
        val bytes = encoded?.let { ByteArray(it.position()).apply { it.flip(); it.get(this) } }
        try {
            client?.send(Message.obtain(null, type).apply {
                arg1 = request; data = Bundle().apply { putBoolean("ok", ok); putByteArray("payload", bytes) }
            })
        } catch (_: android.os.RemoteException) { stopSelf() }
    }
    private fun execute(message: Message) {
        val method = message.data.getString("method") ?: return
        val id = message.data.getInt("player")
        if (method == "surface") {
            @Suppress("DEPRECATION")
            val surface = message.data.getParcelable<Surface>("surface") ?: return
            outputs[id] = Output(surface, message.data.getInt("width"), message.data.getInt("height"))
        }
        val bytes = message.data.getByteArray("payload") ?: return
        val args = codec.decodeMessage(java.nio.ByteBuffer.wrap(bytes))
        val request = message.arg1
        channel.invokeMethod(method, args, object : MethodChannel.Result {
            override fun success(value: Any?) = send(3, request, value)
            override fun error(code: String, text: String?, details: Any?) = send(3, request, null, false)
            override fun notImplemented() = send(3, request, null, false)
        })
    }

    private fun handleDescriptor(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "openMedia" -> {
                    if (descriptors.size >= 64) throw IllegalStateException()
                    val uri = android.net.Uri.parse(call.argument<String>("uri"))
                    if (uri.scheme != "content") throw IllegalArgumentException()
                    val fd = contentResolver.openFileDescriptor(uri, "r") ?: throw IllegalStateException()
                    val lease = (++nextLease).toString(); descriptors[lease] = fd
                    result.success(mapOf("lease" to lease, "fd" to fd.fd))
                }
                "closeMedia" -> { descriptors.remove(call.argument<String>("lease"))?.close(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (_: Exception) { result.error("media_unavailable", "无法读取本地媒体", null) }
    }

    override fun onDestroy() {
        // Do not let a wedged native destructor block service or UI teardown.
        // Every worker resource belongs to this private process.
        if (ownsProcess) Process.killProcess(Process.myPid())
        super.onDestroy()
    }
}
