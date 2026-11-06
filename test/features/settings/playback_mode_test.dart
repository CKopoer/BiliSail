import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mode defaults, copying and legacy construction are consistent', () {
    expect(AppSettings().playbackMode, PlaybackMode.pause);
    expect(const AppSettings.defaults().playbackMode, PlaybackMode.pause);
    expect(
      AppSettings(continuousPlayback: true).playbackMode,
      PlaybackMode.continuous,
    );
    expect(
      AppSettings(continuousRelatedPlayback: true).playbackMode,
      PlaybackMode.continuous,
    );
    for (final mode in PlaybackMode.values) {
      final settings = AppSettings(playbackMode: mode)
          .copyWith(theme: AppThemePreference.dark)
          .normalized();
      expect(settings.playbackMode, mode);
      expect(settings.continuousPlayback, mode == PlaybackMode.continuous);
      expect(
        const AppSettings.defaults().copyWith(playbackMode: mode).playbackMode,
        mode,
      );
    }
  });

  test(
    'legacy switches migrate independently and explicit modes take priority',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      for (final continuous in [false, true]) {
        for (final related in [false, true]) {
          await database.writeSetting(
            'preferences.v1',
            jsonEncode({
              'schemaVersion': 38,
              'continuousPlayback': continuous,
              'continuousRelatedPlayback': related,
              'autoPlay': false,
            }),
          );
          final migrated = await repository.load();
          expect(
            migrated.playbackMode,
            continuous || related
                ? PlaybackMode.continuous
                : PlaybackMode.pause,
          );
          expect(migrated.continuousPlayback, continuous);
          expect(migrated.continuousRelatedPlayback, related);
          expect(migrated.autoPlay, isFalse);
          await repository.save(migrated);
          expect((await repository.load()).playbackMode, migrated.playbackMode);
        }
      }
      for (final value in [null, 'unknown', 4, true, [], 'pause', 'listLoop']) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'playbackMode': value,
            'continuousPlayback': true,
            'continuousRelatedPlayback': true,
          }),
        );
        expect(
          (await repository.load()).playbackMode,
          value == 'listLoop' ? PlaybackMode.listLoop : PlaybackMode.pause,
        );
      }
    },
  );

  test(
    'every mode persists and reset restores pause without a table migration',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      final container = ProviderContainer(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);
      for (final mode in PlaybackMode.values) {
        await container
            .read(settingsControllerProvider.notifier)
            .setPlaybackMode(mode);
        expect((await repository.load()).playbackMode, mode);
        container.invalidate(settingsControllerProvider);
        expect(
          (await container.read(settingsControllerProvider.future))
              .playbackMode,
          mode,
        );
      }
      await container
          .read(settingsControllerProvider.notifier)
          .resetToDefaults();
      expect((await repository.load()).playbackMode, PlaybackMode.pause);
      expect(database.schemaVersion, 3);
    },
  );
}
