import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late SqliteSettingsRepository repository;
  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    repository = SqliteSettingsRepository(database);
  });
  tearDown(() => database.close());
  test(
    'legacy snapshot retains preferences and supplies new defaults',
    () async {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'theme': 'dark',
          'danmakuEnabled': false,
          'danmakuOpacity': .7,
          'danmakuFontScale': 1.2,
        }),
      );
      final settings = await repository.load();
      expect(settings.theme, AppThemePreference.dark);
      expect(settings.font, AppFontPreference.harmonyOsSans);
      expect(settings.cacheImages, isTrue);
      expect(settings.danmakuEnabled, isFalse);
      expect(settings.danmakuOpacity, .7);
      expect(settings.danmakuFontScale, 1.2);
      expect(settings.danmakuTopMargin, 0);
      expect(settings.autoPlay, isTrue);
      expect(settings.resumePlayback, isTrue);
      expect(settings.showCollapsedProgress, isTrue);
      expect(settings.preferredQuality, 80);
      expect(settings.preferredVideoCodec, VideoCodecPreference.h264);
      expect(settings.videoDecoding, VideoDecodingPreference.automatic);
      expect(settings.sponsorBlockMode, SponsorBlockMode.disabled);
      expect(settings.sponsorBlockCategories, ['sponsor']);
      await repository.save(settings);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], 9);
      expect(snapshot['theme'], 'dark');
      expect(database.schemaVersion, 2);
    },
  );
  test('all configurable fields survive a repository reload', () async {
    final settings = AppSettings(
      shortcuts: const ShortcutSettings.defaults()
          .withKeys(ShortcutAction.playPause, ['Ctrl+K'])
          .withKeys(ShortcutAction.closeTab, ['Ctrl+W', 'MouseBack'])
          .withActionEnabled(ShortcutAction.fullscreen, false)
          .withPlayback(seekSeconds: 8, holdRate: 2),
      theme: AppThemePreference.light,
      font: AppFontPreference.system,
      cacheImages: false,
      autoPlay: false,
      resumePlayback: false,
      showCollapsedProgress: false,
      preferredQuality: 120,
      preferredVideoCodec: VideoCodecPreference.av1,
      videoDecoding: VideoDecodingPreference.software,
      defaultPlaybackRate: 1.5,
      defaultVolume: 35,
      danmakuEnabled: false,
      danmakuOpacity: .6,
      danmakuFontScale: 1.3,
      danmakuArea: .5,
      danmakuTopMargin: 48,
      danmakuSpeed: 1.5,
      danmakuFont: DanmakuFontPreference.harmonyOsSans,
      danmakuBold: true,
      danmakuStyle: DanmakuStylePreference.stroke,
      danmakuMergeDuplicates: true,
      danmakuBlockColored: true,
      danmakuMinimumWeight: 5,
      danmakuOffset: const Duration(milliseconds: -1500),
      danmakuMaxPerSecond: 5,
      danmakuMaxOnScreen: 12,
      danmakuScrollEnabled: false,
      danmakuTopEnabled: false,
      danmakuBottomEnabled: false,
      danmakuBlockedWords: ['测试', 'spoiler'],
      subtitlesEnabled: true,
      subtitleFontScale: 1.2,
      subtitleBackgroundOpacity: .7,
      subtitleBottomPadding: 50,
      sponsorBlockMode: SponsorBlockMode.automatic,
      sponsorBlockCategories: ['intro', 'sponsor'],
    );
    await repository.save(settings);
    final first = await database.readSetting('preferences.v1');
    final reloaded = await SqliteSettingsRepository(database).load();
    await repository.save(reloaded);
    expect(await database.readSetting('preferences.v1'), first);
    expect(reloaded.defaultVolume, 35);
    expect(reloaded.danmakuTopMargin, 48);
    expect(reloaded.danmakuFont, DanmakuFontPreference.harmonyOsSans);
    expect(reloaded.danmakuBold, isTrue);
    expect(reloaded.danmakuStyle, DanmakuStylePreference.stroke);
    expect(reloaded.danmakuMergeDuplicates, isTrue);
    expect(reloaded.danmakuBlockColored, isTrue);
    expect(reloaded.danmakuMinimumWeight, 5);
    expect(reloaded.danmakuOffset, const Duration(milliseconds: -1500));
    expect(reloaded.danmakuMaxOnScreen, 12);
    expect(reloaded.preferredVideoCodec, VideoCodecPreference.av1);
    expect(reloaded.videoDecoding, VideoDecodingPreference.software);
    expect(reloaded.font, AppFontPreference.system);
    expect(reloaded.cacheImages, isFalse);
    expect(reloaded.showCollapsedProgress, isFalse);
    expect(reloaded.shortcuts.actionFor('Ctrl+K'), ShortcutAction.playPause);
    expect(reloaded.shortcuts.actionFor('MouseBack'), ShortcutAction.closeTab);
    expect(reloaded.shortcuts.actionFor('F'), isNull);
    expect(reloaded.shortcuts.seekSeconds, 8);
    expect(reloaded.shortcuts.holdRate, 2);
    expect(reloaded.danmakuBlockedWords, ['测试', 'spoiler']);
    expect(
      () => reloaded.danmakuBlockedWords.add('mutate'),
      throwsUnsupportedError,
    );
    expect(
      () => reloaded.sponsorBlockCategories.clear(),
      throwsUnsupportedError,
    );
  });
  test('malformed field types and values normalize safely', () async {
    await database.writeSetting(
      'preferences.v1',
      jsonEncode({
        'theme': 'unknown',
        'font': 'unknown',
        'autoPlay': 'yes',
        'preferredQuality': 999,
        'preferredVideoCodec': 'future',
        'videoDecoding': 12,
        'defaultPlaybackRate': -2,
        'defaultVolume': 200,
        'danmakuArea': -1,
        'danmakuTopMargin': -4,
        'danmakuMaxPerSecond': 0,
        'danmakuFont': 'unknown',
        'danmakuBold': 'yes',
        'danmakuStyle': 'unknown',
        'danmakuMinimumWeight': 15,
        'danmakuOffsetMs': -90000,
        'danmakuBlockedWords': [' x ', 'x', '', 7],
        'subtitleBottomPadding': 999,
        'sponsorBlockMode': 'future',
        'sponsorBlockCategories': ['intro', 'unknown', 'intro'],
      }),
    );
    final s = await repository.load();
    expect(s.theme, AppThemePreference.system);
    expect(s.font, AppFontPreference.harmonyOsSans);
    expect(s.autoPlay, isTrue);
    expect(s.preferredQuality, 80);
    expect(s.preferredVideoCodec, VideoCodecPreference.h264);
    expect(s.videoDecoding, VideoDecodingPreference.automatic);
    expect(s.defaultPlaybackRate, .5);
    expect(s.defaultVolume, 100);
    expect(s.danmakuArea, .25);
    expect(s.danmakuTopMargin, 0);
    expect(s.danmakuMaxPerSecond, 0);
    expect(s.danmakuFont, DanmakuFontPreference.system);
    expect(s.danmakuBold, isFalse);
    expect(s.danmakuStyle, DanmakuStylePreference.shadow);
    expect(s.danmakuMinimumWeight, 10);
    expect(s.danmakuOffset, const Duration(seconds: -60));
    expect(s.danmakuBlockedWords, ['x']);
    expect(s.subtitleBottomPadding, 120);
    expect(s.sponsorBlockMode, SponsorBlockMode.disabled);
    expect(s.sponsorBlockCategories, ['intro']);
    final nonFinite = AppSettings(
      defaultVolume: double.nan,
      danmakuSpeed: double.infinity,
    ).normalized();
    expect(nonFinite.defaultVolume, 100);
    expect(nonFinite.danmakuSpeed, 1);
  });
  test('invalid snapshot is an error rather than an empty success', () async {
    await database.writeSetting('preferences.v1', '[]');
    await expectLater(repository.load(), throwsFormatException);
  });
  test(
    'version seven snapshot adds zero top margin without losing values',
    () async {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 7,
          'danmakuArea': .5,
          'defaultVolume': 35.5,
          'danmakuBlockedWords': ['spoiler'],
        }),
      );
      final settings = await repository.load();
      expect(settings.danmakuTopMargin, 0);
      await repository.save(settings.copyWith(danmakuTopMargin: 80));
      final reloaded = await repository.load();
      expect(reloaded.danmakuTopMargin, 80);
      expect(reloaded.danmakuArea, .5);
      expect(reloaded.defaultVolume, 35.5);
      expect(reloaded.danmakuBlockedWords, ['spoiler']);
      expect(database.schemaVersion, 2);
    },
  );
}
