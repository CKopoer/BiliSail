import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dynamic tab defaults and copies preserve the selection', () {
    expect(AppSettings().defaultDynamicTab, DynamicPageTab.dynamic);
    expect(
      const AppSettings.defaults().defaultDynamicTab,
      DynamicPageTab.dynamic,
    );
    for (final tab in DynamicPageTab.values) {
      final settings = AppSettings(defaultDynamicTab: tab)
          .copyWith(theme: AppThemePreference.dark)
          .normalized();
      expect(settings.defaultDynamicTab, tab);
      expect(settings.theme, AppThemePreference.dark);
      expect(
        const AppSettings.defaults()
            .copyWith(defaultDynamicTab: tab)
            .defaultDynamicTab,
        tab,
      );
    }
  });

  test('missing and malformed dynamic tabs keep legacy settings', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    expect((await repository.load()).defaultDynamicTab, DynamicPageTab.dynamic);
    for (final snapshot in <Map<String, Object?>>[
      {},
      for (final value in [null, 'unknown', 'recommended', 1, true, []])
        {'defaultDynamicTab': value},
    ]) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 36,
          'theme': 'dark',
          'autoPlay': false,
          ...snapshot,
        }),
      );
      final loaded = await repository.load();
      expect(loaded.defaultDynamicTab, DynamicPageTab.dynamic);
      expect(loaded.theme, AppThemePreference.dark);
      expect(loaded.autoPlay, isFalse);
    }
  });

  test('dynamic tab selection survives reload and resets to dynamic', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    for (final tab in DynamicPageTab.values) {
      await container
          .read(settingsControllerProvider.notifier)
          .setDefaultDynamicTab(tab);
      final loaded = await SqliteSettingsRepository(database).load();
      expect(loaded.defaultDynamicTab, tab);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      ) as Map<String, Object?>;
      expect(snapshot['defaultDynamicTab'], tab.name);
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(38));
      expect(database.schemaVersion, 3);
      container.invalidate(settingsControllerProvider);
      expect(
        (await container.read(settingsControllerProvider.future))
            .defaultDynamicTab,
        tab,
      );
    }
    await container.read(settingsControllerProvider.notifier).resetToDefaults();
    expect((await repository.load()).defaultDynamicTab, DynamicPageTab.dynamic);
  });
}
