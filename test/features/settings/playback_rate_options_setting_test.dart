import 'package:bilisail/domain/playback_rates.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/shared/ui/playback_rate_options_setting.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

void main() {
  for (final width in [320.0, 960.0]) {
    testWidgets('custom rates add, validate and delete at width $width', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 640);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = MemorySettingsRepository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      expect(find.text('倍速选项（7/9）'), findsOneWidget);
      for (final rate in PlaybackRates.requiredValues) {
        expect(
          tester
              .widget<InputChip>(find.widgetWithText(InputChip, '${rate}x'))
              .onDeleted,
          isNull,
        );
      }
      await tester.tap(find.text('添加倍速'));
      await tester.pumpAndSettle();
      for (final invalid in [
        '',
        'NaN',
        'Infinity',
        '0',
        '5.01',
        '1.234',
        '1e0',
      ]) {
        await tester.enterText(find.byType(TextFormField), invalid);
        await tester.tap(find.text('添加'));
        await tester.pumpAndSettle();
        expect(find.text('请输入 0.25～5.0，最多两位小数'), findsOneWidget);
        expect(repository.value.playbackRates, PlaybackRates.values);
      }
      await tester.enterText(find.byType(TextFormField), '1.0');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(find.text('该倍速已存在'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '1.75');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(repository.value.playbackRates, [
        0.5,
        0.75,
        1,
        1.25,
        1.5,
        1.75,
        2,
        3,
      ]);
      expect(find.text('倍速选项（8/9）'), findsOneWidget);
      await tester.tap(find.text('添加倍速'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '4');
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();
      expect(find.text('倍速选项（9/9）'), findsOneWidget);
      expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '添加倍速'))
            .onPressed,
        isNull,
      );
      await tester.tap(find.byTooltip('删除 1.75x'));
      await tester.pumpAndSettle();
      expect(repository.value.playbackRates, isNot(contains(1.75)));
      expect(find.text('倍速选项（8/9）'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('failed add/delete restore saved rates and allow retry', (
    tester,
  ) async {
    final repository = MemorySettingsRepository()..failWrites = true;
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除 1.25x'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '1.25x'), findsOneWidget);
    expect(find.text('设置保存失败，请重试'), findsOneWidget);
    await tester.tap(find.text('添加倍速'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '1.75');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '1.75x'), findsNothing);
    expect(repository.value.playbackRates, PlaybackRates.values);
    repository.failWrites = false;
    await tester.tap(find.byTooltip('删除 1.25x'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InputChip, '1.25x'), findsNothing);
    expect(find.text('设置保存失败，请重试'), findsNothing);
  });
}

Widget _app(MemorySettingsRepository repository) => ProviderScope(
  overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Consumer(
          builder: (context, ref, _) {
            final settings = ref
                .watch(settingsControllerProvider)
                .asData
                ?.value;
            return settings == null
                ? const SizedBox.shrink()
                : PlaybackRateOptionsSetting(
                    rates: settings.playbackRates,
                    onChanged: ref
                        .read(settingsControllerProvider.notifier)
                        .setPlaybackRates,
                  );
          },
        ),
      ),
    ),
  ),
);
