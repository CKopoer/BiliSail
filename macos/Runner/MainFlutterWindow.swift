import Cocoa
import FlutterMacOS

// There must be no native FlutterViewController before Dart creates its first
// regular window: Flutter 3.47.6 enables multiview at that first FFI call.
final class MacOSApplication {
  private let engine: FlutterEngine
  private let applicationWindowChannel: FlutterMethodChannel
  private let exitChannel: FlutterMethodChannel
  private var systemFontsChannel: FlutterMethodChannel?
  private var imageExportChannel: FlutterMethodChannel?
  private var appIconChannel: FlutterMethodChannel?
  private var passportCookies: PassportWebCookies?
  private var desktopWindows: DesktopWindowController?
  private var mainGeometry: PersistentWindowGeometry?
  private var focusObservers: [NSObjectProtocol] = []
  private var focusRevision: Int64 = 0
  private let focusDiagnostics =
    ProcessInfo.processInfo.environment["BILISAIL_WINDOW_FOCUS_DIAGNOSTICS"] == "1" ||
    ProcessInfo.processInfo.arguments.contains("--bilisail-release-smoke")

  init() {
    ReleaseSmokeNativeStage.engineCreate.emit()
    engine = FlutterEngine(name: "BiliSail", project: nil, allowHeadlessExecution: true)
    applicationWindowChannel = FlutterMethodChannel(
      name: "bilisail/application_window", binaryMessenger: engine.binaryMessenger
    )
    exitChannel = FlutterMethodChannel(
      name: "flutter/platform", binaryMessenger: engine.binaryMessenger,
      codec: FlutterJSONMethodCodec.sharedInstance()
    )
    applicationWindowChannel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "engine_unavailable", message: "Flutter engine is unavailable.", details: nil))
        return
      }
      if call.method == "getWindowFocus" {
        result(self.windowFocusSnapshot())
        return
      }
      if call.method == "probeWindowSpace" {
        // Only the explicit packaging smoke can inject this fixed, harmless
        // event into its own key window. Never use a global event tap or post.
        guard ProcessInfo.processInfo.arguments.contains("--bilisail-release-smoke"),
              ProcessInfo.processInfo.arguments.contains("startup"),
              let args = call.arguments as? [String: Any],
              let viewID = (args["viewId"] as? NSNumber)?.int64Value else {
          result(FlutterMethodNotImplemented)
          return
        }
        DispatchQueue.main.async { [weak self] in
          guard let self = self, NSApp.isActive,
                let window = NSApp.keyWindow, window.isKeyWindow,
                let controller = window.contentViewController as? FlutterViewController,
                controller.engine === self.engine, controller.viewIdentifier == viewID else {
            result(FlutterError(code: "focus_probe", message: "Probe window is not key.", details: nil))
            return
          }
          for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let event = NSEvent.keyEvent(
              with: type, location: .zero, modifierFlags: [],
              timestamp: ProcessInfo.processInfo.systemUptime,
              windowNumber: window.windowNumber, context: nil,
              characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49
            ) else {
              result(FlutterError(code: "focus_probe", message: "Probe event is unavailable.", details: nil))
              return
            }
            window.sendEvent(event)
          }
          result(nil)
        }
        return
      }
      if call.method == "prepareWindowing" {
        result(self.engine.viewController == nil)
        return
      }
      guard call.method == "attachMainWindow" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let viewID = (args["viewId"] as? NSNumber)?.int64Value,
            let handle = (args["windowHandle"] as? NSNumber)?.uint64Value,
            let window = NSApp.windows.first(where: {
              UInt64(UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque())) == handle
            }),
            let controller = window.contentViewController as? FlutterViewController,
            controller.engine === self.engine, controller.viewIdentifier == viewID else {
        result(FlutterError(code: "window_unavailable", message: "Main Flutter window is unavailable.", details: nil))
        return
      }
      (NSApp.delegate as? FlutterAppDelegate)?.mainFlutterWindow = window
      self.mainGeometry?.detach()
      window.contentMinSize = NSSize(width: 420, height: 560)
      window.center()
      self.mainGeometry = PersistentWindowGeometry(window: window, role: "main")
      result(nil)
    }

    // Observe independently of FlutterWindowOwner: the pinned SDK installs that
    // delegate only after the regular window has already become key.
    for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                 NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
      focusObservers.append(NotificationCenter.default.addObserver(
        forName: name, object: nil, queue: .main
      ) { [weak self] _ in
        guard let self = self else { return }
        self.focusRevision += 1
        if self.focusDiagnostics { _ = self.windowFocusSnapshot() }
      })
    }

    // These plugins use the messenger/texture registry headlessly. Main-window
    // operations go through the per-view WindowService, never window_manager's
    // legacy registrar.view (which only looks up implicit view 0).
    ReleaseSmokeNativeStage.pluginsRegister.emit()
    RegisterGeneratedPlugins(registry: engine)
    ReleaseSmokeNativeStage.pluginsReady.emit()
    passportCookies = PassportWebCookies(messenger: engine.binaryMessenger) {
      NSApp.windows.compactMap { $0.contentView }
    }

    let channel = FlutterMethodChannel(
      name: "bilisail/system_fonts",
      binaryMessenger: engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "listFamilies" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(NSFontManager.shared.availableFontFamilies)
    }
    systemFontsChannel = channel
    let iconChannel = FlutterMethodChannel(name: "bilisail/app_icon", binaryMessenger: engine.binaryMessenger)
    iconChannel.setMethodCallHandler { call, result in
      guard call.method == "setIcon" else { result(FlutterMethodNotImplemented); return }
      guard let arguments = call.arguments as? [String: Any],
            let name = arguments["icon"] as? String,
            name == "bilisail" || name == "bilibili" else {
        result(FlutterError(code: "invalid_icon", message: "Invalid application icon.", details: nil))
        return
      }
      if name == "bilisail" {
        // AppKit restores the installed icon and its original Dock sizing.
        // Replacing it with a raw PNG changes Launch Services' presentation.
        NSApp.applicationIconImage = nil
        result(nil)
        return
      }
      guard let bytes = arguments["image"] as? FlutterStandardTypedData,
            let image = NSImage(data: bytes.data) else {
        result(FlutterError(code: "invalid_icon", message: "Invalid application icon.", details: nil))
        return
      }
      // The ICNS retains all pixel representations; points are independent of
      // the source bitmap resolution, including on Retina displays.
      image.size = NSSize(width: 512, height: 512)
      NSApp.applicationIconImage = image
      result(nil)
    }
    appIconChannel = iconChannel
    imageExportChannel = registerImageExport(
      messenger: engine.binaryMessenger
    )
    desktopWindows = DesktopWindowController(
      messenger: engine.binaryMessenger
    )
  }

  private func windowFocusSnapshot() -> [String: Any] {
    let window = NSApp.keyWindow
    let controller = window?.contentViewController as? FlutterViewController
    let ownsView = controller?.engine === engine
    let key = window?.isKeyWindow == true
    let active = NSApp.isActive
    let view: Any
    if ownsView && key && active, let controller = controller {
      view = NSNumber(value: controller.viewIdentifier)
    } else {
      view = NSNull()
    }
    let responder = (window?.firstResponder).map { String(describing: type(of: $0)) } ?? "none"
    let responderInView: Bool
    if let controller = controller, let first = window?.firstResponder {
      responderInView = first === controller ||
        (first as? NSView)?.isDescendant(of: controller.view) == true
    } else {
      responderInView = false
    }
    let result: [String: Any] = [
      "revision": focusRevision, "viewId": view, "active": active,
      "isKeyWindow": key, "responder": responder,
      "responderInView": responderInView, "diagnostics": focusDiagnostics,
    ]
    if focusDiagnostics {
      // No window titles, key identities, text, URLs or account data.
      NSLog("BILISAIL_FOCUS_NATIVE revision=%lld active=%d key=%d view=%@ responder=%@ inView=%d",
            focusRevision, active ? 1 : 0, key ? 1 : 0, String(describing: view), responder,
            responderInView ? 1 : 0)
    }
    return result
  }

  deinit {
    mainGeometry?.detach()
    for observer in focusObservers { NotificationCenter.default.removeObserver(observer) }
  }

  func start() -> Bool { engine.run(withEntrypoint: nil) }

  func requestExit(_ completion: @escaping (Bool) -> Void) {
    exitChannel.invokeMethod("System.requestAppExit", arguments: nil) { result in
      let response = result as? [String: Any]
      completion(response?["response"] as? String == "exit")
    }
  }

  func shutDown() { engine.shutDownEngine() }
}

