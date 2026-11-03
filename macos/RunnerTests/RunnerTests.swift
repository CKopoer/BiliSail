import Cocoa
import FlutterMacOS
import XCTest
@testable import BiliSail

class RunnerTests: XCTestCase {

  func testFullscreenCloseWaitsForEntryThenExitAndCoalescesDuplicateClose() {
    var scheduled: [() -> Void] = []
    var fullscreen = false
    var toggles = 0
    var entries = 0
    var closes = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); entries += 1 }
    drain()
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(entries, 0)
    coordinator.prepareToClose { error in XCTAssertNil(error); closes += 1 }
    coordinator.prepareToClose { error in XCTAssertNil(error); closes += 1 }
    drain()
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(closes, 0)
    fullscreen = true
    coordinator.transitionDidEnd()
    drain()
    XCTAssertEqual(toggles, 2)
    XCTAssertEqual(closes, 0)
    fullscreen = false
    coordinator.transitionDidEnd()
    // The didExit notification stack must unwind before replying to Dart.
    XCTAssertEqual(closes, 0)
    drain()
    XCTAssertEqual(closes, 2)
    XCTAssertEqual(entries, 1)
    coordinator.setFullScreen(true) { error in XCTAssertNil(error) }
    drain()
    XCTAssertEqual(toggles, 2)
  }

  func testCloseCancelsAQueuedFullscreenEntryBeforeItStarts() {
    var scheduled: [() -> Void] = []
    var completed = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { false },
      toggle: { XCTFail("A retiring window must not enter fullscreen") },
      schedule: { scheduled.append($0) })
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
    coordinator.prepareToClose { error in XCTAssertNil(error); completed += 1 }
    XCTAssertEqual(completed, 0)
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(completed, 2)
  }

  func testSystemFullscreenExitAndAlreadyNormalCloseWaitForQueuedReply() {
    var scheduled: [() -> Void] = []
    var fullscreen = true
    var completed = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { XCTFail("An existing AppKit transition must finish first") },
      schedule: { scheduled.append($0) })
    coordinator.transitionWillStart()
    coordinator.prepareToClose { error in XCTAssertNil(error); completed += 1 }
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(completed, 0)
    fullscreen = false
    coordinator.transitionDidEnd()
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(completed, 1)
    coordinator.prepareToClose { error in XCTAssertNil(error); completed += 1 }
    XCTAssertEqual(completed, 1)
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(completed, 2)
  }

  func testUnexpectedWindowCloseFailsPendingRequestsOutsideNotification() {
    var scheduled: [() -> Void] = []
    var failures = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { true }, toggle: {},
      schedule: { scheduled.append($0) })
    coordinator.prepareToClose { error in XCTAssertNotNil(error); failures += 1 }
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    coordinator.windowClosed()
    XCTAssertEqual(failures, 0)
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(failures, 1)
  }

  @MainActor
  func testPlaybackCaptionHomeVisibilityAndCallbacks() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 360),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
    var backs = 0
    var homes = 0
    let caption = PlaybackTitlebarBack(window: window,
                                      onBack: { backs += 1 }, onHome: { homes += 1 })
    window.addTitlebarAccessoryViewController(caption)
    defer { caption.detach() }
    guard let home = caption.view.subviews.compactMap({ $0 as? NSButton })
      .first(where: { $0.toolTip == "回到主页" }) else {
      return XCTFail("Missing Home button")
    }
    caption.configure(enabled: true, showHome: false)
    XCTAssertTrue(home.isHidden)
    XCTAssertEqual(caption.view.frame.width, 36)
    caption.configure(enabled: true, showHome: true)
    XCTAssertFalse(home.isHidden)
    XCTAssertEqual(caption.view.frame.width, 72)
    home.performClick(nil)
    caption.backButton.performClick(nil)
    XCTAssertEqual(homes, 1)
    XCTAssertEqual(backs, 1)
    caption.configure(enabled: false, showHome: true)
    XCTAssertFalse(home.isEnabled)
    XCTAssertFalse(caption.backButton.isEnabled)
    home.performClick(nil)
    XCTAssertEqual(homes, 1)
  }

  func testRepeatedQuitWaitsForCleanupApproval() {
    var scheduled: [() -> Void] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) })
    var reply: ((Bool) -> Void)?
    var requests = 0
    var terminations = 0
    let request: (@escaping (Bool) -> Void) -> Void = { callback in
      requests += 1
      reply = callback
    }
    let terminate = { terminations += 1 }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(terminations, 0)
    reply?(true)
    XCTAssertEqual(terminations, 0)
    XCTAssertEqual(scheduled.count, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 1)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateNow)
    XCTAssertEqual(requests, 1)
  }

  func testCancelledQuitCanBeRequestedAgain() {
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { _ in
      XCTFail("Cancelled cleanup must not schedule termination")
    })
    var reply: ((Bool) -> Void)?
    var requests = 0
    let request: (@escaping (Bool) -> Void) -> Void = { callback in
      requests += 1
      reply = callback
    }
    let terminate = { XCTFail("Cancelled cleanup must keep the application open") }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    reply?(false)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 2)
    reply?(false)
  }

  func testSynchronousCleanupStillDefersTermination() {
    var scheduled: [() -> Void] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) })
    var requesting = false
    var terminations = 0
    let request: (@escaping (Bool) -> Void) -> Void = { callback in
      requesting = true
      callback(true)
      requesting = false
    }
    let terminate = {
      XCTAssertFalse(requesting)
      terminations += 1
    }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(terminations, 0)
    XCTAssertEqual(scheduled.count, 1)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateNow)
  }

  func testDefaultSchedulerLeavesTheCleanupReplyBeforeTerminating() {
    let coordinator = ApplicationTerminationCoordinator()
    let terminated = expectation(description: "Termination runs on the main queue")
    var replying = false
    XCTAssertEqual(coordinator.requestExit(using: { callback in
      replying = true
      callback(true)
      replying = false
    }, terminate: {
      XCTAssertFalse(replying)
      XCTAssertTrue(Thread.isMainThread)
      terminated.fulfill()
    }), .terminateCancel)
    wait(for: [terminated], timeout: 2)
  }

}
