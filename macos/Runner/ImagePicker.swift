import Cocoa
import CoreFoundation
import FlutterMacOS
import UniformTypeIdentifiers

protocol ImageSelectionPanel: AnyObject {
  var urls: [URL] { get }
  func begin(for window: NSWindow, completion: @escaping (NSApplication.ModalResponse) -> Void)
  func cancel()
}

private final class SystemImageSelectionPanel: ImageSelectionPanel {
  private let panel = NSOpenPanel()

  init() {
    panel.title = "选择图片"
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.canCreateDirectories = false
    panel.allowsMultipleSelection = true
    panel.allowedContentTypes = [.jpeg, .png, .gif]
  }

  var urls: [URL] { panel.urls }

  func begin(for window: NSWindow, completion: @escaping (NSApplication.ModalResponse) -> Void) {
    // AppKit stays on the main thread, but the Flutter channel does not enter
    // an application-modal run loop. The explicit caller owns this sheet.
    panel.beginSheetModal(for: window, completionHandler: completion)
  }

  func cancel() {
    if let parent = panel.sheetParent {
      parent.endSheet(panel, returnCode: .cancel)
    } else {
      panel.cancel(nil)
    }
    panel.orderOut(nil)
  }
}

enum ImageSelectionResult: Equatable {
  case selected([String])
  case cancelled
  case unavailable
  case busy
  case failed
}

// All request state belongs to the AppKit thread. The platform channel is a
// thin adapter so window retirement and late sheet callbacks can be unit tested.
final class ImageSelectionCoordinator {
  private final class Request {
    let viewID: Int64
    weak var owner: NSWindow?
    let panel: ImageSelectionPanel
    var completion: ((ImageSelectionResult) -> Void)?
    var closeObserver: NSObjectProtocol?

    init(viewID: Int64, owner: NSWindow, panel: ImageSelectionPanel,
         completion: @escaping (ImageSelectionResult) -> Void) {
      self.viewID = viewID
      self.owner = owner
      self.panel = panel
      self.completion = completion
    }
  }

  private let resolveWindow: (Int64) -> NSWindow?
  private let makePanel: () -> ImageSelectionPanel
  private let notifications: NotificationCenter
  private let schedule: (@escaping () -> Void) -> Void
  private var pending: Request?
  private var stopped = false

  init(resolveWindow: @escaping (Int64) -> NSWindow?,
       makePanel: @escaping () -> ImageSelectionPanel = { SystemImageSelectionPanel() },
       notifications: NotificationCenter = .default,
       schedule: @escaping (@escaping () -> Void) -> Void = { action in
         DispatchQueue.main.async(execute: action)
       }) {
    self.resolveWindow = resolveWindow
    self.makePanel = makePanel
    self.notifications = notifications
    self.schedule = schedule
  }

  func pick(viewID: Int64, completion: @escaping (ImageSelectionResult) -> Void) {
    guard !stopped else { completion(.unavailable); return }
    guard pending == nil else { completion(.busy); return }
    guard let window = resolveWindow(viewID) else { completion(.unavailable); return }
    guard window.attachedSheet == nil else { completion(.busy); return }
    let request = Request(viewID: viewID, owner: window, panel: makePanel(), completion: completion)
    pending = request
    request.closeObserver = notifications.addObserver(
      forName: NSWindow.willCloseNotification, object: window, queue: .main
    ) { [weak self, weak request] _ in
      guard let self = self, let request = request else { return }
      self.finish(request, with: .unavailable, cancel: true)
    }
    request.panel.begin(for: window) { [weak self, weak request] response in
      // Leave the native sheet completion stack before sending a Flutter reply.
      self?.schedule { [weak self, weak request] in
        guard let self = self, let request = request, self.pending === request else { return }
        guard let owner = request.owner, self.resolveWindow(request.viewID) === owner else {
          self.finish(request, with: .unavailable)
          return
        }
        if response == .cancel {
          self.finish(request, with: .cancelled)
        } else if response == .OK {
          let urls = request.panel.urls
          guard !urls.isEmpty, urls.count <= 18,
                urls.allSatisfy({ $0.isFileURL && !$0.path.isEmpty }) else {
            self.finish(request, with: .failed)
            return
          }
          self.finish(request, with: .selected(urls.map { $0.path }))
        } else {
          self.finish(request, with: .failed)
        }
      }
    }
  }

  private func finish(_ request: Request, with result: ImageSelectionResult, cancel: Bool = false) {
    guard pending === request else { return }
    pending = nil
    if let observer = request.closeObserver { notifications.removeObserver(observer) }
    request.closeObserver = nil
    let completion = request.completion
    request.completion = nil
    // Cancelling can synchronously invoke the panel callback. Retire the request
    // first so it cannot deliver a second result or affect a newer request.
    if cancel { request.panel.cancel() }
    completion?(result)
  }

  func shutDown() {
    stopped = true
    if let request = pending { finish(request, with: .unavailable, cancel: true) }
  }

  deinit { shutDown() }
}

final class ImagePickerChannel {
  private let channel: FlutterMethodChannel
  private let coordinator: ImageSelectionCoordinator

  init(messenger: FlutterBinaryMessenger, resolveWindow: @escaping (Int64) -> NSWindow?) {
    coordinator = ImageSelectionCoordinator(resolveWindow: resolveWindow)
    channel = FlutterMethodChannel(name: "bilisail/image_picker", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "pickImages" else { result(FlutterMethodNotImplemented); return }
      guard let self = self else {
        result(FlutterError(code: "window_unavailable", message: "The app is closing.", details: nil))
        return
      }
      guard let args = call.arguments as? [String: Any],
            let number = args["viewId"] as? NSNumber,
            CFGetTypeID(number) != CFBooleanGetTypeID(),
            let viewID = Int64(number.stringValue), viewID >= 0 else {
        result(FlutterError(code: "invalid_argument", message: "Expected an image picker view ID.", details: nil))
        return
      }
      self.coordinator.pick(viewID: viewID) { selection in
        switch selection {
        case .selected(let paths): result(paths)
        case .cancelled: result([String]())
        case .unavailable:
          result(FlutterError(code: "window_unavailable", message: "The image picker view is closed.", details: nil))
        case .busy:
          result(FlutterError(code: "picker_busy", message: "An image picker is already open.", details: nil))
        case .failed:
          result(FlutterError(code: "picker_failed", message: "Could not select images.", details: nil))
        }
      }
    }
  }

  func shutDown() {
    channel.setMethodCallHandler(nil)
    coordinator.shutDown()
  }

  deinit { shutDown() }
}
