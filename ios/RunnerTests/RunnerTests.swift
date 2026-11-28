import Flutter
import MediaPlayer
import UIKit
import XCTest
import audio_service

class RunnerTests: XCTestCase {
  @MainActor
  func testNowPlayingFollowsBackgroundVisibility() {
    let plugin: FlutterPlugin = AudioServicePlugin()
    let center = MPNowPlayingInfoCenter.default()
    let notifications = NotificationCenter.default
    func send(_ method: String, _ arguments: [String: Any] = [:]) {
      plugin.handle?(FlutterMethodCall(methodName: method, arguments: arguments), result: { _ in })
    }
    func item(_ title: String) {
      send("setMediaItem", ["mediaItem": ["id": "test", "title": title, "artUri": NSNull()]])
    }
    func update(playing: Bool, milliseconds: Int) {
      send("setState", ["state": [
        "processingState": 3, // AudioProcessingState.ready
        "playing": playing, "speed": 1.0, "updatePosition": milliseconds,
        "controls": [], "systemActions": [],
      ] as [String: Any]])
    }
    func foreground() {
      notifications.post(name: UIApplication.willEnterForegroundNotification, object: UIApplication.shared)
    }
    func background() {
      notifications.post(name: UIApplication.didEnterBackgroundNotification, object: UIApplication.shared)
    }

    defer {
      send("stopService")
      foreground()
    }
    foreground()
    item("First")
    update(playing: true, milliseconds: 4000)
    notifications.post(name: UIApplication.willResignActiveNotification, object: UIApplication.shared)
    XCTAssertNil(center.nowPlayingInfo)

    background()
    XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "First")
    XCTAssertEqual(center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 4)
    update(playing: false, milliseconds: 6000)
    XCTAssertEqual(center.nowPlayingInfo?[MPNowPlayingInfoPropertyPlaybackRate] as? Double, 0)

    foreground()
    XCTAssertNil(center.nowPlayingInfo)
    item("Latest")
    XCTAssertNil(center.nowPlayingInfo)
    background()
    XCTAssertEqual(center.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Latest")
    XCTAssertEqual(center.nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double, 6)

    send("stopService")
    item("Late artwork callback")
    XCTAssertNil(center.nowPlayingInfo)
    foreground()
    background()
    XCTAssertNil(center.nowPlayingInfo)
  }
}