private func registerImageExport(messenger: FlutterBinaryMessenger) -> FlutterMethodChannel {
  let channel = FlutterMethodChannel(name: "bilisail/image_export", binaryMessenger: messenger)
  channel.setMethodCallHandler { call, result in
    guard call.method == "save" || call.method == "copy" else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard let args = call.arguments as? [String: Any],
          let typed = args["bytes"] as? FlutterStandardTypedData,
          let ext = args["extension"] as? String,
          ["png", "jpg", "gif", "webp", "bmp", "avif"].contains(ext),
          !typed.data.isEmpty, typed.data.count <= 32 * 1024 * 1024 else {
      result(FlutterError(code: "invalid_image", message: "Invalid image data", details: nil))
      return
    }
    let data = typed.data
    if call.method == "copy" {
      guard let image = NSImage(data: data) else {
        result(FlutterError(code: "copy_failed", message: "Could not read image", details: nil))
        return
      }
      let pasteboard = NSPasteboard.general
      pasteboard.clearContents()
      if pasteboard.writeObjects([image]) { result(nil) }
      else { result(FlutterError(code: "copy_failed", message: "Could not copy image", details: nil)) }
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        let manager = FileManager.default
        let pictures = try manager.url(for: .picturesDirectory, in: .userDomainMask,
                                       appropriateFor: nil, create: true)
        let directory = pictures.appendingPathComponent("BiliSail", isDirectory: true)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("BiliSail-\(UUID().uuidString).\(ext)")
        let temporary = directory.appendingPathComponent(".\(UUID().uuidString).tmp")
        defer { try? manager.removeItem(at: temporary) }
        try data.write(to: temporary, options: .withoutOverwriting)
        try manager.moveItem(at: temporary, to: file)
        DispatchQueue.main.async { result(file.path) }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "save_failed", message: "Could not save image", details: nil))
        }
      }
    }
  }
  return channel
}

