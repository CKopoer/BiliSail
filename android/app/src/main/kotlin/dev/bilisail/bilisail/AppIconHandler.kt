package dev.bilisail.bilisail

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

class AppIconHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bilisail/app_icon")
    // Keep class names in the production namespace; packageName also includes
    // .test for development builds, so ComponentName must use both separately.
    private val aliases = mapOf(
        "bilisail" to ComponentName(activity.packageName, "dev.bilisail.bilisail.LauncherDefault"),
        "bilibili" to ComponentName(activity.packageName, "dev.bilisail.bilisail.LauncherBilibili"),
    )

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getIcon" -> result.success(currentIcon())
                "setIcon" -> {
                    val icon = call.argument<String>("icon")
                    if (icon == null || icon !in aliases) {
                        result.error("invalid_icon", "Unknown application icon.", null)
                    } else {
                        val previous = currentIcon()
                        try {
                            select(icon)
                            result.success(null)
                        } catch (error: RuntimeException) {
                            try { select(previous) } catch (_: RuntimeException) { /* Retried on the next explicit change. */ }
                            result.error("icon_change_failed", "Cannot change the launcher icon.", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun currentIcon(): String {
        val state = activity.packageManager.getComponentEnabledSetting(aliases.getValue("bilibili"))
        return if (state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED) "bilibili" else "bilisail"
    }

    private fun select(icon: String) {
        val manager = activity.packageManager
        fun state(name: String) = if (name == icon) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            else PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        if (Build.VERSION.SDK_INT >= 33) {
            manager.setComponentEnabledSettings(aliases.map { (name, component) ->
                PackageManager.ComponentEnabledSetting(component, state(name), PackageManager.DONT_KILL_APP)
            })
        } else {
            // Enable the target first so interruption never leaves no launcher.
            manager.setComponentEnabledSetting(aliases.getValue(icon), state(icon), PackageManager.DONT_KILL_APP)
            aliases.filterKeys { it != icon }.forEach { (name, component) ->
                manager.setComponentEnabledSetting(component, state(name), PackageManager.DONT_KILL_APP)
            }
        }
        activity.setTaskDescription(android.app.ActivityManager.TaskDescription(
            activity.applicationInfo.loadLabel(manager).toString(),
            android.graphics.BitmapFactory.decodeResource(activity.resources,
                if (icon == "bilibili") R.mipmap.ic_launcher_bilibili else R.mipmap.ic_launcher),
        ))
    }

    fun close() { channel.setMethodCallHandler(null) }
}
