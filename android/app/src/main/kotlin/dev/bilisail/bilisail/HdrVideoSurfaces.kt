package dev.bilisail.bilisail

import android.app.Activity
import android.content.Context
import android.graphics.PixelFormat
import android.graphics.Rect
import android.view.Display
import android.view.Surface
import android.view.SurfaceControl
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import androidx.annotation.RequiresApi
import com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Keeps mpv's producer Surface alive while inline/fullscreen views exchange parents. */
@RequiresApi(29)
internal class HdrVideoSurfaces : FlutterPlugin, ActivityAware, FlutterEngine.EngineLifecycleListener {
    private var activity: Activity? = null
    private val outputs = mutableMapOf<Long, Output>()
    private lateinit var channel: MethodChannel
    private lateinit var dolbyPlayers: AndroidDolbyPlayers

    private fun transfer(): String? {
        val modes = activity?.window?.decorView?.display?.hdrCapabilities?.supportedHdrTypes
            ?: return null
        return when {
            Display.HdrCapabilities.HDR_TYPE_HDR10 in modes -> "pq"
            Display.HdrCapabilities.HDR_TYPE_HLG in modes -> "hlg"
            else -> null
        }
    }

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        dolbyPlayers = AndroidDolbyPlayers(binding.applicationContext, binding.binaryMessenger,
            createOutput = { width, height -> Output(width, height, decoder = true).also { outputs[it.reference] = it } },
            releaseOutput = { id -> outputs.remove(id)?.close() },
            supportsVideoHdr = { activity?.window?.decorView?.display?.hdrCapabilities?.supportedHdrTypes ?: intArrayOf() })
        binding.flutterEngine.addEngineLifecycleListener(this)
        channel = MethodChannel(binding.binaryMessenger, "bilisail/hdr_video")
        binding.platformViewRegistry.registerViewFactory("bilisail/hdr_video",
            object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
                override fun create(context: Context, id: Int, args: Any?): PlatformView =
                    Host(context, id, (args as? Number)?.toLong())
            })
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "supported" -> result.success(transfer())
                "create" -> {
                    val width = call.argument<Int>("width") ?: 0
                    val height = call.argument<Int>("height") ?: 0
                    if (transfer() == null ||
                        width !in 2..16384 || height !in 2..16384) {
                        result.success(null)
                    } else {
                        try {
                            val output = Output(width, height)
                            outputs[output.reference] = output
                            result.success(output.reference)
                        } catch (error: RuntimeException) {
                            result.error("hdr_surface", error.javaClass.simpleName, null)
                        }
                    }
                }
                "release" -> {
                    outputs.remove((call.arguments as Number).toLong())?.close()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    internal class Output(val width: Int, val height: Int, decoder: Boolean = false) {
        val layer = SurfaceControl.Builder().setName(if (decoder) "BiliSail codec video" else "BiliSail HDR video")
            .setFormat(if (decoder) PixelFormat.OPAQUE else PixelFormat.RGBA_1010102)
            .setBufferSize(width, height).build()
        val surface = try { Surface(layer) } catch (error: RuntimeException) {
            layer.release()
            throw error
        }
        val reference = MediaKitAndroidHelper.newGlobalObjectRef(surface).also {
            if (it == 0L) {
                surface.release()
                layer.release()
                throw IllegalStateException("Could not retain HDR surface")
            }
        }
        private val hosts = sortedMapOf<Int, SurfaceView>()
        fun attach(id: Int, view: SurfaceView) {
            hosts[id] = view
            if (hosts.lastKey() == id) place(view)
        }
        private fun place(view: SurfaceView) {
            val parent = view.surfaceControl
            if (!parent.isValid || !layer.isValid || view.width <= 0 || view.height <= 0) return
            SurfaceControl.Transaction().use { tx ->
                tx.reparent(layer, parent).setLayer(layer, 1)
                    .setGeometry(layer, Rect(0, 0, width, height),
                        Rect(0, 0, view.width, view.height), Surface.ROTATION_0)
                    .setVisibility(layer, true).apply()
            }
        }
        fun detach(id: Int) {
            if (hosts.remove(id) == null || !layer.isValid) return
            if (hosts.isNotEmpty()) place(hosts.getValue(hosts.lastKey()))
            else SurfaceControl.Transaction().use { it.reparent(layer, null).setVisibility(layer, false).apply() }
        }
        fun close() {
            hosts.clear()
            SurfaceControl.Transaction().use { it.reparent(layer, null).setVisibility(layer, false).apply() }
            MediaKitAndroidHelper.deleteGlobalObjectRef(reference)
            surface.release()
            layer.release()
        }
    }

    private inner class Host(context: Context, val id: Int, val key: Long?) : PlatformView, SurfaceHolder.Callback {
        val surfaceView = SurfaceView(context)
        init { surfaceView.holder.addCallback(this) }
        override fun getView(): View = surfaceView
        override fun surfaceCreated(holder: SurfaceHolder) { outputs[key]?.attach(id, surfaceView) }
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
            outputs[key]?.attach(id, surfaceView)
        }
        override fun surfaceDestroyed(holder: SurfaceHolder) { outputs[key]?.detach(id) }
        override fun dispose() {
            surfaceView.holder.removeCallback(this)
            outputs[key]?.detach(id)
        }
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) { activity = binding.activity }
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) = onAttachedToActivity(binding)
    override fun onDetachedFromActivity() { activity = null }
    override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()
    override fun onPreEngineRestart() = dolbyPlayers.releaseSessions()
    override fun onEngineWillDestroy() = Unit
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        binding.flutterEngine.removeEngineLifecycleListener(this)
        channel.setMethodCallHandler(null)
        dolbyPlayers.close()
        for (output in outputs.values) output.close()
        outputs.clear()
    }
}
