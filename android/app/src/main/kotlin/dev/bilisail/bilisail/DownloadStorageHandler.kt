package dev.bilisail.bilisail

import android.app.Activity
import android.Manifest
import android.content.ActivityNotFoundException
import android.content.ContentValues
import android.content.Intent
import android.content.pm.PackageManager
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.CancellationSignal
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.system.Os
import android.system.OsConstants
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Publishes only owned files; legacy provider URIs remain readable/deletable. */
internal class DownloadStorageHandler(private val activity: Activity, messenger: BinaryMessenger) {
    private val resolver = activity.contentResolver
    private val prefs = activity.getSharedPreferences("download_storage_v1", Activity.MODE_PRIVATE)
    private val channel = MethodChannel(messenger, "dev.bilisail/download_storage")
    private val worker = Executors.newFixedThreadPool(5)
    private val main = Handler(Looper.getMainLooper())
    private val cancellations = ConcurrentHashMap<String, AtomicBoolean>()
    private val leases = ConcurrentHashMap<String, ParcelFileDescriptor>()
    private val taskLocks = ConcurrentHashMap<String, Any>()
    private val closed = AtomicBoolean(false)
    private var picker: MethodChannel.Result? = null
    private val requestCode = 5714
    private val names = setOf("video.m4s", "audio.m4s", "media.mp4", "media.mkv")

    init { channel.setMethodCallHandler(::call) }

    private fun call(call: MethodCall, result: MethodChannel.Result) {
        if (closed.get()) { result.error("storage", "存储服务已关闭", null); return }
        if (call.method == "hasDestination") {
            val destination = prefs.getString("destination", null)
            result.success(when (destination) {
                null -> false
                else -> destination.startsWith("file:") && hasStorageAccess()
            })
            return
        }
        if (call.method == "requestAccess") {
            requestAccess(result)
            return
        }
        if (call.method == "cancel") {
            cancellations[key(call)]?.set(true); result.success(null); return
        }
        val cancel = if (call.method == "publish") AtomicBoolean(false) else null
        if (cancel != null) cancellations[key(call)] = cancel
        worker.execute {
            try {
                val value: Any? = when (call.method) {
                    "listDirectories" -> listDirectories(call.argument<String>("directory"))
                    "choose" -> {
                        val folder = externalDirectory(call.argument<String>("directory") ?: throw IllegalArgumentException())
                        val probe = File.createTempFile(".bilisail-access-", ".tmp", folder)
                        try { probe.outputStream().use { it.fd.sync() } } finally { probe.delete() }
                        if (!prefs.edit().putString("destination", Uri.fromFile(folder).toString()).commit()) {
                            throw IOException("保存下载位置失败")
                        }
                        null
                    }
                    "destination" -> {
                        val destination = prefs.getString("destination", null)
                        if (destination?.startsWith("file:") == true) externalDirectory(Uri.parse(destination).path!!)
                        else if (destination != null && destination != "downloads") root(destination, write = true)
                        destination
                    }
                    "publish" -> synchronized(taskLocks.getOrPut(key(call)) { Any() }) { publish(call, cancel!!) }
                    "verify" -> synchronized(taskLocks.getOrPut(key(call)) { Any() }) { verify(call); null }
                    "delete" -> synchronized(taskLocks.getOrPut(key(call)) { Any() }) { delete(call); null }
                    "openMedia" -> openMedia(call.argument<String>("uri")!!)
                    "closeMedia" -> { leases.remove(call.argument<String>("lease"))?.close(); null }
                    else -> throw IllegalArgumentException("不支持的存储操作")
                }
                main.post { result.success(value) }
            } catch (e: Exception) {
                val message = when (e) {
                    is SecurityException -> "下载位置授权已失效，请在设置中重新选择原目录"
                    is java.io.FileNotFoundException -> "公共音视频文件不存在，或存储设备已离线"
                    is UnsupportedOperationException -> "此位置不支持本地视频随机读取，请选择设备上的目录"
                    is IllegalArgumentException -> "下载文件归属或保存位置无效"
                    else -> e.message ?: "公共保存失败，请检查剩余空间、目录授权和存储设备"
                }
                main.post { result.error(if (e is SecurityException) "permission" else "storage", message, null) }
            } finally {
                if (cancel != null) cancellations.remove(key(call), cancel)
            }
        }
    }