// The SDK's public registrar currently exposes only its implicit view. Resolve
// the pinned windowing API's handle against this process's real NSWindows;
// never dereference a window pointer received over the channel.
private final class DesktopWindowController {
  private let channel: FlutterMethodChannel
  private var captions: [Int64: PlaybackTitlebarBack] = [:]
  private var geometryOwner: (view: Int64, owner: Int64)?
  private var geometryTracker: PersistentWindowGeometry?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: "bilisail/desktop_window", binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self,
            let args = call.arguments as? [String: Any],
            let viewID = (args["viewId"] as? NSNumber)?.int64Value else {
        result(FlutterError(code: "invalid_argument", message: "Expected a view ID.", details: nil))
        return
      }
      let geometryCall = ["restoreGeometry", "captureGeometry", "retireGeometry"].contains(call.method)
      let owner = (args["owner"] as? NSNumber)?.int64Value ?? -1
      if geometryCall && owner <= 0 {
        result(FlutterError(code: "invalid_argument", message: "Expected a geometry owner.", details: nil))
        return
      }
      let ownsGeometry = self.geometryOwner?.view == viewID && self.geometryOwner?.owner == owner
      if call.method == "retireGeometry" {
        if ownsGeometry {
          self.geometryTracker?.detach()
          self.geometryTracker = nil
          self.geometryOwner = nil
        }
        result(nil)
        return
      }
      if call.method == "captureGeometry" && !ownsGeometry {
        result(nil)
        return
      }
      if call.method == "removeBackButton" {
        self.captions.removeValue(forKey: viewID)?.detach()
        result(nil)
        return
      }
      guard let handle = (args["windowHandle"] as? NSNumber)?.uint64Value,
            let window = NSApp.windows.first(where: {
              UInt64(UInt(bitPattern: Unmanaged.passUnretained($0).toOpaque())) == handle
            }) else {
        result(FlutterError(code: "window_unavailable", message: "Flutter window is unavailable.", details: nil))
        return
      }
      switch call.method {
      case "restoreGeometry":
        self.geometryTracker?.detach()
        self.geometryOwner = (viewID, owner)
        self.geometryTracker = PersistentWindowGeometry(window: window, role: "playback")
        result(nil)
      case "captureGeometry":
        self.geometryTracker?.capture()
        result(nil)
      case "activate":
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        result(nil)
      case "setBackButton":
        guard let enabled = args["enabled"] as? Bool else {
          result(FlutterError(code: "invalid_argument", message: "Expected a Back enabled state.", details: nil))
          return
        }
        if self.captions[viewID] == nil {
          let caption = PlaybackTitlebarBack(
            window: window,
            onBack: { [weak self] in
              self?.channel.invokeMethod("back", arguments: ["viewId": viewID])
            },
            onHome: { [weak self] in
              self?.channel.invokeMethod("home", arguments: ["viewId": viewID])
            })
          self.captions[viewID] = caption
          window.addTitlebarAccessoryViewController(caption)
        }
        self.captions[viewID]?.configure(enabled: enabled, showHome: args["showHome"] as? Bool ?? false)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  deinit {
    channel.setMethodCallHandler(nil)
    for caption in captions.values { caption.detach() }
    geometryTracker?.detach()
  }
}

// Native presentation preferences are shared across accounts, with one record
// per role. Smoke builds use no persistent state or production window geometry.
private final class PersistentWindowGeometry {
  private var tracker: PlaybackGeometryTracker?
  private var normalFrame: NSRect?
  private var maximized = false
  private let key: String
  private let defaults: UserDefaults?

