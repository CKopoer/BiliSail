import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/domain/playback_rates.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

void main() {
  test(
    'custom rates migrate, persist, repair malformed lists and reset',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      for (final invalid in [null, '1.75', 5, {}]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 39,
            'playbackRates': invalid,
            'defaultPlaybackRate': 1.5,
            'autoPlay': false,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.playbackRates, PlaybackRates.values);
        expect(loaded.defaultPlaybackRate, 1.5);
        expect(loaded.autoPlay, isFalse);
      }
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'playbackRates': [4, '1.75', null, -1, 1.75, 1.234, 6, 1.75],
          'defaultPlaybackRate': 1.75,
        }),
      );
      final repaired = await repository.load();
      expect(repaired.playbackRates, [0.5, 1, 1.75, 2, 4]);
      expect(repaired.defaultPlaybackRate, 1.75);
      await repository.save(repaired);
      final reloaded = await SqliteSettingsRepository(database).load();
      expect(reloaded.playbackRates, repaired.playbackRates);
      expect(reloaded.defaultPlaybackRate, 1.75);
      final snapshot =
          jsonDecode((await database.readSetting('preferences.v1'))!) as Map;
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(40));
      expect(database.schemaVersion, 3);
      await repository.save(const AppSettings.defaults());
      expect((await repository.load()).playbackRates, PlaybackRates.values);
    },
  );

  test('removing the default resets to 1x, failed saves roll back, reset restores presets', () async {
    final repository = MemorySettingsRepository()
      ..value = AppSettings(
        playbackRates: [1.75, 4],
        defaultPlaybackRate: 1.75,
      );
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    repository.failWrites = true;
    await expectLater(
      controller.setPlaybackRates([0.5, 1, 2, 4]),
      throwsStateError,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .requireValue
          .defaultPlaybackRate,
      1.75,
    );
    expect(
      container.read(settingsControllerProvider).requireValue.playbackRates,
      contains(1.75),
    );
    repository.failWrites = false;
    await controller.setPlaybackRates([0.5, 1, 2, 4]);
    expect(repository.value.defaultPlaybackRate, 1);
    container.invalidate(settingsControllerProvider);
    expect(
      (await container.read(settingsControllerProvider.future)).playbackRates,
      [0.5, 1, 2, 4],
    );
    await controller.resetToDefaults();
    expect(repository.value.playbackRates, PlaybackRates.values);
  });

  test('rate memory defaults preserve existing inheritance', () {
    expect(AppSettings().rememberPlaybackRate, isTrue);
    expect(const AppSettings.defaults().rememberPlaybackRate, isTrue);
    for (final enabled in [false, true]) {
      final settings = const AppSettings.defaults()
          .copyWith(rememberPlaybackRate: enabled, defaultPlaybackRate: 1.25)
          .copyWith(theme: AppThemePreference.dark)
          .normalized();
      expect(settings.rememberPlaybackRate, enabled);
      expect(settings.defaultPlaybackRate, 1.25);
    }
  });

  test(
    'rate memory migrates missing and malformed fields without losing defaults',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      expect((await repository.load()).rememberPlaybackRate, isTrue);
      for (final snapshot in <Map<String, Object?>>[
        {},
        for (final value in [null, 'false', 0, [], {}])
          {'rememberPlaybackRate': value},
      ]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 36,
            'defaultPlaybackRate': 1.5,
            'autoPlay': false,
            ...snapshot,
          }),
        );
        final settings = await repository.load();
        expect(settings.rememberPlaybackRate, isTrue);
        expect(settings.defaultPlaybackRate, 1.5);
        expect(settings.autoPlay, isFalse);
      }
      for (final enabled in [false, true]) {
        await repository.save(
          AppSettings(rememberPlaybackRate: enabled, defaultPlaybackRate: 1.25),
        );
        final reloaded = await SqliteSettingsRepository(database).load();
        expect(reloaded.rememberPlaybackRate, enabled);
        expect(reloaded.defaultPlaybackRate, 1.25);
        final snapshot = jsonDecode(
          (await database.readSetting('preferences.v1'))!,
        ) as Map<String, Object?>;
        expect(snapshot['rememberPlaybackRate'], enabled);
      }
    },
  );
}
