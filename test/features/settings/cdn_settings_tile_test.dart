import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/settings/application/cdn_speed_test_controller.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/cdn_speed_test_repository.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/presentation/cdn_settings_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> open(
    WidgetTester tester,
    _Settings settings,
    _Speed speed, {
    double scale = 1,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          cdnSpeedTestRepositoryProvider.overrideWithValue(speed),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ref
                  .watch(settingsControllerProvider)
                  .when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const Text('加载失败'),
                    data: (settings) =>
                        CdnSettingsTile(preference: settings.mediaCdn),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(speed.signals, isEmpty);
    expect(find.byKey(const ValueKey('cdn-option-automatic')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('cdn-settings')));
    await tester.pumpAndSettle();
  }

  testWidgets('open automatically measures; stop/retry/close cancel each run', (
    tester,
  ) async {
    final settings = _Settings();
    final speed = _Speed()..pending = Completer<CdnSpeedSample>();
    await open(tester, settings, speed);
    expect(find.text('正在获取测速视频…'), findsOneWidget);
    await tester.tap(find.text('停止测速'));
    await tester.pumpAndSettle();
    expect(speed.signals.single.isCancelled, isTrue);
    expect(find.text('测速已停止'), findsOneWidget);
    await tester.tap(find.text('重新测速'));
    await tester.pumpAndSettle();
    expect(speed.signals.length, 2);
    final first = speed.pending;
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(speed.signals.last.isCancelled, isTrue);
    first?.complete(speed.sample);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(settings.settings.mediaCdn, MediaCdnPreference.automatic);
  });

  for (final failSave in [false, true]) {
    testWidgets('concrete node selection saves or rolls back: $failSave', (
      tester,
    ) async {
      final settings = _Settings()..failSave = failSave;
      final speed = _Speed();
      await open(tester, settings, speed);
      expect(find.text('测速完成'), findsOneWidget);
      expect(find.textContaining('2.00 MiB/s'), findsWidgets);
      final choice = find.byKey(const ValueKey('cdn-option-ali'));
      await tester.scrollUntilVisible(
        choice,
        250,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('cdn-options')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(choice);
      await tester.pumpAndSettle();
      expect(
        settings.settings.mediaCdn,
        failSave ? MediaCdnPreference.automatic : MediaCdnPreference.ali,
      );
      if (failSave) {
        expect(find.text('设置保存失败，请重试'), findsOneWidget);
        settings.failSave = false;
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(settings.settings.mediaCdn, MediaCdnPreference.ali);
      }
      expect(find.byType(CdnSettingsDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'sample failure retains selection and all nodes on narrow enlarged text',
    (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final settings = _Settings();
      final speed = _Speed()
        ..failure = const AppFailure(AppFailureKind.network, '无法获取测速视频，请重试');
      await open(tester, settings, speed, scale: 1.5);
      expect(find.text('无法获取测速视频，请重试'), findsOneWidget);
      final last = find.byKey(const ValueKey('cdn-option-hkBcache'));
      await tester.scrollUntilVisible(
        last,
        400,
        scrollable: find.descendant(
          of: find.byKey(const ValueKey('cdn-options')),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.tap(last);
      await tester.pumpAndSettle();
      expect(settings.settings.mediaCdn, MediaCdnPreference.hkBcache);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _Settings implements SettingsRepository {
  AppSettings settings = AppSettings();
  bool failSave = false;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async {
    if (failSave) throw const AppFailure(AppFailureKind.storage, 'failed');
    settings = value;
  }
}

final class _Speed implements CdnSpeedTestRepository {
  final sample = CdnSpeedSample([
    Uri.parse(
      'https://upos-sz-mirrorhw.bilivideo.com/upgcxcode/v.m4s?key=fixture',
    ),
  ], sessionEpoch: 0);
  final signals = <RequestCancellation>[];
  Completer<CdnSpeedSample>? pending;
  AppFailure? failure;
  @override
  Future<CdnSpeedSample> loadSample({
    required RequestCancellation cancellation,
  }) async {
    signals.add(cancellation);
    if (failure case final error?) throw error;
    return pending?.future ?? sample;
  }

  @override
  Future<CdnSpeedMeasurement> measure(
    Uri url, {
    required int sessionEpoch,
    required RequestCancellation cancellation,
  }) async => CdnSpeedMeasurement(
    bytes: 1024 * 1024,
    elapsed: const Duration(milliseconds: 500),
    host: url.host,
  );
}
