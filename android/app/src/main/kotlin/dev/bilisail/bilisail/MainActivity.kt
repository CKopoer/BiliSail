package dev.bilisail.bilisail

import android.content.Intent
import android.content.res.Configuration
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var downloadStorage: DownloadStorageHandler? = null
    private var imageExport: ImageExportHandler? = null
    private var windowBrightness: WindowBrightnessHandler? = null
    private var mobileWindow: MobileWindowHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        downloadStorage = DownloadStorageHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        imageExport = ImageExportHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        windowBrightness = WindowBrightnessHandler(this, flutterEngine.dartExecutor.binaryMessenger)
        mobileWindow = MobileWindowHandler(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onResume() {
        super.onResume()
        mobileWindow?.setResumed(true)
    }

    override fun onPause() {
        mobileWindow?.setResumed(false)
        super.onPause()
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        mobileWindow?.reapplyFullScreen()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) mobileWindow?.reapplyFullScreen()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        downloadStorage?.onActivityResult(requestCode)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        imageExport?.onPermissionResult(requestCode, grantResults)
        downloadStorage?.onPermissionResult(requestCode)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        mobileWindow?.close()
        mobileWindow = null
        windowBrightness?.close()
        windowBrightness = null
        downloadStorage?.close()
        downloadStorage = null
        imageExport?.close()
        imageExport = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