    private fun finishPicker(value: Boolean) { picker?.success(value); picker = null }

    private fun hasStorageAccess(): Boolean = if (Build.VERSION.SDK_INT >= 30) {
        Environment.isExternalStorageManager()
    } else {
        activity.checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
            activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
    }

    private fun requestAccess(result: MethodChannel.Result) {
        if (picker != null) { result.error("busy", "请先完成存储授权", null); return }
        if (hasStorageAccess()) { result.success(true); return }
        picker = result
        try {
            if (Build.VERSION.SDK_INT >= 30) {
                try {
                    activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                        Uri.parse("package:${activity.packageName}")), requestCode)
                } catch (_: ActivityNotFoundException) {
                    activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION), requestCode)
                }
            } else if (prefs.getBoolean("requested_storage", false) &&
                !activity.shouldShowRequestPermissionRationale(Manifest.permission.WRITE_EXTERNAL_STORAGE) &&
                !activity.shouldShowRequestPermissionRationale(Manifest.permission.READ_EXTERNAL_STORAGE)) {
                activity.startActivityForResult(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                    Uri.parse("package:${activity.packageName}")), requestCode)
            } else {
                prefs.edit().putBoolean("requested_storage", true).apply()
                activity.requestPermissions(arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE,
                    Manifest.permission.WRITE_EXTERNAL_STORAGE), requestCode)
            }
        } catch (_: Exception) { picker?.error("permission", "无法打开存储授权窗口，请在系统设置中允许文件访问", null); picker = null }
    }

    fun onActivityResult(code: Int): Boolean {
        if (code != requestCode) return false
        finishPicker(hasStorageAccess())
        return true
    }

    fun onPermissionResult(code: Int) {
        if (code == requestCode) finishPicker(hasStorageAccess())
    }

    private fun storageRoots(): List<File> {
        val primary = Environment.getExternalStorageDirectory().absoluteFile
        val additional = activity.getExternalFilesDirs(null).mapNotNull {
            it?.parentFile?.parentFile?.parentFile?.parentFile?.absoluteFile
        }
        return (listOf(primary) + additional).distinctBy { it.path }.filter { it.isDirectory }
    }

    // Platform storage roots may have system aliases. Trust those exact anchors,
    // but reject symlinks, dot segments and Android's private trees below them.
    private fun externalDirectory(path: String): File {
        if (!hasStorageAccess()) throw SecurityException()
        require(File(path).isAbsolute && path.split('/').none { it == "." || it == ".." })
        val folder = File(path).absoluteFile
        val boundary = storageRoots().firstOrNull { folder == it || folder.path.startsWith(it.path + "/") }
            ?: throw IOException("存储设备已离线或此目录不在共享存储中")
        val relative = folder.path.removePrefix(boundary.path).trimStart('/')
        require(relative != "Android" && !relative.startsWith("Android/"))
        var component = folder
        while (component != boundary) {
            if (!component.exists()) throw IOException("文件夹已不存在或存储设备已离线")
            require(!OsConstants.S_ISLNK(Os.lstat(component.path).st_mode))
            component = component.parentFile ?: throw IllegalArgumentException()
        }
        if (!folder.isDirectory || !folder.canRead()) throw IOException("无法读取此文件夹")
        return folder
    }

    private fun folderInfo(folder: File): Map<String, String> = mapOf("path" to folder.path, "name" to folder.name)

    private fun listDirectories(path: String?): Map<String, Any?> {
        if (!hasStorageAccess()) throw SecurityException()
        if (path == null) return mapOf("directory" to null, "parent" to null,
            "folders" to storageRoots().mapIndexed { index, folder ->
                mapOf("path" to folder.path, "name" to if (index == 0) "内部存储" else "存储设备 ${folder.name}")
            })
        val folder = externalDirectory(path)
        val children = folder.listFiles() ?: throw IOException("无法读取此文件夹")
        val directories = children.asSequence().filter {
            it.isDirectory && it.name != "Android" && !it.name.startsWith(".") &&
                !OsConstants.S_ISLNK(Os.lstat(it.path).st_mode)
        }.take(2001).toList().sortedBy { it.name.lowercase() }
        return mapOf("directory" to folderInfo(folder),
            "parent" to if (storageRoots().any { it == folder }) null else folder.parent,
            "folders" to directories.take(2000).map(::folderInfo), "truncated" to (directories.size > 2000))
    }

    private fun key(call: MethodCall): String {
        val id = call.argument<String>("id") ?: throw IllegalArgumentException()
        require(Regex("[0-9a-f]{32}").matches(id))
        val scope = call.argument<String>("scope") ?: throw IllegalArgumentException()
        val digest = MessageDigest.getInstance("SHA-256").digest(scope.toByteArray())
            .joinToString("") { "%02x".format(it) }
        return "task_${digest}_$id"
    }

    private fun read(key: String): JSONObject? = prefs.getString(key, null)?.let(::JSONObject)
    private fun save(key: String, record: JSONObject) {
        if (!prefs.edit().putString(key, record.toString()).commit()) throw IOException("保存公共文件索引失败")
    }
    private fun items(record: JSONObject): Map<String, String> {
        val obj = record.getJSONObject("items")
        return obj.keys().asSequence().associateWith { obj.getString(it) }
    }
    private fun root(destination: String, write: Boolean = false): Uri {
        val tree = Uri.parse(destination)
        require(tree.scheme == "content" && DocumentsContract.isTreeUri(tree))
        if (resolver.persistedUriPermissions.none { it.uri == tree && it.isReadPermission && (!write || it.isWritePermission) }) {
            throw SecurityException()
        }
        val document = DocumentsContract.buildDocumentUriUsingTree(tree, DocumentsContract.getTreeDocumentId(tree))
        try {
            resolver.query(document, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use {
                if (!it.moveToFirst()) throw IOException("保存目录或存储设备不可用，请连接后重试")
            } ?: throw IOException("保存目录或存储设备不可用，请连接后重试")
        } catch (_: java.io.FileNotFoundException) {
            throw IOException("保存目录或存储设备不可用，请连接后重试")
        }
        return document
    }

    private fun checkBoundary(record: JSONObject, uri: Uri) {
        val destination = record.getString("destination")
        require(items(record).containsValue(uri.toString()))
        if (destination.startsWith("file:")) {
            require(uri.scheme == "file")
            val folder = externalDirectory(Uri.parse(destination).path!!)
            val name = items(record).entries.first { it.value == uri.toString() }.key
            val file = File(folder, "${record.getString("taskId")}_$name")
            require(uri == Uri.fromFile(file))
            if (!file.exists()) throw java.io.FileNotFoundException()
            require(!OsConstants.S_ISLNK(Os.lstat(file.path).st_mode) && file.isFile)
        } else if (destination == "downloads") {
            require(uri.scheme == "content")
            require(Build.VERSION.SDK_INT >= 29 && uri.authority == MediaStore.AUTHORITY)
            resolver.query(uri, arrayOf(MediaStore.MediaColumns.RELATIVE_PATH), null, null, null)?.use {
                if (!it.moveToFirst()) throw java.io.FileNotFoundException()
                require(it.getString(0) == record.getString("relativePath"))
            } ?: throw java.io.FileNotFoundException()
        } else {
            require(uri.scheme == "content")
            val parent = root(destination)
            resolver.query(uri, arrayOf(DocumentsContract.Document.COLUMN_DOCUMENT_ID), null, null, null)?.use {
                if (!it.moveToFirst()) throw java.io.FileNotFoundException()
            } ?: throw java.io.FileNotFoundException()
            require(uri.authority == parent.authority && DocumentsContract.isChildDocument(resolver, parent, uri))
        }
    }

    private fun readable(uri: Uri): ParcelFileDescriptor {
        if (uri.scheme == "file") return ParcelFileDescriptor.open(File(uri.path!!), ParcelFileDescriptor.MODE_READ_ONLY)
        val signal = CancellationSignal()
        val timeout = Runnable { signal.cancel() }
        main.postDelayed(timeout, 15000)
        val fd = try {
            resolver.openFileDescriptor(uri, "r", signal) ?: throw java.io.FileNotFoundException()
        } finally { main.removeCallbacks(timeout) }
        try { Os.lseek(fd.fileDescriptor, 0, OsConstants.SEEK_CUR) }
        catch (_: Exception) { fd.close(); throw UnsupportedOperationException() }
        return fd
    }

    private fun verify(call: MethodCall) {
        val record = read(key(call)) ?: throw IllegalArgumentException()
        require(record.getBoolean("ready") && record.getString("destination") == call.argument<String>("destination"))
        val actual = items(record)
        require(actual == call.argument<Map<String, String>>("uris"))
        for ((name, value) in actual) {
            val uri = Uri.parse(value)
            try { checkBoundary(record, uri); readable(uri).close() }
            catch (e: java.io.FileNotFoundException) {
                throw IOException(if (name == "audio.m4s") "公共音频文件不存在或设备已离线" else "公共视频文件不存在或设备已离线")
            }
        }
    }

    private fun publish(call: MethodCall, cancelled: AtomicBoolean): Map<String, String> {
        val key = key(call)
        val destination = call.argument<String>("destination") ?: throw IllegalArgumentException()
        val files = call.argument<Map<String, String>>("files") ?: throw IllegalArgumentException()
        require(files.keys == setOf("video.m4s", "audio.m4s") ||
            files.keys == setOf("media.mp4") || files.keys == setOf("media.mkv"))
        var record = read(key)
        if (record != null) {
            require(record.getString("destination") == destination)
            if (record.getBoolean("ready")) {
                for (value in items(record).values) { val uri = Uri.parse(value); checkBoundary(record, uri); readable(uri).close() }
                return items(record)
            }
            deleteRecord(key, record)
        }
        if (destination.startsWith("file:")) externalDirectory(Uri.parse(destination).path!!)
        else if (destination == "downloads") require(Build.VERSION.SDK_INT >= 29) else root(destination, write = true)
        val id = call.argument<String>("id")!!
        val relative = "${Environment.DIRECTORY_DOWNLOADS}/BiliSail/$id/"
        record = JSONObject().put("destination", destination).put("relativePath", relative)
            .put("taskId", id).put("ready", false).put("items", JSONObject())
        save(key, record)
        for ((name, path) in files) {
            if (cancelled.get()) throw IOException("保存已暂停，临时文件已保留")
            require(name in names)
            val source = File(path)
            // Trust the exact platform-owned app directory, including its system
            // ancestor aliases. Inspect only user-controlled descendants, just
            // like the Dart file store; never canonicalize or walk above it.
            val boundary = activity.getDir("flutter", Activity.MODE_PRIVATE).absoluteFile
            require(source.name == name && source.parentFile?.name == id)
            require(source.absolutePath.startsWith(boundary.path + File.separator))
            require(source.path.split(File.separatorChar).none { it == ".." || it == "." })
            var component = source.absoluteFile
            while (component != boundary) {
                require(!OsConstants.S_ISLNK(Os.lstat(component.path).st_mode))
                component = component.parentFile ?: throw IllegalArgumentException()
            }
            val mime = downloadMimeType(name)
            val uri = if (destination.startsWith("file:")) {
                val target = File(externalDirectory(Uri.parse(destination).path!!), "${id}_$name")
                if (!target.createNewFile()) throw IOException("目标文件已存在，请更换文件夹后重试")
                Uri.fromFile(target)
            } else if (destination == "downloads") {
                val values = ContentValues().apply {
                    put(MediaStore.MediaColumns.DISPLAY_NAME, name)
                    put(MediaStore.MediaColumns.MIME_TYPE, mime)
                    put(MediaStore.MediaColumns.RELATIVE_PATH, relative)
                    put(MediaStore.MediaColumns.IS_PENDING, 1)
                }
                resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values) ?: throw IOException("无法创建下载文件")
            } else {
                // Unique per-task names avoid collisions without deleting existing documents.
                DocumentsContract.createDocument(resolver, root(destination, write = true), mime, "${id}_$name")
                    ?: throw IOException("无法创建下载文件")
            }
            record.getJSONObject("items").put(name, uri.toString())
            save(key, record)
            checkBoundary(record, uri)
            source.inputStream().use { input ->
                val outputStream = if (uri.scheme == "file") File(uri.path!!).outputStream()
                    else resolver.openOutputStream(uri, "w") ?: throw IOException("无法写入下载位置")
                outputStream.use { output ->
                    // MediaStore creates its backing file on the first write
                    // open. Check seekability after that open, before copying.
                    readable(uri).close()
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        if (cancelled.get()) throw IOException("保存已暂停，临时文件已保留")
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                    }
                    output.flush()
                    if (output is java.io.FileOutputStream) output.fd.sync()
                }
            }
            readable(uri).close()
        }
        if (cancelled.get()) throw IOException("保存已暂停，临时文件已保留")
        if (destination == "downloads") {
            for (value in items(record).values) {
                val values = ContentValues().apply { put(MediaStore.MediaColumns.IS_PENDING, 0) }
                if (resolver.update(Uri.parse(value), values, null, null) != 1) throw IOException("公开下载文件失败")
            }
        }
        save(key, record.put("ready", true))
        val published = items(record)
        val merged = published.entries.singleOrNull()
        if (destination.startsWith("file:") && merged != null) {
            Uri.parse(merged.value).path?.let { scanMergedVideo(it, merged.key) }
        }
        return published
    }

    private fun downloadMimeType(name: String): String = when (name) {
        "audio.m4s" -> "audio/mp4"
        "media.mkv" -> "video/x-matroska"
        else -> "video/mp4"
    }

    private fun scanMergedVideo(path: String, name: String) {
        val format = when (name) {
            "media.mp4" -> "mp4"
            "media.mkv" -> "mkv"
            else -> return
        }
        // All result delivery runs on the main thread, including the deadline.
        var reported = false
        fun report(result: String) {
            if (reported || closed.get()) return
            reported = true
            channel.invokeMethod("mediaScanFinished", mapOf("format" to format, "result" to result))
        }
        val deadline = Runnable { report("timedOut") }
        main.postDelayed(deadline, 15_000)
        fun finish(result: String) {
            main.post {
                main.removeCallbacks(deadline)
                report(result)
            }
        }
        try {
            MediaScannerConnection.scanFile(
                activity.applicationContext,
                arrayOf(path),
                arrayOf(downloadMimeType(name)),
            ) { _, uri -> finish(if (uri != null) "scanned" else "noUri") }
        } catch (_: RuntimeException) {
            finish("requestFailed")
        }
    }

    private fun deleteRecord(key: String, record: JSONObject) {
        for ((name, value) in items(record)) {
            val uri = Uri.parse(value)
            try {
                checkBoundary(record, uri)
                if (record.getString("destination").startsWith("file:")) {
                    if (!File(uri.path!!).delete()) throw IOException("删除下载文件失败")
                } else if (record.getString("destination") == "downloads") {
                    if (resolver.delete(uri, null, null) != 1) throw IOException("删除下载文件失败")
                }
                else if (!DocumentsContract.deleteDocument(resolver, uri)) throw IOException("删除下载文件失败")
            } catch (_: java.io.FileNotFoundException) {
                // An unavailable volume is not evidence that the user deleted a
                // child. Retain the journal and task until the tree is readable.
                if (record.getString("destination").startsWith("file:")) {
                    externalDirectory(Uri.parse(record.getString("destination")).path!!)
                } else if (record.getString("destination") != "downloads") {
                    root(record.getString("destination"))
                } else if (Environment.getExternalStorageState() != Environment.MEDIA_MOUNTED) {
                    throw IOException("下载存储设备不可用，请连接后重试")
                }
            }
            record.getJSONObject("items").remove(name)
            save(key, record)
        }
        if (!prefs.edit().remove(key).commit()) throw IOException("保存删除结果失败")
    }

    private fun delete(call: MethodCall) {
        val key = key(call)
        val record = read(key) ?: return
        require(record.getString("destination") == call.argument<String>("destination"))
        deleteRecord(key, record)
    }

    private fun openMedia(value: String): Map<String, Any> {
        val record = prefs.all.entries.asSequence().filter { it.key.startsWith("task_") }
            .map { JSONObject(it.value as String) }.firstOrNull { it.optBoolean("ready") && items(it).containsValue(value) }
            ?: throw SecurityException()
        val uri = Uri.parse(value)
        checkBoundary(record, uri)
        val fd = readable(uri)
        val lease = UUID.randomUUID().toString()
        synchronized(leases) {
            if (closed.get()) { fd.close(); throw IOException("存储服务已关闭") }
            leases[lease] = fd
        }
        return mapOf("lease" to lease, "fd" to fd.fd)
    }

    fun close() {
        if (!closed.compareAndSet(false, true)) return
        channel.setMethodCallHandler(null)
        cancellations.values.forEach { it.set(true) }
        finishPicker(false)
        worker.execute {
            synchronized(leases) { leases.values.forEach { it.close() }; leases.clear() }
        }
        worker.shutdown()
    }
}
