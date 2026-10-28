import XCTest
import WebKit
#if os(iOS)
import Flutter
@testable import Runner
#else
import FlutterMacOS
@testable import BiliSail
#endif

final class PassportWebCookiesTests: XCTestCase {
  private let marker = "BiliSailPassport/0123456789abcdef0123456789abcdef"

  @MainActor
  func testReadsOnlyTheMatchingPrivateViewIncludingHttpOnlyCookies() {
    let root = PassportNativeView(frame: .zero)
    let current = makeView(marker: marker)
    let otherMarker = "BiliSailPassport/ffffffffffffffffffffffffffffffff"
    let other = makeView(marker: otherMarker)
    root.addSubview(other)
    root.addSubview(current)
    let saved = expectation(description: "Private cookie saved")
    let expiry = Date(timeIntervalSince1970: 2000000000)
    let cookie = makeCookie(value: "fixture-current", expiry: expiry)
    current.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { saved.fulfill() }
    wait(for: [saved], timeout: 5)
    let read = expectation(description: "Read current store")
    PassportWebCookies.read(marker: marker, roots: [root]) { result in
      guard let cookies = result as? [[String: Any]], let cookie = cookies.first else {
        return XCTFail("Missing private cookie")
      }
      XCTAssertEqual(cookies.count, 1)
      XCTAssertEqual(cookie["value"] as? String, "fixture-current")
      XCTAssertEqual(cookie["domain"] as? String, ".bilibili.com")
      XCTAssertEqual(cookie["path"] as? String, "/")
      XCTAssertEqual(cookie["isHttpOnly"] as? Bool, true)
      XCTAssertEqual(cookie["isSecure"] as? Bool, true)
      XCTAssertEqual(cookie["expiresDate"] as? Int64, 2000000000000)
      read.fulfill()
    }
    wait(for: [read], timeout: 5)
    let next = expectation(description: "Other private store is empty")
    PassportWebCookies.read(marker: otherMarker, roots: [root]) { result in
      XCTAssertEqual((result as? [[String: Any]])?.count, 0)
      next.fulfill()
    }
    wait(for: [next], timeout: 5)
  }

  @MainActor
  func testMissingViewNeverReadsTheDefaultStoreAndAmbiguousViewsAreRejected() {
    let root = PassportNativeView(frame: .zero)
    PassportWebCookies.read(marker: marker, roots: [root]) { result in
      XCTAssertEqual((result as? [[String: Any]])?.count, 0)
    }
    root.addSubview(makeView(marker: marker))
    root.addSubview(makeView(marker: marker))
    PassportWebCookies.read(marker: marker, roots: [root]) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "ambiguous_view")
    }
  }

  @MainActor
  func testPersistentViewIsRejected() {
    let root = PassportNativeView(frame: .zero)
    let config = WKWebViewConfiguration()
    let view = WKWebView(frame: .zero, configuration: config)
    view.customUserAgent = "Default " + marker
    root.addSubview(view)
    PassportWebCookies.read(marker: marker, roots: [root]) { result in
      XCTAssertEqual((result as? FlutterError)?.code, "ambiguous_view")
    }
  }

  func testApiCookieScopeAndExpiry() {
    XCTAssertTrue(PassportWebCookies.isApplicable(makeCookie()))
    XCTAssertTrue(PassportWebCookies.isApplicable(makeCookie(domain: "api.bilibili.com")))
    XCTAssertFalse(PassportWebCookies.isApplicable(makeCookie(domain: ".bilibili.com.invalid")))
    XCTAssertFalse(PassportWebCookies.isApplicable(makeCookie(domain: "passport.bilibili.com")))
    XCTAssertFalse(PassportWebCookies.isApplicable(makeCookie(path: "/login")))
    XCTAssertFalse(PassportWebCookies.isApplicable(makeCookie(expiry: Date(timeIntervalSince1970: 1))))
  }

  @MainActor
  private func makeView(marker: String) -> WKWebView {
    let config = WKWebViewConfiguration()
    config.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: config)
    view.customUserAgent = "Default " + marker
    return view
  }

  private func makeCookie(value: String = "fixture", domain: String = ".bilibili.com",
                          path: String = "/", expiry: Date? = nil) -> HTTPCookie {
    var properties: [HTTPCookiePropertyKey: Any] = [
      .name: "SESSDATA", .value: value, .domain: domain, .path: path,
      .secure: "TRUE", .init("HttpOnly"): "YES",
    ]
    if let expiry = expiry { properties[.expires] = expiry }
    return HTTPCookie(properties: properties)!
  }
}
