package dev.bilisail.bilisail

import android.content.Context
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel

/** Public OS facts only; no Android ID, IMEI, OAID, installed apps or credentials. */
class AppRequestDeviceHandler(context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "dev.bilisail/app_request_device")
    private val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager

    init {
        channel.setMethodCallHandler { call, result ->
            if (call.method != "read") {
                result.notImplemented()
            } else {
                val capabilities = connectivity.getNetworkCapabilities(connectivity.activeNetwork)
                val network = when {
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) == true -> "wifi"
                    capabilities?.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) == true -> "mobile"
                    else -> ""
                }
                result.success(mapOf("model" to Build.MODEL, "osVersion" to Build.VERSION.RELEASE, "network" to network))
            }
        }
    }

    fun close() = channel.setMethodCallHandler(null)
}
