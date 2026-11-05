package dev.bilisail.bilisail

import android.Manifest
import android.app.Activity
import android.content.ContentValues
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

/** Publishes user-requested ZIPs without granting access to private app data. */
internal class LogExportHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, "bilisail/log_export")
    private val worker = Executors.newSingleThreadExecutor()
    private var permission: Pair<MethodCall, MethodChannel.Result>? = null
    private var pending: MethodChannel.Result? = null
    private var closed = false

    init { channel.setMethodCallHandler { call, result -> handle(call, result) } }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "deviceInfo") {
            result.success(mapOf("manufacturer" to Build.MANUFACTURER, "model" to Build.MODEL,
                "androidVersion" to Build.VERSION.RELEASE, "androidSdk" to Build.VERSION.SDK_INT,
                "supportedAbis" to Build.SUPPORTED_ABIS.toList()))
            return
        }
        if (call.method != "save") { result.notImplemented(); return }
        if (closed || pending != null) { result.error("busy", "日志正在导出", null); return }
        val bytes = call.argument<ByteArray>("bytes")
        val name = call.argument<String>("name")
        if (bytes == null || bytes.isEmpty() || bytes.size > 10 * 1024 * 1024 ||
            name == null || !Regex("^BiliSail-logs-[0-9]+-[0-9]+\\.zip$").matches(name)) {
            result.error("invalid_archive", "日志压缩包无效", null); return
        }
        pending = result
        if (Build.VERSION.SDK_INT < 29 &&
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) != PackageManager.PERMISSION_GRANTED) {
            permission = Pair(call, result)
            activity.requestPermissions(arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE), permissionRequest)
            return
        }
        worker.execute {
            try {
                val location = save(bytes, name)
                activity.runOnUiThread {
                    if (!closed) { pending = null; result.success(location) }
                }
            } catch (_: Exception) {
                activity.runOnUiThread {
                    if (!closed) { pending = null; result.error("export_failed", "无法保存日志，请检查存储空间和权限", null) }
                }
            }
        }
    }

    private fun save(bytes: ByteArray, name: String): String {
        if (Build.VERSION.SDK_INT >= 29) {
            val resolver = activity.contentResolver
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                put(MediaStore.MediaColumns.MIME_TYPE, "application/zip")
                put(MediaStore.MediaColumns.RELATIVE_PATH, "${Environment.DIRECTORY_DOWNLOADS}/BiliSail/logs")
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = checkNotNull(resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values))
            try {
                checkNotNull(resolver.openOutputStream(uri, "w")).use { it.write(bytes) }
                check(resolver.update(uri, ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }, null, null) == 1)
            } catch (error: Exception) { resolver.delete(uri, null, null); throw error }
        } else {
            @Suppress("DEPRECATION")
            val directory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "BiliSail/logs")
            check(directory.isDirectory || directory.mkdirs())
            val file = File(directory, name)
            val partial = File(directory, "$name.partial")
            try {
                partial.outputStream().use { stream -> stream.write(bytes); stream.fd.sync() }
                check(!file.exists() && partial.renameTo(file))
            } finally { partial.delete() }
            MediaScannerConnection.scanFile(activity, arrayOf(file.absolutePath), arrayOf("application/zip"), null)
        }
        return "${Environment.DIRECTORY_DOWNLOADS}/BiliSail/logs/$name"
    }

    fun onPermissionResult(requestCode: Int, grants: IntArray) {
        if (requestCode != permissionRequest) return
        val request = permission ?: return
        permission = null
        pending = null
        if (grants.firstOrNull() == PackageManager.PERMISSION_GRANTED) handle(request.first, request.second)
        else request.second.error("permission_denied", "保存日志需要存储权限", null)
    }

    fun close() {
        closed = true
        pending?.error("cancelled", "日志导出已取消", null)
        pending = null
        permission = null
        channel.setMethodCallHandler(null)
        worker.shutdown()
    }

    private companion object { const val permissionRequest = 24026 }
}
