package dev.bilisail.bilisail

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodChannel

class DownloadExecutionPlugin : FlutterPlugin {
    private lateinit var channel: MethodChannel

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "dev.bilisail/background_downloads")
        channel.setMethodCallHandler { call, result ->
            if (call.method != "setActive") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            try {
                if (call.arguments == true) {
                    DownloadForegroundService.start(context, result) { channel.invokeMethod("timeout", null) }
                } else {
                    DownloadForegroundService.stop()
                    result.success(null)
                }
            } catch (error: RuntimeException) {
                result.error("foreground_service", "Cannot start download service.", null)
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        DownloadForegroundService.stop()
        channel.setMethodCallHandler(null)
    }
}

class DownloadForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    companion object {
        private const val CHANNEL = "offline_downloads"
        private const val NOTIFICATION_ID = 0x444c
        // Accessed only on the main thread. A very short run can end before
        // Android delivers onStartCommand; it must still promote before stopping.
        private var onTimeoutReached: (() -> Unit)? = null
        private var instance: DownloadForegroundService? = null
        private val starting = mutableListOf<MethodChannel.Result>()

        fun start(context: Context, result: MethodChannel.Result, onTimeout: () -> Unit) {
            val intent = Intent(context, DownloadForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent)
            else context.startService(intent)
            starting.add(result)
            onTimeoutReached = onTimeout
        }

        fun stop() {
            onTimeoutReached = null
            instance?.stopSelf()
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        instance = this
        val builder = if (Build.VERSION.SDK_INT >= 26) {
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "离线下载", NotificationManager.IMPORTANCE_LOW)
            )
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        packageManager.getLaunchIntentForPackage(packageName)?.let { launch ->
            val pendingFlags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            builder.setContentIntent(PendingIntent.getActivity(this, 0, launch, pendingFlags))
        }
        val notification = builder.setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentTitle("正在下载离线媒体")
            .setOngoing(true)
            .build()
        try {
            startForeground(NOTIFICATION_ID, notification)
        } catch (error: RuntimeException) {
            starting.forEach { it.error("foreground_service", "Cannot promote download service.", null) }
            starting.clear()
            stop()
            return START_NOT_STICKY
        }
        starting.forEach { it.success(null) }
        starting.clear()
        if (onTimeoutReached == null) {
            stopSelfResult(startId)
        } else if (wakeLock?.isHeld != true) {
            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = power.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "BiliSail:OfflineDownloads")
                .apply { acquire(6 * 60 * 60 * 1000L) }
        }
        return START_NOT_STICKY
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        onTimeoutReached?.invoke()
        stop()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        wakeLock?.let { if (it.isHeld) it.release() }
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
