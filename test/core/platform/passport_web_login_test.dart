import 'package:bilisail/core/platform/passport_web_login.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final windows in [false, true]) {
    test('native expiry retains units for Windows: $windows', () {
      final expiry = DateTime.utc(2027, 1, 1);
      final cookie = BrowserLoginCookie.fromNative(
        Cookie(
          name: 'SESSDATA',
          value: 'fixture',
          domain: '.BILIBILI.COM',
          path: '/',
          isSecure: true,
          isSessionOnly: false,
          expiresDate: windows
              ? expiry.millisecondsSinceEpoch ~/ 1000
              : expiry.millisecondsSinceEpoch,
        ),
        windowsExpiryInSeconds: windows,
      );
      expect(cookie.expires, expiry);
      expect(cookie.domain, 'bilibili.com');
      expect(cookie.hostOnly, isFalse);
    });
  }

  test('native session cookies do not acquire an expiry', () {
    final cookie = BrowserLoginCookie.fromNative(
      Cookie(
        name: 'SESSDATA',
        value: 'fixture',
        isSecure: true,
        isSessionOnly: true,
        expiresDate: -1,
      ),
      windowsExpiryInSeconds: true,
    );
    expect(cookie.expires, isNull);
    expect(cookie.domain, 'api.bilibili.com');
    expect(cookie.hostOnly, isTrue);
  });

  test('incomplete native scope metadata is rejected', () {
    expect(
      () => BrowserLoginCookie.fromNative(
        Cookie(name: 'SESSDATA', value: 'fixture'),
        windowsExpiryInSeconds: false,
      ),
      throwsFormatException,
    );
  });
}
