package dev.bilisail.bilisail

import android.app.Activity
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.OrientationEventListener
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Owns immersive bars and observes physical rotation independently of UI locks. */
class MobileWindowHandler(private val activity: Activity, messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val events = EventChannel(messenger, "bilisail/device_orientation")
    private val commands = MethodChannel(messenger, "bilisail/mobile_window")
    private val handler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null
    private var resumed = false
    private var fullScreen = false
    private var candidate: String? = null
    private var delivered: String? = null
    private val publish = Runnable {
        val value = candidate
        if (resumed && value != null && value != delivered) {
            delivered = value
            sink?.success(value)
        }
    }
    private val listener = object : OrientationEventListener(activity) {
        override fun onOrientationChanged(angle: Int) {
            // Ignore flat/diagonal positions; require a stable cardinal posture.
            val value = when (angle) {
                in 0..25, in 155..205, in 335..359 -> "portrait"
                in 65..115, in 245..295 -> "landscape"
                else -> null
            }
            if (value == candidate) return
            candidate = value
            handler.removeCallbacks(publish)
            if (value != null) handler.postDelayed(publish, 250)
        }
    }

    init {
        events.setStreamHandler(this)
        commands.setMethodCallHandler { call, result ->
            if (call.method != "setFullScreen") {
                result.notImplemented()
            } else if (call.arguments !is Boolean) {
                result.error("invalid_argument", "Expected fullscreen flag", null)
            } else {
                fullScreen = call.arguments as Boolean
                applySystemBars()
                result.success(null)
            }
        }
    }

    override fun onListen(arguments: Any?, eventSink: EventChannel.EventSink) {
        sink = eventSink
        delivered = null
        candidate = null
        if (resumed && listener.canDetectOrientation()) listener.enable()
    }

    override fun onCancel(arguments: Any?) {
        listener.disable()
        handler.removeCallbacks(publish)
        candidate = null
        delivered = null
        sink = null
    }

    fun setResumed(value: Boolean) {
        resumed = value
        if (value) {
            candidate = null
            delivered = null
            if (sink != null && listener.canDetectOrientation()) listener.enable()
            if (fullScreen) applySystemBars()
        } else {
            listener.disable()
            handler.removeCallbacks(publish)
            candidate = null
        }
    }

    @Suppress("DEPRECATION")
    fun applySystemBars() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.window.insetsController?.let { controller ->
                if (fullScreen) {
                    controller.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                    controller.hide(WindowInsets.Type.systemBars())
                } else {
                    controller.show(WindowInsets.Type.systemBars())
                }
            }
        } else {
            val decor = activity.window.decorView
            // Preserve Flutter's theme-driven icon colors when changing only
            // visibility. Otherwise API 26-29 restores white icons on white.
            val appearance = decor.systemUiVisibility and
                (View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR or View.SYSTEM_UI_FLAG_LIGHT_NAVIGATION_BAR)
            decor.systemUiVisibility = appearance or if (fullScreen) {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_HIDE_NAVIGATION or View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
            } else {
                View.SYSTEM_UI_FLAG_LAYOUT_STABLE or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN or
                    View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
            }
        }
    }

    fun reapplyFullScreen() {
        if (fullScreen) applySystemBars()
    }

    fun close() {
        onCancel(null)
        events.setStreamHandler(null)
        commands.setMethodCallHandler(null)
        if (fullScreen) {
            fullScreen = false
            applySystemBars()
        }
    }
}
