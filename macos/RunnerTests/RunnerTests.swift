import Cocoa
import FlutterMacOS
import XCTest
@testable import BiliSail

class RunnerTests: XCTestCase {

  func testMiniPlayerRetirementNeverRestoresClosingWindow() {
    let suite = "BiliSail.MiniRetirement.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    var mini: MiniPlaybackPresentation? = MiniPlaybackPresentation(window: window, defaults: defaults)
    let compact = window.frame
    let style = window.styleMask
    let minimum = window.minSize
    mini?.retire()
    mini?.restore()
    mini = nil
    XCTAssertEqual(window.frame, compact)
    XCTAssertEqual(window.styleMask, style)
    XCTAssertEqual(window.minSize, minimum)
    XCTAssertEqual(window.level, .floating)
    XCTAssertFalse(MiniPlaybackPresentation.contains(window))
    XCTAssertEqual(defaults.array(forKey: "bilisail.windowGeometry.v1.miniPlayer") as? [Double],
      [Double(compact.minX), Double(compact.minY), Double(compact.width), Double(compact.height)])
  }

  func testMiniPlayerWindowCloseAndDeinitOnlyRemoveTracking() {
    for closeFirst in [false, true] {
      let suite = "BiliSail.MiniClose.\(UUID().uuidString)"
      let defaults = UserDefaults(suiteName: suite)!
      defer { defaults.removePersistentDomain(forName: suite) }
      let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
        styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      var mini: MiniPlaybackPresentation? = MiniPlaybackPresentation(window: window, defaults: defaults)
      let compact = window.frame
      let style = window.styleMask
      if closeFirst {
        window.close()
        XCTAssertFalse(MiniPlaybackPresentation.contains(window))
        mini?.restore()
      }
      mini = nil
      XCTAssertEqual(window.frame, compact)
      XCTAssertEqual(window.styleMask, style)
      XCTAssertFalse(MiniPlaybackPresentation.contains(window))
    }
  }

  func testMiniPlayerExplicitRestoreStillRestoresNormalPresentation() {
    let suite = "BiliSail.MiniRestore.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let window = NSWindow(contentRect: NSRect(x: 100, y: 100, width: 900, height: 600),
      styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    defer { window.close() }
    let frame = window.frame
    let style = window.styleMask
    let minimum = window.minSize
    let mini = MiniPlaybackPresentation(window: window, defaults: defaults)
    mini.restore()
    mini.retire()
    XCTAssertEqual(window.frame, frame)
    XCTAssertEqual(window.styleMask, style)
    XCTAssertEqual(window.minSize, minimum)
    XCTAssertEqual(window.level, .normal)
    XCTAssertFalse(MiniPlaybackPresentation.contains(window))
  }

