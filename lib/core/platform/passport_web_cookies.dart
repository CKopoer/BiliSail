import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

final class PassportWebCookieReader {
  PassportWebCookieReader({TargetPlatform? platform})
    : platform = platform ?? defaultTargetPlatform;

  final TargetPlatform platform;
  bool get usesNativeStore =>
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;

  // The pinned Apple plugin does not expose its WKWebView by ID. A per-attempt
  // user-agent suffix lets our native adapter find that exact view using public
  // WebKit APIs, without reading another window's or the default store's cookies.
  late final String viewMarker = _createMarker();

  static String _createMarker() {
    final random = Random.secure();
    return 'BiliSailPassport/${List.generate(16, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  Future<String> createUserAgent() async {
    if (!usesNativeStore) return '';
    // The Apple plugin skips applicationNameForUserAgent when WebKit's default
    // application name is nil (macOS). Set customUserAgent from the system UA.
    final userAgent = await InAppWebViewController.getDefaultUserAgent()
        .timeout(const Duration(seconds: 10));
    if (userAgent.isEmpty) {
      throw StateError('Missing system WebView user agent');
    }
    return '$userAgent $viewMarker';
  }

  Future<List<Cookie>> read(
    InAppWebViewController controller, {
    WebViewEnvironment? environment,
  }) async {
    if (!usesNativeStore) {
      return CookieManager.instance(webViewEnvironment: environment).getCookies(
        url: WebUri('https://api.bilibili.com/'),
        webViewController: controller,
      );
    }
    // CookieManager on iOS/macOS 1.2.0-beta.3 ignores webViewController and reads
    // WKWebsiteDataStore.default(), while incognito uses nonPersistent().
    final values = await const MethodChannel('bilisail/passport_web_cookies')
        .invokeListMethod<Object?>('getCookies', {'marker': viewMarker});
    if (values == null || values.length > 128) {
      throw const FormatException('Invalid native cookie list');
    }
    return [for (final value in values) _decode(value)];
  }

  Cookie _decode(Object? value) {
    if (value
        case {
          'name': final String name,
          'value': final String content,
          'domain': final String domain,
          'path': final String path,
          'isSecure': final bool secure,
          'isHttpOnly': final bool httpOnly,
          'isSessionOnly': final bool sessionOnly,
          'expiresDate': final Object? expiry,
        }
        when domain.isNotEmpty &&
            path.startsWith('/') &&
            (expiry == null || expiry is int)) {
      return Cookie(
        name: name,
        value: content,
        domain: domain,
        path: path,
        isSecure: secure,
        isHttpOnly: httpOnly,
        isSessionOnly: sessionOnly,
        expiresDate: expiry as int?,
      );
    }
    throw const FormatException('Incomplete native cookie metadata');
  }
}
