import 'dart:async';

import 'package:bilisail/core/platform/passport_webview_environment.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all/webview_all.dart';

import 'fake_passport_webview.dart';

void main() {
  late FakePassportPlatform platform;
  final original = WebViewPlatform.instance;
  setUp(() {
    platform = FakePassportPlatform();
    WebViewPlatform.instance = platform;
  });
  tearDown(() => WebViewPlatform.instance = original ?? FakePassportPlatform());

  for (final target in [
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
    TargetPlatform.linux,
  ]) {
    test('$target requests an isolated session and closes once', () async {
      final environment = await PassportWebViewEnvironment.create(
        platform: target,
      );
      expect(environment.session.mode, WebViewSessionMode.isolatedIncognito);
      await Future.wait([environment.dispose(), environment.dispose()]);
      expect(platform.controller.closes, 1);
      expect(platform.data.clears, 0);
    });
  }
  test('unsupported isolation does not open an ordinary store', () async {
    platform.modes = {WebViewSessionMode.shared};
    await expectLater(
      PassportWebViewEnvironment.create(platform: TargetPlatform.linux),
      throwsUnsupportedError,
    );
    expect(platform.controllers, isEmpty);
  });
  test('Android cleans shared data before and after login and reserves through cleanup', () async {
    final environment = await PassportWebViewEnvironment.create(
      platform: TargetPlatform.android,
    );
    expect(platform.data.clears, 1);
    platform.data.pending = Completer<void>();
    final closing = environment.dispose();
    await expectLater(
      PassportWebViewEnvironment.create(platform: TargetPlatform.android),
      throwsStateError,
    );
    platform.data.pending!.complete();
    await closing;
    expect(platform.data.clears, 2);
    expect(platform.controller.closes, 1);
    final next = await PassportWebViewEnvironment.create(
      platform: TargetPlatform.android,
    );
    await next.dispose();
  });
  test(
    'failed Android cleanup closes the view and releases its reservation',
    () async {
      platform.data.fail = true;
      await expectLater(
        PassportWebViewEnvironment.create(platform: TargetPlatform.android),
        throwsStateError,
      );
      expect(platform.controller.closes, 1);
      platform.data.fail = false;
      final next = await PassportWebViewEnvironment.create(
        platform: TargetPlatform.android,
      );
      await next.dispose();
    },
  );
}