  func testFullscreenTabClosePreservesSurvivingTabsAndDefersDuplicateReplies() {
    var scheduled: [() -> Void] = []
    var closes = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { true },
      toggle: { XCTFail("Closing one tab must preserve the group's fullscreen Space") },
      hasOtherTabbedWindows: { true }, schedule: { scheduled.append($0) })
    coordinator.prepareToClose { error in XCTAssertNil(error); closes += 1 }
    coordinator.prepareToClose { error in XCTAssertNil(error); closes += 1 }
    XCTAssertEqual(closes, 0)
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(closes, 2)
    coordinator.setFullScreen(false) { error in XCTAssertNil(error) }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error) }
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(closes, 2)
  }

  func testTabCloseDuringEntryWaitsForTransitionAndKeepsSharedFullscreen() {
    var scheduled: [() -> Void] = []
    var fullscreen = false
    var otherTabs = false
    var toggles = 0
    var closes = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, hasOtherTabbedWindows: { otherTabs },
      schedule: { scheduled.append($0) })
    coordinator.setFullScreen(true) { error in XCTAssertNil(error) }
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(toggles, 1)
    coordinator.prepareToClose { error in XCTAssertNil(error); closes += 1 }
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(closes, 0)
    fullscreen = true
    otherTabs = true
    coordinator.transitionDidEnd()
    XCTAssertEqual(closes, 0)
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(closes, 1)
    XCTAssertEqual(toggles, 1)
    XCTAssertTrue(fullscreen)
  }

  func testCloseRechecksTabGroupAfterTransitionBeforeExitingLastFullscreenWindow() {
    var scheduled: [() -> Void] = []
    var fullscreen = true
    var otherTabs = true
    var toggles = 0
    var closes = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, hasOtherTabbedWindows: { otherTabs },
      schedule: { scheduled.append($0) })
    coordinator.transitionWillStart()
    coordinator.prepareToClose { error in XCTAssertNil(error); closes += 1 }
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(closes, 0)
    XCTAssertEqual(toggles, 0)
    otherTabs = false
    coordinator.transitionDidEnd()
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(closes, 0)
    fullscreen = false
    coordinator.transitionDidEnd()
    while !scheduled.isEmpty { scheduled.removeFirst()() }
    XCTAssertEqual(closes, 1)
  }

  func testPlaybackFullscreenExitPreservesExistingWindowAndTabGroupFullscreen() {
    for otherTabs in [false, true] {
      var scheduled: [() -> Void] = []
      var completed = 0
      let coordinator = WindowFullScreenCoordinator(isFullScreen: { true },
        toggle: { XCTFail("Video fullscreen must preserve existing window fullscreen") },
        hasOtherTabbedWindows: { otherTabs }, schedule: { scheduled.append($0) })
      func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
      for _ in 0..<2 {
        coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
        drain()
        coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
        drain()
      }
      XCTAssertEqual(completed, 4)
    }
  }

  func testPlaybackFullscreenSamplesSystemEntryAfterItsAnimation() {
    var scheduled: [() -> Void] = []
    var fullscreen = false
    var completed = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { XCTFail("An existing system entry must not be undone by video exit") },
      schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.transitionWillStart()
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(completed, 0)
    fullscreen = true
    coordinator.transitionDidEnd()
    XCTAssertEqual(completed, 0)
    drain()
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(completed, 2)
    XCTAssertTrue(fullscreen)
  }

  func testPlaybackOwnedFullscreenExitStillAppliesToTabbedWindowAfterRepeatedEntry() {
    var scheduled: [() -> Void] = []
    var fullscreen = false
    var toggles = 0
    var entries = 0
    var exits = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, hasOtherTabbedWindows: { true },
      schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); entries += 1 }
    drain()
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(entries, 0)
    // Repeating the request after native entry must retain its original owner.
    fullscreen = true
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); entries += 1 }
    coordinator.transitionDidEnd()
    drain()
    XCTAssertEqual(entries, 2)
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); exits += 1 }
    drain()
    XCTAssertEqual(toggles, 2)
    XCTAssertEqual(exits, 0)
    fullscreen = false
    coordinator.transitionDidEnd()
    XCTAssertEqual(exits, 0)
    drain()
    XCTAssertEqual(exits, 1)
  }

  func testVideoExitDoesNotReenterFullscreenAfterUserSystemExit() {
    var scheduled: [() -> Void] = []
    var fullscreen = true
    var exits = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { XCTFail("Video cleanup must not reverse the user's system exit") },
      schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error) }
    drain()
    coordinator.transitionWillStart()
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); exits += 1 }
    drain()
    XCTAssertEqual(exits, 0)
    fullscreen = false
    coordinator.transitionDidEnd()
    drain()
    XCTAssertEqual(exits, 1)
    XCTAssertFalse(fullscreen)
  }

  func testVideoExitDuringOwnedEntryWaitsForBothNativeAnimations() {
    var scheduled: [() -> Void] = []
    var fullscreen = false
    var toggles = 0
    var completed = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
    drain()
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(completed, 0)
    fullscreen = true
    coordinator.transitionDidEnd()
    drain()
    XCTAssertEqual(toggles, 2)
    XCTAssertEqual(completed, 1)
    fullscreen = false
    coordinator.transitionDidEnd()
    XCTAssertEqual(completed, 1)
    drain()
    XCTAssertEqual(completed, 2)
  }

  func testPlaybackFullscreenRecapturesWindowStateForEachPresentation() {
    var scheduled: [() -> Void] = []
    var fullscreen = true
    var toggles = 0
    var completed = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(toggles, 0)
    fullscreen = false
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(toggles, 1)
    fullscreen = true
    coordinator.transitionDidEnd()
    drain()
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(toggles, 2)
    fullscreen = false
    coordinator.transitionDidEnd()
    drain()
    XCTAssertEqual(completed, 4)
    // Duplicate cleanup after the user enters system fullscreen is a no-op.
    fullscreen = true
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(toggles, 2)
    XCTAssertEqual(completed, 5)
  }

  func testCloseSupersedesQueuedVideoExitAndKeepsSharedFullscreen() {
    var scheduled: [() -> Void] = []
    var fullscreen = false
    var otherTabs = false
    var toggles = 0
    var completed = 0
    let coordinator = WindowFullScreenCoordinator(isFullScreen: { fullscreen },
      toggle: { toggles += 1 }, hasOtherTabbedWindows: { otherTabs },
      schedule: { scheduled.append($0) })
    func drain() { while !scheduled.isEmpty { scheduled.removeFirst()() } }
    coordinator.setFullScreen(true) { error in XCTAssertNil(error); completed += 1 }
    drain()
    fullscreen = true
    coordinator.transitionDidEnd()
    drain()
    XCTAssertEqual(toggles, 1)
    otherTabs = true
    coordinator.setFullScreen(false) { error in XCTAssertNil(error); completed += 1 }
    coordinator.prepareToClose { error in XCTAssertNil(error); completed += 1 }
    coordinator.prepareToClose { error in XCTAssertNil(error); completed += 1 }
    drain()
    XCTAssertEqual(toggles, 1)
    XCTAssertEqual(completed, 4)
    XCTAssertTrue(fullscreen)
  }

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
    var reply: ((ApplicationExitResponse) -> Void)?
    var requests = 0
    var terminations = 0
    let request: (@escaping (ApplicationExitResponse) -> Void) -> Void = { callback in
      requests += 1
      reply = callback
    }
    let terminate = { terminations += 1 }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 1)
    XCTAssertEqual(terminations, 0)
    reply?(.exit)
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
    var reply: ((ApplicationExitResponse) -> Void)?
    var requests = 0
    let request: (@escaping (ApplicationExitResponse) -> Void) -> Void = { callback in
      requests += 1
      reply = callback
    }
    let terminate = { XCTFail("Cancelled cleanup must keep the application open") }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    reply?(.cancel)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(requests, 2)
    reply?(.cancel)
  }

  func testSynchronousCleanupStillDefersTermination() {
    var scheduled: [() -> Void] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) })
    var requesting = false
    var terminations = 0
    let request: (@escaping (ApplicationExitResponse) -> Void) -> Void = { callback in
      requesting = true
      callback(.exit)
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
      callback(.exit)
      replying = false
    }, terminate: {
      XCTAssertFalse(replying)
      XCTAssertTrue(Thread.isMainThread)
      terminated.fulfill()
    }), .terminateCancel)
    wait(for: [terminated], timeout: 2)
  }

  func testUnansweredQuitTimesOutWithoutWaitingForDart() {
    var scheduled: [() -> Void] = []
    var timeout: (() -> Void)?
    var reply: ((ApplicationExitResponse) -> Void)?
    var cancellations = 0
    var terminations = 0
    var failures: [ApplicationTerminationFailure] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) },
      scheduleTimeout: { delay, action in
        XCTAssertEqual(delay, 30)
        timeout = action
        return { cancellations += 1 }
      }, onFailure: { failures.append($0) })
    let request: (@escaping (ApplicationExitResponse) -> Void) -> Void = { reply = $0 }
    let terminate = { terminations += 1 }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    XCTAssertEqual(terminations, 0)
    timeout?()
    XCTAssertEqual(cancellations, 1)
    XCTAssertEqual(failures, [.timeout])
    XCTAssertEqual(scheduled.count, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    // Late/duplicate replies cannot undo or duplicate a timeout-approved exit.
    reply?(.cancel)
    reply?(.exit)
    timeout?()
    XCTAssertEqual(scheduled.count, 1)
    XCTAssertEqual(failures, [.timeout])
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateNow)
  }

  func testCleanupApprovalCancelsDeadlineAndIgnoresDuplicateReplies() {
    var scheduled: [() -> Void] = []
    var timeout: (() -> Void)?
    var reply: ((ApplicationExitResponse) -> Void)?
    var cancellations = 0
    var terminations = 0
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) },
      scheduleTimeout: { _, action in
        timeout = action
        return { cancellations += 1 }
      }, onFailure: { _ in XCTFail("Successful cleanup is not a fallback") })
    XCTAssertEqual(coordinator.requestExit(using: { reply = $0 }, terminate: { terminations += 1 }),
                   .terminateCancel)
    reply?(.exit)
    timeout?()
    reply?(.exit)
    reply?(.cancel)
    XCTAssertEqual(cancellations, 1)
    XCTAssertEqual(scheduled.count, 1)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
  }

  func testCancelledQuitInvalidatesItsTimeoutAndRepliesAcrossRetry() {
    var scheduled: [() -> Void] = []
    var timeouts: [() -> Void] = []
    var replies: [(ApplicationExitResponse) -> Void] = []
    var cancellations = 0
    var terminations = 0
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) },
      scheduleTimeout: { _, action in
        timeouts.append(action)
        return { cancellations += 1 }
      }, onFailure: { _ in XCTFail("Old attempts cannot force a later quit") })
    let request: (@escaping (ApplicationExitResponse) -> Void) -> Void = { replies.append($0) }
    let terminate = { terminations += 1 }
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    replies[0](.cancel)
    XCTAssertEqual(cancellations, 1)
    timeouts[0]()
    XCTAssertTrue(scheduled.isEmpty)
    XCTAssertEqual(coordinator.requestExit(using: request, terminate: terminate), .terminateCancel)
    timeouts[0]()
    replies[0](.exit)
    replies[0](.unavailable)
    XCTAssertTrue(scheduled.isEmpty)
    replies[1](.exit)
    XCTAssertEqual(cancellations, 2)
    XCTAssertEqual(scheduled.count, 1)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
  }

  func testUnavailableDartReplyAllowsDeferredNativeQuit() {
    var scheduled: [() -> Void] = []
    var cancellations = 0
    var terminations = 0
    var failures: [ApplicationTerminationFailure] = []
    let coordinator = ApplicationTerminationCoordinator(scheduleTermination: { scheduled.append($0) },
      scheduleTimeout: { _, _ in { cancellations += 1 } },
      onFailure: { failures.append($0) })
    var requesting = false
    XCTAssertEqual(coordinator.requestExit(using: { reply in
      requesting = true
      reply(.unavailable)
      requesting = false
    }, terminate: {
      XCTAssertFalse(requesting)
      terminations += 1
    }), .terminateCancel)
    XCTAssertEqual(cancellations, 1)
    XCTAssertEqual(failures, [.unavailable])
    XCTAssertEqual(terminations, 0)
    scheduled.removeFirst()()
    XCTAssertEqual(terminations, 1)
  }

  func testExitReplyRequiresExplicitCancellation() {
    XCTAssertEqual(ApplicationExitResponse(channelReply: ["response": "exit"]), .exit)
    XCTAssertEqual(ApplicationExitResponse(channelReply: ["response": "cancel"]), .cancel)
    let unavailableReplies: [Any?] = [nil, FlutterMethodNotImplemented,
      FlutterError(code: "unavailable", message: nil, details: nil),
      [:], ["response": "unknown"], ["response": true], "cancel"]
    for reply in unavailableReplies {
      XCTAssertEqual(ApplicationExitResponse(channelReply: reply), .unavailable)
    }
  }

}
