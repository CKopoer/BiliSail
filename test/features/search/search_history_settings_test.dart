import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('history recording defaults and malformed values migrate without changing other settings', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    expect((await repository.load()).recordSearchHistory, isTrue);
    for (final invalid in <Object?>[null, 0, 'false']) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({'recordSearchHistory': invalid, 'autoPlay': false}),
      );
      final loaded = await repository.load();
      expect(loaded.recordSearchHistory, isTrue);
      expect(loaded.autoPlay, isFalse);
    }
    await repository.save(
      AppSettings(recordSearchHistory: false, autoPlay: false),
    );
    final loaded = await SqliteSettingsRepository(database).load();
    expect(loaded.recordSearchHistory, isFalse);
    expect(loaded.autoPlay, isFalse);
    expect(
      loaded
          .copyWith(theme: AppThemePreference.dark)
          .normalized()
          .recordSearchHistory,
      isFalse,
    );
    expect(database.schemaVersion, 3);
  });

  test('recording preference persists, rolls back failed saves and restores defaults', () async {
    final repository = _Settings();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setRecordSearchHistory(false);
    expect(repository.saved.recordSearchHistory, isFalse);
    repository.fail = true;
    await expectLater(
      controller.setRecordSearchHistory(true),
      throwsStateError,
    );
    expect(
      container
          .read(settingsControllerProvider)
          .requireValue
          .recordSearchHistory,
      isFalse,
    );
    repository.fail = false;
    await controller.resetToDefaults();
    expect(repository.saved.recordSearchHistory, isTrue);
  });
}

final class _Settings implements SettingsRepository {
  AppSettings saved = const AppSettings.defaults();
  bool fail = false;
  @override
  Future<AppSettings> load() async => saved;
  @override
  Future<void> save(AppSettings settings) async {
    if (fail) throw StateError('disk');
    saved = settings;
  }
}
