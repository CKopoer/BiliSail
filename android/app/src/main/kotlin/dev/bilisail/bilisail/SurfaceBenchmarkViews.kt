package dev.bilisail.bilisail

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.view.View
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

/** Registered only in the independent .test application; never a product mode. */
class SurfaceBenchmarkViews(private val engine: FlutterEngine) : AutoCloseable {
    private val views = mutableMapOf<Int, Output>()
    private val channel = MethodChannel(engine.dartExecutor.binaryMessenger, "dev.bilisail/surface_benchmark")
    private val handler = Handler(Looper.getMainLooper())
    private val helper by lazy { Class.forName("com.alexmercerind.mediakitandroidhelper.MediaKitAndroidHelper") }
    private fun retain(surface: Any) = (helper.getDeclaredMethod("newGlobalObjectRef", Any::class.java)
        .apply { isAccessible = true }.invoke(null, surface) as Number).toLong()
    private fun release(reference: Long) {
        helper.getDeclaredMethod("deleteGlobalObjectRef", Long::class.javaPrimitiveType)
            .apply { isAccessible = true }.invoke(null, reference)
    }
    init {
        engine.platformViewsController.registry.registerViewFactory("dev.bilisail/surface_benchmark", object : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
            override fun create(context: Context, id: Int, args: Any?): PlatformView {
                val output = Output(context, id)
                views[id] = output
                return output
            }
        })
        channel.setMethodCallHandler { call, result ->
            if (call.method == "composition") {
                result.success(mapOf("hcpp" to engine.platformViewsController2.isHcppEnabled))
                return@setMethodCallHandler
            }
            val output = views[call.argument<Number>("id")?.toInt()]
            if (call.method != "surface" || output == null) result.error("unavailable", "实验画面不存在", null)
            else output.waitForSurface(result)
        }
    }
    private inner class Output(context: Context, val id: Int) : PlatformView, SurfaceHolder.Callback {
        val view = SurfaceView(context)
        var reference = 0L
        var ready = false
        var disposed = false
        var pending: MethodChannel.Result? = null
        val timeout = Runnable { pending?.error("surface_timeout", "实验画面准备超时", null); pending = null }
        init {
            view.setZOrderOnTop(false)
            if (engine.platformViewsController2.isHcppEnabled) view.holder.setSizeFromLayout()
            else view.holder.setFixedSize(3840, 2160)
            view.holder.addCallback(this)
        }
        override fun getView(): View = view
        fun waitForSurface(result: MethodChannel.Result) {
            if (ready) result.success(reference)
            else if (pending != null || disposed) result.error("unavailable", "实验画面不可用", null)
            else { pending = result; handler.postDelayed(timeout, 15000) }
        }
        fun complete(value: Long) {
            if (disposed) return
            ready = true; reference = value
            handler.removeCallbacks(timeout); pending?.success(value); pending = null
        }
        override fun surfaceCreated(holder: SurfaceHolder) {
            complete(retain(holder.surface))
        }
        override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}
        override fun surfaceDestroyed(holder: SurfaceHolder) { ready = false }
        override fun dispose() {
            if (disposed) return
            disposed = true
            handler.removeCallbacks(timeout)
            pending?.error("disposed", "实验画面已关闭", null); pending = null
            // The probe closes the engine before unmounting this platform view.
            if (reference != 0L) { release(reference); reference = 0 }
            view.holder.removeCallback(this); views.remove(id)
        }
    }
    override fun close() {
        views.values.toList().forEach { it.dispose() }
        channel.setMethodCallHandler(null)
    }
}
