import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_category.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/memory_settings_repository.dart';

void main() {
  testWidgets('Android direct-output chips save and roll back failed writes', (
    tester,
  ) async {
    final repository = MemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          builder: AppNoticeHost.builder,
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.playback),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final direct = find.text('解码直出纹理（实验）');
    await tester.scrollUntilVisible(
      direct,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(direct);
    await tester.pumpAndSettle();
    expect(
      repository.value.androidVideoOutput,
      AndroidVideoOutputPreference.directTexture,
    );
    repository.failWrites = true;
    await tester.tap(find.text('兼容渲染（默认）'));
    await tester.pumpAndSettle();
    expect(
      repository.value.androidVideoOutput,
      AndroidVideoOutputPreference.directTexture,
    );
    expect(
      tester
          .widget<ChoiceChip>(
            find.ancestor(of: direct, matching: find.byType(ChoiceChip)),
          )
          .selected,
      true,
    );
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
  test('Android output persists, migrates invalid fields and resets', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    for (final value in [null, 'future', 123]) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 41,
          'androidVideoOutput': value,
          'defaultVolume': 37,
        }),
      );
      final settings = await repository.load();
      expect(
        settings.androidVideoOutput,
        AndroidVideoOutputPreference.renderedTexture,
      );
      expect(settings.defaultVolume, 37);
    }
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setAndroidVideoOutput(
      AndroidVideoOutputPreference.directTexture,
    );
    final saved = await repository.load();
    expect(
      saved.androidVideoOutput,
      AndroidVideoOutputPreference.directTexture,
    );
    expect(
      saved.copyWith(theme: AppThemePreference.dark).androidVideoOutput,
      saved.androidVideoOutput,
    );
    expect(saved.defaultVolume, 37);
    await controller.resetToDefaults();
    expect(
      (await repository.load()).androidVideoOutput,
      AndroidVideoOutputPreference.renderedTexture,
    );
  });
  testWidgets('backend chips persist selection and roll back a failed write', (
    tester,
  ) async {
    final repository = MemorySettingsRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
        child: const MaterialApp(
          builder: AppNoticeHost.builder,
          home: Scaffold(
            body: SettingsScreen(category: SettingsCategory.playback),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final fvp = find.text('fvp（实验性）');
    await tester.scrollUntilVisible(
      fvp,
      350,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(fvp);
    await tester.pumpAndSettle();
    expect(repository.value.playbackBackend, PlaybackBackendPreference.fvp);
    repository.failWrites = true;
    await tester.tap(find.text('media_kit（默认）'));
    await tester.pumpAndSettle();
    expect(repository.value.playbackBackend, PlaybackBackendPreference.fvp);
    final chip = tester.widget<ChoiceChip>(
      find.ancestor(of: fvp, matching: find.byType(ChoiceChip)),
    );
    expect(chip.selected, true);
  });
  test('backend defaults, migration, persistence and reset retain unrelated settings', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    expect(
      (await repository.load()).playbackBackend,
      PlaybackBackendPreference.mediaKit,
    );
    for (final value in [null, 'unknown', 1]) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 40,
          'playbackBackend': value,
          'defaultVolume': 37,
        }),
      );
      final settings = await repository.load();
      expect(settings.playbackBackend, PlaybackBackendPreference.mediaKit);
      expect(settings.defaultVolume, 37);
    }
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
    );
    addTearDown(container.dispose);
    await container.read(settingsControllerProvider.future);
    final controller = container.read(settingsControllerProvider.notifier);
    await controller.setPlaybackBackend(PlaybackBackendPreference.fvp);
    expect(
      (await SqliteSettingsRepository(database).load()).playbackBackend,
      PlaybackBackendPreference.fvp,
    );
    expect((await repository.load()).defaultVolume, 37);
    await controller.resetToDefaults();
    expect(
      (await repository.load()).playbackBackend,
      PlaybackBackendPreference.mediaKit,
    );
  });
}
