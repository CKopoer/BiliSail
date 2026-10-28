import 'package:bilisail/core/platform/passport_web_cookies.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('bilisail/passport_web_cookies');
  final controller = InAppWebViewController.fromPlatform(
    platform: _Controller(),
  );
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
      '$platform reads the current private store with full metadata',
      () async {
        final reader = PassportWebCookieReader(platform: platform);
        final expiry = DateTime.utc(2027).millisecondsSinceEpoch;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          expect(call.method, 'getCookies');
          expect(call.arguments, {'marker': reader.viewMarker});
          return [_cookie(expiry: expiry)];
        });
        final cookies = await reader.read(controller);
        expect(cookies.single.value, 'fixture');
        expect(cookies.single.domain, '.bilibili.com');
        expect(cookies.single.path, '/');
        expect(cookies.single.isSecure, isTrue);
        expect(cookies.single.isHttpOnly, isTrue);
        expect(cookies.single.expiresDate, expiry);
        expect(cookies.single.isSessionOnly, isFalse);
      },
    );
  }

  test('attempt markers are distinct and stable within an attempt', () {
    final reader = PassportWebCookieReader(platform: TargetPlatform.iOS);
    expect(reader.viewMarker, matches(r'^BiliSailPassport/[0-9a-f]{32}$'));
    expect(reader.viewMarker, reader.viewMarker);
    expect(
      reader.viewMarker,
      isNot(PassportWebCookieReader(platform: TargetPlatform.iOS).viewMarker),
    );
  });

  test(
    'an unattached view remains pending and session expiry remains null',
    () async {
      final reader = PassportWebCookieReader(platform: TargetPlatform.iOS);
      var attached = false;
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) async => attached ? [_cookie()] : [],
      );
      expect(await reader.read(controller), isEmpty);
      attached = true;
      final cookie = (await reader.read(controller)).single;
      expect(cookie.isSessionOnly, isTrue);
      expect(cookie.expiresDate, isNull);
    },
  );

  test('native failure does not fall back to the default store', () async {
    final reader = PassportWebCookieReader(platform: TargetPlatform.macOS);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'ambiguous_view');
    });
    await expectLater(
      reader.read(controller),
      throwsA(isA<PlatformException>()),
    );
  });

  for (final invalid in <Object?>[
    null,
    [_cookie()..remove('domain')],
    [_cookie()..remove('path')],
    [_cookie()..remove('isSecure')],
    [_cookie()..['expiresDate'] = 'invalid'],
    List.generate(129, (_) => _cookie()),
  ]) {
    test(
      'incomplete or oversized native response is rejected: ${invalid.runtimeType}',
      () async {
        binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (_) async => invalid,
        );
        final reader = PassportWebCookieReader(platform: TargetPlatform.iOS);
        await expectLater(reader.read(controller), throwsFormatException);
      },
    );
  }
}

Map<String, Object?> _cookie({int? expiry}) => {
  'name': 'SESSDATA',
  'value': 'fixture',
  'domain': '.bilibili.com',
  'path': '/',
  'isSecure': true,
  'isHttpOnly': true,
  'isSessionOnly': expiry == null,
  'expiresDate': expiry,
};

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 'fixture'),
      );
}
