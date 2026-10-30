import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceOrientation: DeviceOrientationHandler?
  private var passportCookies: PassportWebCookies?
  private var appIconChannel: FlutterMethodChannel?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "bilisail/app_icon", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      let application = UIApplication.shared
      if call.method == "getIcon" {
        result(application.alternateIconName == "BilibiliIcon" ? "bilibili" : "bilisail")
      } else if call.method == "setIcon" {
        guard let arguments = call.arguments as? [String: Any],
              let icon = arguments["icon"] as? String,
              icon == "bilisail" || icon == "bilibili" else {
          result(FlutterError(code: "invalid_icon", message: "Unknown application icon.", details: nil))
          return
        }
        let name: String? = icon == "bilibili" ? "BilibiliIcon" : nil
        if application.alternateIconName == name { result(nil); return }
        guard application.supportsAlternateIcons else {
          result(FlutterError(code: "unsupported", message: "Alternate icons are unavailable.", details: nil))
          return
        }
        application.setAlternateIconName(name) { error in
          DispatchQueue.main.async {
            if error != nil {
              result(FlutterError(code: "icon_change_failed", message: "Cannot change the application icon.", details: nil))
            } else { result(nil) }
          }
        }
      } else { result(FlutterMethodNotImplemented) }
    }
    appIconChannel = channel
    deviceOrientation = DeviceOrientationHandler(messenger: engineBridge.applicationRegistrar.messenger())
    passportCookies = PassportWebCookies(messenger: engineBridge.applicationRegistrar.messenger()) {
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    }
  }
}
