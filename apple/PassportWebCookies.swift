import Foundation
import WebKit
#if os(iOS)
import Flutter
import UIKit
typealias PassportNativeView = UIView
#else
import FlutterMacOS
import AppKit
typealias PassportNativeView = NSView
#endif

// Read HttpOnly cookies from the login view's nonpersistent store. The pinned
// plugin's CookieManager always reads the unrelated default WKWebsiteDataStore.
final class PassportWebCookies {
  private let channel: FlutterMethodChannel
  private let roots: () -> [PassportNativeView]

  init(messenger: FlutterBinaryMessenger, roots: @escaping () -> [PassportNativeView]) {
    self.roots = roots
    channel = FlutterMethodChannel(name: "bilisail/passport_web_cookies", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getCookies" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let self = self, let args = call.arguments as? [String: Any],
            let marker = args["marker"] as? String,
            marker.range(of: "^BiliSailPassport/[0-9a-f]{32}$", options: .regularExpression) != nil else {
        result(FlutterError(code: "invalid_attempt", message: "Invalid login attempt.", details: nil))
        return
      }
      Self.read(marker: marker, roots: self.roots(), result: result)
    }
  }

  static func read(marker: String, roots: [PassportNativeView], result: @escaping FlutterResult) {
    var matches: [WKWebView] = []
    func visit(_ view: PassportNativeView) {
      if let webView = view as? WKWebView {
        let name = webView.customUserAgent ?? ""
        if name == marker || name.hasSuffix(" " + marker) {
          if !matches.contains(where: { $0 === webView }) { matches.append(webView) }
        }
        return
      }
      for child in view.subviews { visit(child) }
    }
    for root in roots { visit(root) }
    // Creation may precede attachment to the native view tree; the next poll
    // retries. Never fall back to another view or the persistent cookie store.
    guard !matches.isEmpty else { result([]); return }
    guard matches.count == 1, let webView = matches.first,
          !webView.configuration.websiteDataStore.isPersistent else {
      result(FlutterError(code: "ambiguous_view", message: "Login view is not isolated.", details: nil))
      return
    }
    webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak webView] cookies in
      guard let webView = webView, webView.superview != nil else { result([]); return }
      let applicable = cookies.filter { isApplicable($0) }
      guard applicable.count <= 128 else {
        result(FlutterError(code: "cookie_limit", message: "Too many login cookies.", details: nil))
        return
      }
      result(applicable.map { cookie -> [String: Any] in
        var value: [String: Any] = [
          "name": cookie.name, "value": cookie.value, "domain": cookie.domain,
          "path": cookie.path, "isSecure": cookie.isSecure,
          "isHttpOnly": cookie.isHTTPOnly, "isSessionOnly": cookie.isSessionOnly,
          "expiresDate": NSNull(),
        ]
        if let expiry = cookie.expiresDate {
          value["expiresDate"] = Int64(expiry.timeIntervalSince1970 * 1000)
        }
        return value
      })
    }
  }

  static func isApplicable(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
    let domain = cookie.domain.lowercased()
    let host = "api.bilibili.com"
    let domainMatches = domain.hasPrefix(".")
      ? host == String(domain.dropFirst()) || host.hasSuffix(domain)
      : host == domain
    return domainMatches && cookie.path == "/" &&
      (cookie.expiresDate.map { $0 > now } ?? true)
  }
}
