import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'navigation bar defaults and copies preserve independent preferences',
    () {
      expect(AppSettings().navigationBarMode, NavigationBarMode.automatic);
      expect(
        const AppSettings.defaults().navigationBarMode,
        NavigationBarMode.automatic,
      );
      for (final mode in NavigationBarMode.values) {
        final settings = AppSettings(
          navigationBarMode: mode,
          sidebarStyle: SidebarStyle.expanded,
          sidebarCollapsed: true,
        ).copyWith(theme: AppThemePreference.dark).normalized();
        expect(settings.navigationBarMode, mode);
        expect(settings.sidebarStyle, SidebarStyle.expanded);
        expect(settings.sidebarCollapsed, isTrue);
      }
    },
  );

  test(
    'legacy and invalid navigation bar preferences fall back to automatic',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      expect(
        (await repository.load()).navigationBarMode,
        NavigationBarMode.automatic,
      );
      for (final value in [null, 'unknown', 1, true, <String>[]]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 27,
            'navigationBarMode': value,
            'sidebarStyle': 'compact',
            'sidebarCollapsed': true,
            'theme': 'dark',
          }),
        );
        final settings = await repository.load();
        expect(settings.navigationBarMode, NavigationBarMode.automatic);
        expect(settings.sidebarStyle, SidebarStyle.compact);
        expect(settings.sidebarCollapsed, isTrue);
        expect(settings.theme, AppThemePreference.dark);
      }
    },
  );

  test(
    'every navigation bar mode persists and reset restores automatic',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      for (final mode in NavigationBarMode.values) {
        await repository.save(AppSettings(navigationBarMode: mode));
        expect((await repository.load()).navigationBarMode, mode);
      }
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
      expect(database.schemaVersion, 4);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      await container
          .read(settingsControllerProvider.notifier)
          .resetToDefaults();
      expect(
        (await repository.load()).navigationBarMode,
        NavigationBarMode.automatic,
      );
    },
  );
}
