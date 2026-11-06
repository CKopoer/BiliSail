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
    NativeLifecycleEvent.engineStarting.record()
    applicationStarted = application.start()
    (applicationStarted ? NativeLifecycleEvent.engineStarted : .engineStartFailed).record()
    ReleaseSmokeNativeStage.engineRunning.emit()
    if !applicationStarted { NSApp.terminate(nil) }
  }

  override func applicationWillTerminate(_ notification: Notification) {
    NativeLifecycleEvent.applicationTerminating.record()
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

// These markers remain available in the macOS unified log when Dart cannot
// write its own diagnostics. No arguments, window titles or user data.
enum NativeLifecycleEvent: String {
  case engineStarting = "engine-starting"
  case engineStarted = "engine-started"
  case engineStartFailed = "engine-start-failed"
  case applicationTerminating = "application-terminating"
  case engineShutdownBegin = "engine-shutdown-begin"
  case engineShutdownEnd = "engine-shutdown-end"
  case systemSleep = "system-sleep"
  case systemWake = "system-wake"

  func record() { NSLog("BILISAIL_LIFECYCLE:%@", rawValue) }
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
  private let scheduleTimeout: (TimeInterval, @escaping () -> Void) -> () -> Void
  private let onFailure: (ApplicationTerminationFailure) -> Void
  private var pending: ExitAttempt?
  private var approved = false

  init(scheduleTermination: @escaping (@escaping () -> Void) -> Void = { action in
    DispatchQueue.main.async(execute: action)
  }, scheduleTimeout: @escaping (TimeInterval, @escaping () -> Void) -> () -> Void = { delay, action in
    let work = DispatchWorkItem(block: action)
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    return { work.cancel() }
  }, onFailure: @escaping (ApplicationTerminationFailure) -> Void = { failure in
    // The Dart logger may already be gone. Only fixed lifecycle markers may
    // enter the native log; never print channel replies or exception details.
    NSLog("BILISAIL_TERMINATION:%@", failure.rawValue)
  }) {
    self.scheduleTermination = scheduleTermination
    self.scheduleTimeout = scheduleTimeout
    self.onFailure = onFailure
  }

  func requestExit(
    using request: (@escaping (ApplicationExitResponse) -> Void) -> Void,
    terminate: @escaping () -> Void
  ) -> NSApplication.TerminateReply {
    if approved { return .terminateNow }
    if pending != nil { return .terminateCancel }
    let attempt = ExitAttempt()
    pending = attempt
    // This deadline belongs to AppKit, not Dart: a lost isolate cannot run a
    // Dart Timer or reply to System.requestAppExit. Only an explicit quit
    // request starts it; long sessions and sleep alone never terminate the app.
    attempt.cancelTimeout = scheduleTimeout(30) { [weak self, weak attempt] in
      guard let self = self, let attempt = attempt else { return }
      self.complete(attempt, response: .unavailable, failure: .timeout, terminate: terminate)
    }
    request { [weak self, weak attempt] response in
      guard let self = self, let attempt = attempt else { return }
      self.complete(attempt, response: response,
                    failure: response == .unavailable ? .unavailable : nil, terminate: terminate)
    }
    return .terminateCancel
  }

  private func complete(_ attempt: ExitAttempt, response: ApplicationExitResponse,
                        failure: ApplicationTerminationFailure?, terminate: @escaping () -> Void) {
    // A cancelled timeout or an old reply can still be queued. It must not
    // approve a newer quit request, cancel a queued exit, or terminate twice.
    guard pending === attempt, !attempt.resolved else { return }
    attempt.resolved = true
    attempt.cancelTimeout?()
    attempt.cancelTimeout = nil
    if response == .cancel {
      pending = nil
      return
    }
    if let failure = failure { onFailure(failure) }
    // Leave Flutter's reply stack before shutting down the shared engine.
    // Duplicate quit requests remain blocked until this queued action runs.
    scheduleTermination { [weak self, weak attempt] in
      guard let self = self, let attempt = attempt, self.pending === attempt else { return }
      self.pending = nil
      self.approved = true
      terminate()
    }
  }

  private final class ExitAttempt {
    var resolved = false
    var cancelTimeout: (() -> Void)?
  }
}

enum ApplicationExitResponse: Equatable {
  case exit, cancel, unavailable

  init(channelReply: Any?) {
    let response = (channelReply as? [String: Any])?["response"] as? String
    switch response {
    case "exit": self = .exit
    case "cancel": self = .cancel
    default: self = .unavailable
    }
  }
}

enum ApplicationTerminationFailure: String {
  case timeout, unavailable
}
