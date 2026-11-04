import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
