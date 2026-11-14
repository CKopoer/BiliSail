import 'package:webview_all/webview_all.dart';

final class PassportWebCookieReader {
  static final apiRoot = Uri.https('api.bilibili.com', '/');
  static const requiredAttributes = {
    WebViewCookieAttribute.domain,
    WebViewCookieAttribute.path,
    WebViewCookieAttribute.expires,
    WebViewCookieAttribute.secure,
    WebViewCookieAttribute.httpOnly,
    WebViewCookieAttribute.session,
  };

  Future<void> checkSupport(WebViewSession session) async {
    final capabilities = await session.cookieManager.getCapabilities();
    if (!capabilities.readableAttributes.containsAll(requiredAttributes)) {
      throw const FormatException('Incomplete native cookie capabilities');
    }
  }

  Future<List<WebViewCookie>> read(WebViewSession session) async {
    // The session manager addresses the view's actual store, including HttpOnly
    // cookies. Never use the default manager or document.cookie as a fallback.
    final cookies = await session.cookieManager.getCookies(domain: apiRoot);
    if (cookies.length > 128) {
      throw const FormatException('Invalid native cookie list');
    }
    for (final cookie in cookies) {
      cookie.validate();
      if (cookie.isSecure == null ||
          cookie.isHttpOnly == null ||
          cookie.isSession == null ||
          (cookie.isSession == false && cookie.expires == null)) {
        throw const FormatException('Incomplete native cookie metadata');
      }
    }
    return cookies;
  }
}
