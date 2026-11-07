package dev.bilisail.bilisail

import android.app.Activity
import android.app.PictureInPictureParams
import android.content.pm.PackageManager
import android.graphics.Rect
import android.os.Build
import android.util.Rational
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Uses the existing activity; the audio_service MediaSession supplies controls. */
class PictureInPictureHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bilisail/picture_in_picture")
    private val supported: Boolean
        get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            activity.packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(supported)
                "enter" -> {
                    if (!supported) {
                        result.success(false)
                    } else {
                        try {
                            val ratio = (call.argument<Number>("aspectRatio")?.toDouble() ?: (16.0 / 9))
                                .coerceIn(1.0 / 2.39, 2.39)
                            val source = Rect()
                            activity.window.decorView.getGlobalVisibleRect(source)
                            val params = PictureInPictureParams.Builder()
                                .setAspectRatio(Rational((ratio * 10000).toInt(), 10000))
                                .setSourceRectHint(source)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                                params.setSeamlessResizeEnabled(true)
                            }
                            result.success(activity.enterPictureInPictureMode(params.build()))
                        } catch (error: IllegalStateException) {
                            result.error("pip_unavailable", "当前无法进入系统小窗", null)
                        } catch (error: IllegalArgumentException) {
                            result.error("pip_unavailable", "系统小窗不可用", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    fun changed(active: Boolean) { channel.invokeMethod("changed", active) }
    fun close() { channel.setMethodCallHandler(null) }
}
