// Real Worker/VideoOutput/manager classes execute against controlled textures.
import Foundation
import Dispatch

let platformQueue = DispatchSpecificKey<UInt8>()
DispatchQueue.main.setSpecific(key: platformQueue, value: 1)

func autoreleasepool(_ body: () -> Void) { body() }
public final class CVPixelBuffer {}
public protocol FlutterTexture: AnyObject {
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>?
}
public protocol FlutterTextureRegistry: AnyObject {
  func register(_ texture: FlutterTexture) -> Int64
  func unregisterTexture(_ textureId: Int64)
  func textureFrameAvailable(_ textureId: Int64)
}
public protocol FlutterPlugin {}
public protocol FlutterPluginRegistrar {
  func messenger() -> Int
  func textures() -> FlutterTextureRegistry
  func addMethodCallDelegate(_ plugin: FlutterPlugin, channel: FlutterMethodChannel)
}
public typealias FlutterResult = (Any?) -> Void
public struct FlutterMethodCall { let method: String; let arguments: Any? }
public let FlutterMethodNotImplemented = "not-implemented"
public final class FlutterMethodChannel {
  var onInvoke: ((String, Any?) -> Void)?
  init(name: String, binaryMessenger: Int) {}
  func invokeMethod(_ method: String, arguments: Any?) { onInvoke?(method, arguments) }
}
struct MPVVideoOutParams { var dw: Int64 = 1920; var dh: Int64 = 1080; var rotate: Int64 = 0 }
final class Evidence {
  let lock = NSLock()
  var renders = 0
  var disposed = 0
  var alive = true
  var stall = false
  var stallInitialization = false
  var updates: (() -> Void)?
  let entered = DispatchSemaphore(value: 0)
  let resume = DispatchSemaphore(value: 0)
  func withLock<T>(_ body: (Evidence) -> T) -> T {
    lock.lock(); defer { lock.unlock() }; return body(self)
  }
}
let evidence = Evidence()
enum MPVHelpers {
  static func getVideoOutParams(_ handle: OpaquePointer) -> MPVVideoOutParams {
    evidence.withLock { precondition($0.alive, "Used the destroyed mpv handle") }
    return MPVVideoOutParams()
  }
}
class TextureHW: NSObject, FlutterTexture, ResizableTextureProtocol {
  private var disposed = false
  init(handle: OpaquePointer, updateCallback: @escaping () -> Void) {
    super.init()
    evidence.withLock { $0.updates = updateCallback }
    if evidence.withLock({ $0.stallInitialization }) {
      evidence.entered.signal()
      precondition(evidence.resume.wait(timeout: .now() + 8) == .success)
    }
  }
  deinit { dispose() }
  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? { nil }
  func resize(_ size: CGSize) {}
  func render(_ size: CGSize) {
    let wait = evidence.withLock { state -> Bool in
      precondition(state.alive && !disposed, "Render used a disposed context")
      state.renders += 1
      if state.stall { state.stall = false; return true }
      return false
    }
    if wait {
      evidence.entered.signal()
      precondition(evidence.resume.wait(timeout: .now() + 8) == .success, "Render was never released")
      evidence.withLock { precondition($0.alive, "mpv was freed during rendering") }
    }
  }
  func dispose() {
    if !disposed {
      disposed = true
      evidence.withLock { $0.disposed += 1 }
    }
  }
}
final class TextureSW: TextureHW {}
final class Registry: FlutterTextureRegistry {
  var textures: [Int64: FlutterTexture] = [:]
  var frames = 0
  var nextID: Int64 = 0
  func register(_ texture: FlutterTexture) -> Int64 {
    precondition(DispatchQueue.getSpecific(key: platformQueue) == 1)
    nextID += 1; textures[nextID] = texture; return nextID
  }
  func unregisterTexture(_ textureId: Int64) {
    precondition(DispatchQueue.getSpecific(key: platformQueue) == 1)
    textures[textureId] = nil
  }
  func textureFrameAvailable(_ textureId: Int64) {
    precondition(DispatchQueue.getSpecific(key: platformQueue) == 1 && textures[textureId] != nil)
    frames += 1
  }
}

