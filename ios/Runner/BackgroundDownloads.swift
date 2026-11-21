import Flutter
import UIKit

/// URLSession owns the network transfer while the Flutter engine is suspended.
/// Only the repository can publish the response after checking Range and ETag.
final class BackgroundDownloads: NSObject, URLSessionDownloadDelegate {
  static let identifier = (Bundle.main.bundleIdentifier ?? "bilisail") + ".downloads"
  private let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent("bilisail-track-responses", isDirectory: true)
  private lazy var session: URLSession = {
    let config = URLSessionConfiguration.background(withIdentifier: BackgroundDownloads.identifier)
    config.isDiscretionary = false
    config.httpShouldSetCookies = false
    config.httpCookieStorage = nil
    config.urlCredentialStorage = nil
    config.urlCache = nil
    config.timeoutIntervalForRequest = 20
    config.timeoutIntervalForResource = 3 * 60 * 60
    return URLSession(configuration: config, delegate: self, delegateQueue: .main)
  }()
  private var tasks: [Int: URLSessionDownloadTask] = [:]
  private var replies: [Int: FlutterResult] = [:]
  private var deadlines: [Int: DispatchWorkItem] = [:]
  private var channel: FlutterMethodChannel?
  private var executionTime: UIBackgroundTaskIdentifier = .invalid
  private var finishEvents: (() -> Void)?
  private var receivedAllEvents = false
  private var eventDeadline: DispatchWorkItem?

  override init() {
    super.init()
    // Previous-process downloads have no live account/run owner.
    try? FileManager.default.removeItem(at: directory)
    session.getAllTasks { [weak self] previous in
      DispatchQueue.main.async {
        guard let self = self else { return }
        for task in previous where self.replies[task.taskIdentifier] == nil { task.cancel() }
      }
    }
  }

  func attach(to messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "dev.bilisail/background_downloads", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "setActive":
        if call.arguments as? Bool == true { self.beginExecutionTime() }
        else { self.endExecutionTime(); self.acknowledgeEvents() }
        result(nil)
      case "fetch":
        self.fetch(call, result)
      case "cancel":
        if let id = call.arguments as? Int { self.tasks[id]?.cancel() }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func fetch(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let id = args["id"] as? Int,
          let raw = args["url"] as? String, let url = URL(string: raw),
          ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
          let headers = args["headers"] as? [String: String], let timeout = args["timeout"] as? Int else {
      result(FlutterError(code: "request", message: "Invalid download request.", details: nil))
      return
    }
    var request = URLRequest(url: url)
    request.allHTTPHeaderFields = headers
    let task = session.downloadTask(with: request)
    let taskId = task.taskIdentifier
    tasks[id] = task
    replies[taskId] = result
    let cancel = DispatchWorkItem { [weak task] in task?.cancel() }
    deadlines[taskId] = cancel
    DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(timeout), execute: cancel)
    task.resume()
    acknowledgeEvents()
  }

  private func takeReply(_ task: URLSessionTask) -> FlutterResult? {
    tasks = tasks.filter { $0.value.taskIdentifier != task.taskIdentifier }
    deadlines.removeValue(forKey: task.taskIdentifier)?.cancel()
    return replies.removeValue(forKey: task.taskIdentifier)
  }

  func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                  didFinishDownloadingTo location: URL) {
    guard let reply = takeReply(downloadTask) else { return }
    guard let response = downloadTask.response as? HTTPURLResponse else {
      reply(FlutterError(code: "response", message: "Missing HTTP response.", details: nil))
      return
    }
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      let file = directory.appendingPathComponent(UUID().uuidString)
      try FileManager.default.moveItem(at: location, to: file)
      // Keep the original Content-Length semantics for 200 and chunked 206.
      var value: [String: Any] = [
        "file": file.path, "status": response.statusCode,
        "length": Int64(response.value(forHTTPHeaderField: "Content-Length") ?? "") ?? -1,
      ]
      value["range"] = response.value(forHTTPHeaderField: "Content-Range")
      value["etag"] = response.value(forHTTPHeaderField: "ETag")
      beginExecutionTime()
      reply(value)
    } catch {
      reply(FlutterError(code: "storage", message: "Could not stage response.", details: nil))
    }
  }

  func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
    if let reply = takeReply(task) {
      let code = (error as? URLError)?.code == .timedOut ? "timeout" : "network"
      reply(FlutterError(code: code, message: "Background download interrupted.", details: nil))
    }
  }

  func handleEvents(completion: @escaping () -> Void) {
    finishEvents = completion
    if receivedAllEvents { acknowledgeEvents() }
  }

  func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
    receivedAllEvents = true
    // Allow Dart to validate this track and submit the next before iOS
    // suspends the app. Cold launches have no live repository run.
    guard executionTime != .invalid else { acknowledgeEvents(); return }
    let deadline = DispatchWorkItem { [weak self] in self?.acknowledgeEvents() }
    eventDeadline?.cancel()
    eventDeadline = deadline
    DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: deadline)
  }

  private func acknowledgeEvents() {
    guard receivedAllEvents, let finish = finishEvents else { return }
    eventDeadline?.cancel()
    eventDeadline = nil
    receivedAllEvents = false
    finishEvents = nil
    finish()
  }

  private func beginExecutionTime() {
    guard executionTime == .invalid else { return }
    executionTime = UIApplication.shared.beginBackgroundTask(withName: "Download queue") { [weak self] in
      self?.endExecutionTime()
      self?.acknowledgeEvents()
    }
  }

  private func endExecutionTime() {
    guard executionTime != .invalid else { return }
    UIApplication.shared.endBackgroundTask(executionTime)
    executionTime = .invalid
  }
}
