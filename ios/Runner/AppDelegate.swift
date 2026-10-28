import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceOrientation: DeviceOrientationHandler?
  private var passportCookies: PassportWebCookies?
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    deviceOrientation = DeviceOrientationHandler(messenger: engineBridge.applicationRegistrar.messenger())
    passportCookies = PassportWebCookies(messenger: engineBridge.applicationRegistrar.messenger()) {
      UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap { $0.windows }
    }
  }
}