  init(window: NSWindow, role: String) {
    key = "bilisail.windowGeometry.v1.\(role)"
    defaults = ProcessInfo.processInfo.arguments.contains("--bilisail-release-smoke")
      ? nil : UserDefaults.standard
    if let saved = defaults?.dictionary(forKey: key),
       let version = saved["version"] as? Int, version == 1,
       let values = saved["normal"] as? [Double], values.count == 4,
       let zoomed = saved["maximized"] as? Bool {
      let frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
      if let fitted = PlaybackGeometryTracker.fitToVisibleScreen(frame) {
        normalFrame = fitted
        maximized = zoomed
        window.setFrame(fitted, display: false)
      }
    }
    // Seed the ordinary rectangle before zooming; never replace it with the
    // visible zoomed frame. Observers are installed after restore completes.
    if normalFrame == nil { normalFrame = window.frame }
    if maximized && !window.isZoomed { window.zoom(nil) }
    tracker = PlaybackGeometryTracker(window: window) { [weak self] frame, zoomed in
      guard let self = self else { return }
      if let frame = frame { self.normalFrame = frame }
      self.maximized = zoomed
      self.save()
    }
  }

  private func save() {
    guard let frame = normalFrame, PlaybackGeometryTracker.valid(frame) else { return }
    let record: [String: Any] = [
      "version": 1, "normal": [Double(frame.minX), Double(frame.minY),
                                 Double(frame.width), Double(frame.height)],
      "maximized": maximized,
    ]
    if let previous = defaults?.dictionary(forKey: key),
       NSDictionary(dictionary: previous).isEqual(to: record) { return }
    defaults?.set(record, forKey: key)
  }

  func capture() { tracker?.capture() }
  func detach() {
    tracker?.capture()
    tracker?.detach()
    tracker = nil
  }
  deinit { detach() }
}

// Frame coordinates stay in Cocoa desktop points. Preserve normal bounds while
// zoomed, miniaturized, or transitioning to/from native fullscreen.
private final class PlaybackGeometryTracker {
  private weak var window: NSWindow?
  private let onCapture: (NSRect?, Bool) -> Void
  private var observers: [NSObjectProtocol] = []
  private var fullscreenTransition = false

  init(window: NSWindow, onCapture: @escaping (NSRect?, Bool) -> Void) {
    self.window = window
    self.onCapture = onCapture
    let center = NotificationCenter.default
    for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification,
                 NSWindow.willMiniaturizeNotification] {
      observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
        self?.capture()
      })
    }
    observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification,
                                       object: window, queue: .main) { [weak self] _ in
      self?.capture()
      self?.fullscreenTransition = true
    })
    observers.append(center.addObserver(forName: NSWindow.willExitFullScreenNotification,
                                       object: window, queue: .main) { [weak self] _ in
      self?.fullscreenTransition = true
    })
    observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                       object: window, queue: .main) { [weak self] _ in
      self?.fullscreenTransition = false
      self?.capture()
    })
    observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
                                       object: window, queue: .main) { [weak self] _ in
      self?.capture()
      self?.detach()
    })
    capture()
  }

  func capture() {
    guard let window = window, !fullscreenTransition,
          !window.isMiniaturized,
          !window.styleMask.contains(.fullScreen), Self.valid(window.frame) else { return }
    onCapture(window.isZoomed ? nil : window.frame, window.isZoomed)
  }

  static func valid(_ frame: NSRect) -> Bool {
    frame.origin.x.isFinite && frame.origin.y.isFinite &&
      frame.width.isFinite && frame.height.isFinite &&
      abs(frame.origin.x) <= 1_000_000 && abs(frame.origin.y) <= 1_000_000 &&
      frame.width >= 100 && frame.height >= 100 &&
      frame.width <= 100_000 && frame.height <= 100_000
  }

  static func fitToVisibleScreen(_ saved: NSRect) -> NSRect? {
    guard valid(saved), !NSScreen.screens.isEmpty else { return nil }
    // Prefer overlap; after a display is removed choose the nearest work area.
    let screen = NSScreen.screens.min { first, second in
      func score(_ screen: NSScreen) -> CGFloat {
        let area = saved.intersection(screen.visibleFrame)
        if !area.isNull && !area.isEmpty { return -(area.width * area.height) }
        return hypot(saved.midX - screen.visibleFrame.midX, saved.midY - screen.visibleFrame.midY)
      }
      return score(first) < score(second)
    }
    guard let work = screen?.visibleFrame, valid(work) else { return nil }
    let width = min(saved.width, work.width)
    let height = min(saved.height, work.height)
    return NSRect(x: max(work.minX, min(saved.minX, work.maxX - width)),
                  y: max(work.minY, min(saved.minY, work.maxY - height)),
                  width: width, height: height)
  }

  func detach() {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    window = nil
  }

  deinit { detach() }
}

