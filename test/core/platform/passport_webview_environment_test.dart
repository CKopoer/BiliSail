import 'dart:io';

import 'package:bilisail/core/platform/passport_webview_environment.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory support;
  setUp(() async {
    support = await Directory.systemTemp.createTemp(
      'passport-environment-test-',
    );
  });
  tearDown(() async => support.delete(recursive: true));

  test(
    'login attempts own distinct profiles under application support',
    () async {
      final settings = <WebViewEnvironmentSettings>[];
      final native = <_FakeEnvironment>[];
      Future<WebViewEnvironment> create(
        WebViewEnvironmentSettings value,
      ) async {
        settings.add(value);
        final environment = _FakeEnvironment();
        native.add(environment);
        return WebViewEnvironment.fromPlatform(platform: environment);
      }

      final first = await PassportWebViewEnvironment.create(
        support,
        createEnvironment: create,
      );
      final second = await PassportWebViewEnvironment.create(
        support,
        createEnvironment: create,
      );
      expect(
        first.userDataDirectory.path,
        isNot(second.userDataDirectory.path),
      );
      for (final profile in [first, second]) {
        expect(
          path.isWithin(support.path, profile.userDataDirectory.path),
          isTrue,
        );
        expect(await profile.userDataDirectory.exists(), isTrue);
      }
      expect(settings.first.userDataFolder, first.userDataDirectory.path);
      expect(settings.last.userDataFolder, second.userDataDirectory.path);
      await Future.wait([first.dispose(), first.dispose()]);
      expect(native.first.disposals, 1);
      expect(await first.userDataDirectory.exists(), isFalse);
      expect(await second.userDataDirectory.exists(), isTrue);
      await second.dispose();
    },
  );

  test(
    'failed initialization removes only its profile and propagates failure',
    () async {
      final root = Directory(path.join(support.path, 'passport-webview'));
      await root.create();
      final existing = await root.createTemp('existing-');
      final failure = PlatformException(code: 'environment_unavailable');
      await expectLater(
        PassportWebViewEnvironment.create(
          support,
          createEnvironment: (_) async => throw failure,
        ),
        throwsA(same(failure)),
      );
      expect(await root.list().map((entry) => entry.path).toList(), [
        existing.path,
      ]);
    },
  );

  test('native shutdown failure still releases the owned profile', () async {
    final failure = PlatformException(code: 'shutdown_failed');
    final environment = _FakeEnvironment(failure: failure);
    final profile = await PassportWebViewEnvironment.create(
      support,
      createEnvironment: (_) async =>
          WebViewEnvironment.fromPlatform(platform: environment),
    );
    await expectLater(profile.dispose(), throwsA(same(failure)));
    expect(await profile.userDataDirectory.exists(), isFalse);
  });
}

class _FakeEnvironment extends PlatformWebViewEnvironment {
  _FakeEnvironment({this.failure})
    : super.implementation(const PlatformWebViewEnvironmentCreationParams());

  final PlatformException? failure;
  int disposals = 0;

  @override
  Future<void> dispose() async {
    disposals++;
    if (failure case final error?) throw error;
  }
}
