import Flutter
import Photos
import UIKit

final class DownloadPhotosHandler {
  private let channel: FlutterMethodChannel

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: "dev.bilisail/download_photos", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterMethodNotImplemented)
        return
      }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "requestAccess":
      if UIApplication.shared.applicationState == .active &&
          PHPhotoLibrary.authorizationStatus(for: .addOnly) == .notDetermined {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { _ in
          DispatchQueue.main.async { result(nil) }
        }
      } else {
        result(nil)
      }
    case "saveVideo":
      saveVideo(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func saveVideo(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard canAddToPhotos else {
      result(FlutterError(code: "permission", message: nil, details: nil))
      return
    }
    guard let args = call.arguments as? [String: String],
          let scope = args["scopeDirectory"], isHex(scope, length: 16),
          let task = args["taskId"], isHex(task, length: 32),
          let name = args["fileName"], name == "media.mp4" || name == "media.mkv",
          let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    else {
      result(FlutterError(code: "missing", message: nil, details: nil))
      return
    }

    // Dart verifies the completed task and its owner. Rebuild the path from
    // the system's Documents directory and reject links below that anchor.
    let video = documents.resolvingSymlinksInPath()
      .appendingPathComponent("BiliSail", isDirectory: true)
      .appendingPathComponent("offline", isDirectory: true)
      .appendingPathComponent(scope, isDirectory: true)
      .appendingPathComponent(task, isDirectory: true)
      .appendingPathComponent(name, isDirectory: false)
    guard isReadableVideo(video) else {
      result(FlutterError(code: "missing", message: nil, details: nil))
      return
    }
    guard UIVideoAtPathIsCompatibleWithSavedPhotosAlbum(video.path) else {
      result(FlutterError(code: "unsupported", message: nil, details: nil))
      return
    }
    PHPhotoLibrary.shared().performChanges({
      let options = PHAssetResourceCreationOptions()
      options.shouldMoveFile = false
      PHAssetCreationRequest.forAsset().addResource(with: .video, fileURL: video, options: options)
    }) { success, _ in
      DispatchQueue.main.async {
        if success {
          result(nil)
        } else {
          let code = self.canAddToPhotos ? "importFailed" : "permission"
          result(FlutterError(code: code, message: nil, details: nil))
        }
      }
    }
  }

  private var canAddToPhotos: Bool {
    let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
    return status == .authorized || status == .limited
  }

  private func isHex(_ value: String, length: Int) -> Bool {
    value.utf8.count == length && value.utf8.allSatisfy {
      (UInt8(48)...UInt8(57)).contains($0) || (UInt8(97)...UInt8(102)).contains($0)
    }
  }

  private func isReadableVideo(_ video: URL) -> Bool {
    video.resolvingSymlinksInPath().path == video.path &&
      (try? video.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true &&
      FileManager.default.isReadableFile(atPath: video.path)
  }
}