final class PlaybackTitlebarBack: NSTitlebarAccessoryViewController {
  let backButton = NSButton(title: "‹", target: nil, action: nil)
  private let homeButton = NSButton(title: "⌂", target: nil, action: nil)
  private weak var playbackWindow: NSWindow?
  private let onBack: () -> Void
  private let onHome: () -> Void
  private var observers: [NSObjectProtocol] = []

  init(window: NSWindow, onBack: @escaping () -> Void, onHome: @escaping () -> Void) {
    self.playbackWindow = window
    self.onBack = onBack
    self.onHome = onHome
    super.init(nibName: nil, bundle: nil)
    layoutAttribute = .left
    view = NSView(frame: NSRect(x: 0, y: 0, width: 36, height: 28))
    backButton.frame = NSRect(x: 3, y: 3, width: 30, height: 22)
    backButton.bezelStyle = .texturedRounded
    backButton.font = .systemFont(ofSize: 20)
    backButton.setAccessibilityLabel("返回上一视频或浏览窗口")
    backButton.toolTip = "返回上一视频或浏览窗口"
    backButton.target = self
    backButton.action = #selector(back)
    view.addSubview(backButton)
    homeButton.frame = NSRect(x: 37, y: 3, width: 30, height: 22)
    homeButton.bezelStyle = .texturedRounded
    homeButton.image = NSImage(systemSymbolName: "house", accessibilityDescription: "回到主页")
    homeButton.imagePosition = .imageOnly
    homeButton.setAccessibilityLabel("回到主页")
    homeButton.toolTip = "回到主页"
    homeButton.target = self
    homeButton.action = #selector(home)
    homeButton.isHidden = true
    view.addSubview(homeButton)
    let center = NotificationCenter.default
    observers.append(center.addObserver(forName: NSWindow.willEnterFullScreenNotification,
                                       object: window, queue: .main) { [weak self] _ in
      self?.view.isHidden = true
    })
    observers.append(center.addObserver(forName: NSWindow.didExitFullScreenNotification,
                                       object: window, queue: .main) { [weak self] _ in
      self?.view.isHidden = false
    })
  }

  required init?(coder: NSCoder) { return nil }

  func configure(enabled: Bool, showHome: Bool) {
    backButton.isEnabled = enabled
    homeButton.isEnabled = enabled
    homeButton.isHidden = !showHome
    view.setFrameSize(NSSize(width: showHome ? 72 : 36, height: 28))
  }

  @objc private func back() {
    // A double click is one navigation action, matching the Windows caption.
    if let event = NSApp.currentEvent,
       event.type == .leftMouseDown || event.type == .leftMouseUp,
       event.clickCount > 1 { return }
    onBack()
  }

  @objc private func home() {
    if let event = NSApp.currentEvent,
       event.type == .leftMouseDown || event.type == .leftMouseUp,
       event.clickCount > 1 { return }
    onHome()
  }

  func detach() {
    guard let window = playbackWindow else { return }
    if let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === self }) {
      window.removeTitlebarAccessoryViewController(at: index)
    }
    playbackWindow = nil
  }

  deinit {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
  }
}
