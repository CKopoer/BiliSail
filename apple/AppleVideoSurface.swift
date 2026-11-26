import Metal
import QuartzCore
#if os(macOS)
import AppKit
import FlutterMacOS
#else
import Flutter
import UIKit
#endif

// The player owns the Metal swapchain. Flutter only moves its layer between
// platform views when the presentation changes.
final class AppleVideoSurface: NSObject, FlutterPlatformViewFactory {
  private var layers: [Int64: PlaybackMetalLayer] = [:]
  private let displayTransfer: (Int64) -> String?

  #if os(macOS)
  static func register(engine: FlutterEngine) {
    let registrar = engine.registrar(forPlugin: "BiliSailAppleVideo")
    let factory = AppleVideoSurface { [weak engine] viewID in
      for window in NSApp.windows {
        guard let controller = window.contentViewController as? FlutterViewController,
              controller.engine === engine, controller.viewIdentifier == viewID,
              let screen = window.screen else { continue }
        return screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 ? "pq" : "srgb"
      }
      return nil
    }
    registrar.register(factory, withId: "bilisail/hdr_video")
    factory.listen(on: engine.binaryMessenger)
  }
  #else
  static func register(registrar: FlutterPluginRegistrar) {
    let factory = AppleVideoSurface { [weak registrar] _ in
      guard let screen = registrar?.viewController?.viewIfLoaded?.window?.windowScene?.screen else { return nil }
      if #available(iOS 16.0, *), screen.potentialEDRHeadroom > 1 { return "pq" }
      return "srgb"
    }
    registrar.register(factory, withId: "bilisail/hdr_video")
    factory.listen(on: registrar.messenger())
  }
  #endif

  private init(displayTransfer: @escaping (Int64) -> String?) {
    self.displayTransfer = displayTransfer
  }

  private func listen(on messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "bilisail/hdr_video", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(nil); return }
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "supported":
        guard let view = args?["view"] as? NSNumber else { result(nil); return }
        result(self.displayTransfer(view.int64Value))
      case "create":
        guard let width = args?["width"] as? Int, let height = args?["height"] as? Int,
              (2...16384).contains(width), (2...16384).contains(height),
              let view = args?["view"] as? NSNumber,
              let transfer = self.displayTransfer(view.int64Value),
              transfer == args?["transfer"] as? String,
              let device = MTLCreateSystemDefaultDevice() else { result(nil); return }
        let layer = PlaybackMetalLayer()
        layer.device = device
        // Start with SDR. Only a successful Vulkan colorspace negotiation can
        // change this to a tagged high precision HDR swapchain.
        layer.pixelFormat = .bgra8Unorm
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.frame = CGRect(x: 0, y: 0, width: width, height: height)
        layer.drawableSize = layer.bounds.size
        if #available(iOS 16.0, macOS 10.11, *) {
          layer.wantsExtendedDynamicRangeContent = transfer == "pq"
        }
        let id = Int64(Int(bitPattern: Unmanaged.passUnretained(layer).toOpaque()))
        self.layers[id] = layer
        result(id)
      case "matches":
        guard let id = args?["id"] as? NSNumber, let layer = self.layers[id.int64Value],
              let transfer = args?["transfer"] as? String, layer.didPresent else { result(false); return }
        let name = layer.colorspace?.name
        if transfer == "pq", #available(iOS 16.0, macOS 10.15, *) {
          let deep = [.rgb10a2Unorm, .bgr10a2Unorm, .rgba16Float].contains(layer.pixelFormat)
          result(deep && layer.wantsExtendedDynamicRangeContent &&
                 (name == CGColorSpace.itur_2100_PQ || name == CGColorSpace.itur_2020_PQ))
        } else {
          result(transfer == "srgb" && name == CGColorSpace.sRGB)
        }
      case "release":
        if let id = call.arguments as? NSNumber {
          self.layers.removeValue(forKey: id.int64Value)?.removeFromSuperlayer()
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  #if os(macOS)
  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? { FlutterStandardMessageCodec.sharedInstance() }
  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    MetalHost(target: (args as? NSNumber).flatMap { layers[$0.int64Value] })
  }
  #else
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    MetalHost(target: (args as? NSNumber).flatMap { layers[$0.int64Value] })
  }
  #endif
}

private final class PlaybackMetalLayer: CAMetalLayer {
  private let lock = NSLock()
  private var presented = false
  var didPresent: Bool {
    lock.lock()
    defer { lock.unlock() }
    return presented
  }

  override var drawableSize: CGSize {
    get { super.drawableSize }
    set {
      // MoltenVK briefly requests a 1x1 surface while replacing a swapchain.
      // Reusing that extent for the paused frame loses its real dimensions.
      if newValue.width > 1 && newValue.height > 1 { super.drawableSize = newValue }
    }
  }

  override func nextDrawable() -> CAMetalDrawable? {
    let drawable = super.nextDrawable()
    if !didPresent {
      drawable?.addPresentedHandler { [weak self] frame in
        guard let self = self, frame.presentedTime > 0 else { return }
        self.lock.lock()
        self.presented = true
        self.lock.unlock()
      }
    }
    return drawable
  }
}

#if os(macOS)
private final class MetalHost: NSView {
  private let target: CAMetalLayer?
  init(target: CAMetalLayer?) {
    self.target = target
    super.init(frame: .zero)
    wantsLayer = true
    if let target = target { layer?.addSublayer(target) }
  }
  required init?(coder: NSCoder) { return nil }
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func layout() {
    super.layout()
    if let target = target, target.superlayer === layer { fit(target, bounds) }
  }
}
#else
private final class MetalHost: UIView, FlutterPlatformView {
  private let target: CAMetalLayer?
  init(target: CAMetalLayer?) {
    self.target = target
    super.init(frame: .zero)
    isUserInteractionEnabled = false
    if let target = target { layer.addSublayer(target) }
  }
  required init?(coder: NSCoder) { return nil }
  func view() -> UIView { self }
  override func layoutSubviews() {
    super.layoutSubviews()
    if let target = target, target.superlayer === layer { fit(target, bounds) }
  }
}
#endif

private func fit(_ target: CAMetalLayer, _ bounds: CGRect) {
  guard !bounds.isEmpty else { return }
  // Keep the source-sized Vulkan swapchain while Core Animation scales the
  // already color-managed image to the layout bounds.
  let size = target.drawableSize
  CATransaction.begin()
  CATransaction.setDisableActions(true)
  target.frame = bounds
  target.drawableSize = size
  CATransaction.commit()
}
