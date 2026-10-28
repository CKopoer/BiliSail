import Flutter
import UIKit

/// Physical device posture keeps updating while Flutter locks the interface.
final class DeviceOrientationHandler: NSObject, FlutterStreamHandler {
  private let channel: FlutterEventChannel
  private var sink: FlutterEventSink?
  private var observers: [NSObjectProtocol] = []
  private var pending: DispatchWorkItem?
  private var delivered: String?
  private var generating = false

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterEventChannel(name: "bilisail/device_orientation", binaryMessenger: messenger)
    super.init()
    channel.setStreamHandler(self)
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    let center = NotificationCenter.default
    observers = [
      center.addObserver(forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
        self?.orientationChanged()
      },
      center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.start()
      },
      center.addObserver(forName: UIApplication.willResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
        self?.stop()
      },
    ]
    start()
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stop()
    observers.forEach { NotificationCenter.default.removeObserver($0) }
    observers.removeAll()
    sink = nil
    return nil
  }

  private func start() {
    guard !generating, sink != nil, UIApplication.shared.applicationState == .active else { return }
    delivered = nil
    generating = true
    UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    orientationChanged()
  }

  private func stop() {
    pending?.cancel()
    pending = nil
    if generating { UIDevice.current.endGeneratingDeviceOrientationNotifications() }
    generating = false
  }

  private func orientationChanged() {
    pending?.cancel()
    let value: String
    switch UIDevice.current.orientation {
    case .portrait, .portraitUpsideDown: value = "portrait"
    case .landscapeLeft, .landscapeRight: value = "landscape"
    default: return
    }
    guard generating, value != delivered else { return }
    let work = DispatchWorkItem { [weak self] in
      guard let self, self.generating, self.sink != nil else { return }
      self.delivered = value
      self.sink?(value)
    }
    pending = work
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
  }
}
