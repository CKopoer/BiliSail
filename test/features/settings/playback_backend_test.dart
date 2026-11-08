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
  testWidgets(
    'software decoding keeps backend and Android output controls visible',
    (tester) async {
      final repository = MemorySettingsRepository()
        ..value = AppSettings(
          playbackBackend: PlaybackBackendPreference.fvp,
          androidVideoOutput: AndroidVideoOutputPreference.directTexture,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
            home: Scaffold(
              body: SettingsScreen(category: SettingsCategory.playback),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('软件解码'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('软件解码'));
      await tester.pumpAndSettle();
      expect(find.text('播放后端'), findsOneWidget);
      expect(find.text('优先视频编码'), findsOneWidget);
      expect(find.text('优先音质'), findsOneWidget);
      expect(find.text('GPU 设备'), findsNothing);
      final direct = find.text('解码直出纹理（实验）');
      ChoiceChip directChip() => tester.widget<ChoiceChip>(
        find.ancestor(of: direct, matching: find.byType(ChoiceChip)),
      );
      expect(direct, findsOneWidget);
      expect(directChip().selected, isTrue);
      expect(directChip().onSelected, isNull);
      expect(find.textContaining('软件解码使用兼容渲染'), findsOneWidget);
      await tester.ensureVisible(find.text('media_kit（默认）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('media_kit（默认）'));
      await tester.pumpAndSettle();
      expect(
        repository.value.playbackBackend,
        PlaybackBackendPreference.mediaKit,
      );
      expect(repository.value.videoDecoding, VideoDecodingPreference.software);
      await tester.ensureVisible(find.text('硬件解码（优先）'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('硬件解码（优先）'));
      await tester.pumpAndSettle();
      expect(directChip().onSelected, isNotNull);
      expect(directChip().selected, isTrue);
      expect(
        repository.value.androidVideoOutput,
        AndroidVideoOutputPreference.directTexture,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  testWidgets(
    'backend switching preserves the saved Android output preference',
    (tester) async {
      final repository = MemorySettingsRepository()
        ..value = AppSettings(
          androidVideoOutput: AndroidVideoOutputPreference.directTexture,
        );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [settingsRepositoryProvider.overrideWithValue(repository)],
          child: const MaterialApp(
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
      ChoiceChip directChip() => tester.widget<ChoiceChip>(
        find.ancestor(of: direct, matching: find.byType(ChoiceChip)),
      );
      expect(directChip().selected, isTrue);
      expect(directChip().onSelected, isNotNull);
      for (final (label, backend) in [
        ('fvp（实验性）', PlaybackBackendPreference.fvp),
        ('media_kit（默认）', PlaybackBackendPreference.mediaKit),
      ]) {
        await tester.ensureVisible(find.text(label));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(repository.value.playbackBackend, backend);
        expect(directChip().onSelected, isNotNull);
        expect(directChip().selected, isTrue);
        expect(
          repository.value.androidVideoOutput,
          AndroidVideoOutputPreference.directTexture,
        );
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
  test(
    'removed backend falls back and saves without resetting other preferences',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(database);
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 44,
          'playbackBackend': 'fsplayer',
          'videoDecoding': 'software',
          'androidVideoOutput': 'directTexture',
          'defaultVolume': 37,
          'defaultPlaybackRate': 1.5,
          'autoPlay': false,
        }),
      );
      final settings = await repository.load();
      expect(settings.playbackBackend, PlaybackBackendPreference.mediaKit);
      expect(settings.videoDecoding, VideoDecodingPreference.software);
      expect(
        settings.androidVideoOutput,
        AndroidVideoOutputPreference.directTexture,
      );
      expect(settings.defaultVolume, 37);
      expect(settings.defaultPlaybackRate, 1.5);
      expect(settings.autoPlay, isFalse);
      await repository.save(settings.copyWith(theme: AppThemePreference.dark));
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      ) as Map<String, Object?>;
      expect(snapshot['playbackBackend'], 'mediaKit');
      final reloaded = await SqliteSettingsRepository(database).load();
      expect(reloaded.playbackBackend, PlaybackBackendPreference.mediaKit);
      expect(reloaded.videoDecoding, settings.videoDecoding);
      expect(reloaded.androidVideoOutput, settings.androidVideoOutput);
      expect(reloaded.defaultVolume, settings.defaultVolume);
      expect(reloaded.defaultPlaybackRate, settings.defaultPlaybackRate);
      expect(reloaded.autoPlay, settings.autoPlay);
      expect(reloaded.theme, AppThemePreference.dark);
    },
  );
  test('old GPU preference is ignored and removed on save without resetting settings', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final repository = SqliteSettingsRepository(database);
    await database.writeSetting(
      'preferences.v1',
      jsonEncode({
        'schemaVersion': 43,
        'fvpGpuDeviceId': 'dxgi:old-device',
        'playbackBackend': 'fvp',
        'videoDecoding': 'software',
        'androidVideoOutput': 'directTexture',
        'defaultVolume': 37,
      }),
    );
    final settings = await repository.load();
    expect(settings.playbackBackend, PlaybackBackendPreference.fvp);
    expect(settings.videoDecoding, VideoDecodingPreference.software);
    expect(
      settings.androidVideoOutput,
      AndroidVideoOutputPreference.directTexture,
    );
    expect(settings.defaultVolume, 37);
    await repository.save(settings.copyWith(theme: AppThemePreference.dark));
    final snapshot = jsonDecode(
      (await database.readSetting('preferences.v1'))!,
    ) as Map<String, Object?>;
    expect(snapshot.containsKey('fvpGpuDeviceId'), isFalse);
    expect(snapshot['schemaVersion'], greaterThanOrEqualTo(44));
    final reloaded = await repository.load();
    expect(reloaded.playbackBackend, settings.playbackBackend);
    expect(reloaded.videoDecoding, settings.videoDecoding);
    expect(reloaded.androidVideoOutput, settings.androidVideoOutput);
    expect(reloaded.defaultVolume, 37);
    expect(reloaded.theme, AppThemePreference.dark);
  });
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
    expect(find.text('media_kit（默认）'), findsOneWidget);
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
  }, variant: TargetPlatformVariant.all());
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
