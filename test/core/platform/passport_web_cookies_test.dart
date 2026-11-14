import 'package:bilisail/core/platform/passport_web_cookies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import 'fake_passport_webview.dart';

void main() {
  late FakePassportPlatform platform;
  late WebViewSession session;
  final original = WebViewPlatform.instance;
  setUp(() async {
    platform = FakePassportPlatform();
    WebViewPlatform.instance = platform;
    session = (await WebViewSession.create(
      mode: WebViewSessionMode.isolatedIncognito,
    ))!;
  });
  tearDown(() async {
    await session.close();
    WebViewPlatform.instance = original ?? FakePassportPlatform();
  });
  test(
    'reads HttpOnly cookies from the session store with UTC expiry',
    () async {
      final expiry = DateTime.utc(2027);
      platform.cookies.value = [
        WebViewCookie(
          name: 'SESSDATA',
          value: 'fixture',
          domain: '.bilibili.com',
          isSecure: true,
          isHttpOnly: true,
          isSession: false,
          expires: expiry,
        ),
      ];
      final reader = PassportWebCookieReader();
      await reader.checkSupport(session);
      final cookie = (await reader.read(session)).single;
      expect(cookie.expires, expiry);
      expect(cookie.isHttpOnly, isTrue);
      expect(cookie.domain, '.bilibili.com');
    },
  );
  test('incomplete provider metadata is rejected before login', () async {
    platform.cookies.attributes = {};
    await expectLater(
      PassportWebCookieReader().checkSupport(session),
      throwsFormatException,
    );
  });
  for (final invalid in [
    const WebViewCookie(
      name: 'SESSDATA',
      value: 'fixture',
      domain: '.bilibili.com',
    ),
    const WebViewCookie(
      name: 'SESSDATA',
      value: 'fixture',
      domain: '.bilibili.com',
      isSecure: true,
      isHttpOnly: true,
      isSession: false,
    ),
  ]) {
    test('incomplete native cookie is rejected', () async {
      platform.cookies.value = [invalid];
      await expectLater(
        PassportWebCookieReader().read(session),
        throwsFormatException,
      );
    });
  }
  test('oversized native list is rejected', () async {
    platform.cookies.value = List.filled(
      129,
      const WebViewCookie(
        name: 'SESSDATA',
        value: 'fixture',
        domain: '.bilibili.com',
      ),
    );
    await expectLater(
      PassportWebCookieReader().read(session),
      throwsFormatException,
    );
  });
}
