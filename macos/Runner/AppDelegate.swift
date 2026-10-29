import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var application: MacOSApplication?
  private var applicationStarted = false
  private let termination = ApplicationTerminationCoordinator()

  override func applicationDidFinishLaunching(_ notification: Notification) {
    ReleaseSmokeNativeStage.application.emit()
    let application = MacOSApplication()
    self.application = application
    ReleaseSmokeNativeStage.engineRun.emit()
    applicationStarted = application.start()
    ReleaseSmokeNativeStage.engineRunning.emit()
    if !applicationStarted { NSApp.terminate(nil) }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    application?.shutDown()
  }

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    guard applicationStarted, let application = application else { return .terminateNow }
    return termination.requestExit(using: application.requestExit) {
      sender.terminate(nil)
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    // Hot restart temporarily closes every SDK-managed window. Normal main
    // window Close requests application exit through Flutter's lifecycle,
    // allowing playback/download/native resources to finish releasing first.
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}

// Fixed markers only; never emit process arguments, paths or plugin data.
enum ReleaseSmokeNativeStage: String {
  case application
  case engineCreate = "engine-create"
  case pluginsRegister = "plugins-register"
  case pluginsReady = "plugins-ready"
  case engineRun = "engine-run"
  case engineRunning = "engine-running"

  func emit() {
    guard ProcessInfo.processInfo.arguments.contains("--bilisail-release-smoke") else { return }
    FileHandle.standardError.write(Data("BILISAIL_NATIVE_STAGE:\(rawValue)\n".utf8))
  }
}

// The pinned engine marks shouldTerminate before Dart cleanup completes. Own
// the pending/approved distinction so another Cmd+Q cannot bypass that cleanup.
final class ApplicationTerminationCoordinator {
  private let scheduleTermination: (@escaping () -> Void) -> Void
  private var pending = false
  private var approved = false

  init(scheduleTermination: @escaping (@escaping () -> Void) -> Void = { action in
    DispatchQueue.main.async(execute: action)
  }) {
    self.scheduleTermination = scheduleTermination
  }

  func requestExit(
    using request: (@escaping (Bool) -> Void) -> Void,
    terminate: @escaping () -> Void
  ) -> NSApplication.TerminateReply {
    if approved { return .terminateNow }
    if pending { return .terminateCancel }
    pending = true
    request { [weak self] approved in
      guard let self = self else { return }
      if approved {
        // This reply is still on Flutter's platform-message stack. Terminating
        // here shuts down the engine before that stack has returned. Keep
        // duplicate quit requests blocked until the queued action runs too.
        self.scheduleTermination { [weak self] in
          guard let self = self else { return }
          self.pending = false
          self.approved = true
          terminate()
        }
      } else {
        self.pending = false
      }
    }
    return .terminateCancel
  }
}
