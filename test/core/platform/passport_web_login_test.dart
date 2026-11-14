import 'package:bilisail/core/platform/passport_web_login.dart';
import 'package:webview_all/webview_all.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('native UTC expiry and domain scope are retained', () {
    final expiry = DateTime.utc(2027);
    final cookie = BrowserLoginCookie.fromNative(
      WebViewCookie(
        name: 'SESSDATA',
        value: 'fixture',
        domain: '.BILIBILI.COM',
        isSecure: true,
        isSession: false,
        expires: expiry,
      ),
    );
    expect(cookie.expires, expiry);
    expect(cookie.domain, 'bilibili.com');
    expect(cookie.hostOnly, isFalse);
  });
  test('native host-only and session cookies keep their identity', () {
    final cookie = BrowserLoginCookie.fromNative(
      const WebViewCookie(
        name: 'SESSDATA',
        value: 'fixture',
        domain: 'api.bilibili.com',
        isSecure: true,
        isSession: true,
      ),
    );
    expect(cookie.expires, isNull);
    expect(cookie.hostOnly, isTrue);
  });
  test('missing metadata is rejected', () {
    expect(
      () => BrowserLoginCookie.fromNative(
        const WebViewCookie(
          name: 'SESSDATA',
          value: 'fixture',
          domain: '.bilibili.com',
        ),
      ),
      throwsFormatException,
    );
  });
}
