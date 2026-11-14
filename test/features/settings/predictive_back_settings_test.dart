import 'dart:convert';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

void main() {
  test('legacy and invalid snapshots keep predictive Back enabled', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    expect((await repository.load()).predictiveBackEnabled, isTrue);
    for (final snapshot in [
      <String, Object?>{},
      {'predictiveBackEnabled': null},
      {'predictiveBackEnabled': 'false'},
      {'predictiveBackEnabled': 0},
    ]) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({'schemaVersion': 49, 'theme': 'dark', ...snapshot}),
      );
      final restored = await repository.load();
      expect(restored.predictiveBackEnabled, isTrue);
      expect(restored.theme, AppThemePreference.dark);
    }
    expect(database.schemaVersion, 3);
  });

  test('predictive Back persists both choices and resets to enabled', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    for (final enabled in [false, true, false]) {
      await container
          .read(settingsControllerProvider.notifier)
          .setPredictiveBackEnabled(enabled);
      final restored = await SqliteSettingsRepository(database).load();
      expect(restored.predictiveBackEnabled, enabled);
      expect(
        restored
            .copyWith(theme: AppThemePreference.dark)
            .normalized()
            .predictiveBackEnabled,
        enabled,
      );
      container.invalidate(settingsControllerProvider);
      expect(
        (await container.read(settingsControllerProvider.future))
            .predictiveBackEnabled,
        enabled,
      );
    }
    await container.read(settingsControllerProvider.notifier).resetToDefaults();
    expect((await repository.load()).predictiveBackEnabled, isTrue);
    expect(
      jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      )['schemaVersion'],
      50,
    );
  });

  for (final failSave in [false, true]) {
    testWidgets(
      'Android switch updates shell, reloads and handles save failure: $failSave',
      (tester) async {
        final repository = MemorySettingsRepository()..failWrites = failSave;
        final router = createBiliRouter(
          initialLocation: '/settings',
          playerBuilder: (_, _, _) => const SizedBox(),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(repository),
            ],
            child: MaterialApp.router(
              builder: AppNoticeHost.builder,
              routerConfig: router,
            ),
          ),
        );
        await tester.pumpAndSettle();
        final toggle = find.widgetWithText(SwitchListTile, '预测式返回动画');
        final shell = tester.state(find.byType(BiliAppShell));
        final container = ProviderScope.containerOf(tester.element(toggle));
        expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, failSave);
        expect(repository.value.predictiveBackEnabled, failSave);
        expect(
          tester
              .widget<BiliAppShell>(find.byType(BiliAppShell))
              .predictiveBackEnabled,
          failSave,
        );
        expect(tester.state(find.byType(BiliAppShell)), same(shell));
        container.invalidate(settingsControllerProvider);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, failSave);
        if (failSave) {
          expect(find.text('设置保存失败，请重试'), findsOneWidget);
        } else {
          await container
              .read(settingsControllerProvider.notifier)
              .resetToDefaults();
          await tester.pumpAndSettle();
          expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
          expect(
            tester
                .widget<BiliAppShell>(find.byType(BiliAppShell))
                .predictiveBackEnabled,
            isTrue,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
      variant: TargetPlatformVariant.only(TargetPlatform.android),
    );
  }

  testWidgets(
    'predictive Back switch is only shown on Android',
    (tester) async {
      final router = createBiliRouter(
        initialLocation: '/settings',
        playerBuilder: (_, _, _) => const SizedBox(),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(
              MemorySettingsRepository(),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('预测式返回动画'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
    variant: TargetPlatformVariant({
      TargetPlatform.iOS,
      TargetPlatform.windows,
      TargetPlatform.macOS,
      TargetPlatform.linux,
    }),
  );
}