// PRODUCTION_CLASSES

let scenario = CommandLine.arguments[1]
let registry = Registry()
let channel = FlutterMethodChannel(name: "test", binaryMessenger: 0)
let plugin = MediaKitVideoPlugin(registry: registry, channel: channel, utils: nil)
var retainedTexture: FlutterTexture?
var started = false
var completed = 0
var lateUpdate: (() -> Void)?
func signalFrame() {
  let callback = evidence.withLock { $0.updates }
  callback?()
}
func finish() {
  precondition(evidence.withLock { $0.disposed == 1 }, "Dispose replied before releasing the render context")
  precondition(registry.textures.isEmpty, "Dispose replied before unregistering the texture")
  evidence.withLock { $0.alive = false }
  let count = evidence.withLock { $0.renders }
  for _ in 0..<100 { lateUpdate?(); signalFrame() }
  DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    precondition(evidence.withLock { $0.renders == count }, "Late render ran after disposal")
    precondition(completed == (scenario == "repeat" ? 2 : 1))
    retainedTexture = nil
    print("Passed Apple output lifecycle: \(scenario)")
    exit(0)
  }
}
func closeOutput() {
  disposeOutput(completion: { completed += 1; finish() })
}
func disposeOutput(completion: @escaping () -> Void) {
  plugin.handle(FlutterMethodCall(method: "VideoOutputManager.Dispose", arguments: ["handle": "1"]),
                result: { _ in completion() })
}
func begin(_ textureId: Int64) {
  guard !started else { return }
  started = true
  retainedTexture = registry.textures[textureId]
  lateUpdate = evidence.withLock { $0.updates }
  if scenario == "retained" {
    closeOutput()
  } else if scenario == "repeat" {
    disposeOutput(completion: { completed += 1; if completed == 2 { finish() } })
    disposeOutput(completion: { completed += 1; if completed == 2 { finish() } })
  } else {
    evidence.withLock { $0.stall = true }
    signalFrame()
    DispatchQueue.global().async {
      precondition(evidence.entered.wait(timeout: .now() + 5) == .success, "No render began")
      DispatchQueue.main.async {
        if scenario == "coalesce" {
          for _ in 0..<10000 { signalFrame() }
          evidence.resume.signal()
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            let count = evidence.withLock { $0.renders }
            precondition(count == 2, "Unbounded render backlog: \(count) renders")
            precondition(registry.frames <= 3, "Unbounded platform notifications")
            closeOutput()
          }
        } else if scenario == "native-free" {
          disposeOutput(completion: {
            completed += 1
            evidence.withLock { $0.alive = false }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { finish() }
          })
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { evidence.resume.signal() }
        } else {
          disposeOutput(completion: { completed += 1; finish() })
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            precondition(completed == 0, "Disposal did not wait for the active GPU render")
            evidence.resume.signal()
          }
        }
      }
    }
  }
}
DispatchQueue.main.async {
  if scenario == "initialize" { evidence.withLock { $0.stallInitialization = true } }
  channel.onInvoke = { method, args in
    if method == "VideoOutput.Resize", let values = args as? [String: Any], let id = values["id"] as? Int64 {
      begin(id)
    }
  }
  plugin.handle(FlutterMethodCall(method: "VideoOutputManager.Create", arguments: [
    "handle": "1", "configuration": ["width": "null", "height": "null", "enableHardwareAcceleration": true]
  ]), result: { _ in })
  if scenario == "initialize" {
    DispatchQueue.global().async {
      precondition(evidence.entered.wait(timeout: .now() + 5) == .success)
      DispatchQueue.main.async {
        closeOutput()
        precondition(completed == 0)
        evidence.resume.signal()
      }
    }
  }
}
DispatchQueue.global().asyncAfter(deadline: .now() + 12) {
  fputs("Lifecycle test timed out\n", stderr)
  exit(2)
}
dispatchMain()
