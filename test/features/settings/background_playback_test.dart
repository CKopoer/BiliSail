import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('background playback defaults and copying preserve valid choices', () {
    expect(AppSettings().backgroundPlayback, isTrue);
    expect(const AppSettings.defaults().backgroundPlayback, isTrue);
    for (final enabled in [false, true]) {
      final settings = AppSettings(backgroundPlayback: enabled)
          .copyWith(theme: AppThemePreference.dark)
          .normalized();
      expect(settings.backgroundPlayback, enabled);
      expect(
        const AppSettings.defaults()
            .copyWith(backgroundPlayback: enabled)
            .backgroundPlayback,
        enabled,
      );
    }
  });

  test(
    'missing and malformed snapshots retain existing background behavior',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      expect((await repository.load()).backgroundPlayback, isTrue);
      for (final snapshot in <Map<String, Object?>>[
        {'schemaVersion': 44},
        for (final value in [null, 'false', 0, [], {}])
          {'backgroundPlayback': value},
        {'backgroundPlayback': false},
        {'backgroundPlayback': true},
      ]) {
        await database.writeSetting('preferences.v1', jsonEncode(snapshot));
        expect(
          (await repository.load()).backgroundPlayback,
          snapshot['backgroundPlayback'] != false,
        );
      }
    },
  );

  test('controller persists both choices, reloads and resets without a table migration', () async {
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
          .setBackgroundPlayback(enabled);
      expect((await repository.load()).backgroundPlayback, enabled);
      container.invalidate(settingsControllerProvider);
      expect(
        (await container.read(settingsControllerProvider.future))
            .backgroundPlayback,
        enabled,
      );
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      ) as Map<String, Object?>;
      expect(snapshot['backgroundPlayback'], enabled);
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(45));
    }
    await container.read(settingsControllerProvider.notifier).resetToDefaults();
    expect((await repository.load()).backgroundPlayback, isTrue);
    expect(database.schemaVersion, 3);
  });
}
