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
    'player controls migrate to click and both modes survive reload',
    () async {
      expect(
        (await repository.load()).playerControlsMode,
        PlayerControlsMode.click,
      );
      for (final oldValue in [null, 'future', 42, true]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 15,
            'theme': 'dark',
            'autoPlay': false,
            'playerControlsMode': ?oldValue,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.playerControlsMode, PlayerControlsMode.click);
        expect(loaded.theme, AppThemePreference.dark);
        expect(loaded.autoPlay, isFalse);
      }
      for (final mode in PlayerControlsMode.values) {
        await repository.save(
          AppSettings(playerControlsMode: mode, autoPlay: false),
        );
        final loaded = await repository.load();
        expect(loaded.playerControlsMode, mode);
        expect(loaded.autoPlay, isFalse);
        final snapshot = jsonDecode(
          (await database.readSetting('preferences.v1')) ?? '{}',
        ) as Map<String, Object?>;
        expect(snapshot['schemaVersion'], 16);
        expect(snapshot['playerControlsMode'], mode.name);
      }
      expect(database.schemaVersion, 3);
    },
  );
  test(
    'CDN migrates to automatic and every preference survives reload',
    () async {
      for (final oldValue in [null, 'future', 7]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 13,
            'theme': 'dark',
            'mediaCdn': ?oldValue,
          }),
        );
        final settings = await repository.load();
        expect(settings.mediaCdn, MediaCdnPreference.automatic);
        expect(settings.theme, AppThemePreference.dark);
      }
      for (final preference in MediaCdnPreference.values) {
        await repository.save(
          AppSettings(mediaCdn: preference, theme: AppThemePreference.dark),
        );
        final reloaded = await repository.load();
        expect(reloaded.mediaCdn, preference);
        expect(reloaded.copyWith(cacheImages: false).mediaCdn, preference);
        expect(reloaded.theme, AppThemePreference.dark);
      }
      expect(database.schemaVersion, 3);
    },
  );
  test('empty settings use the injected platform default', () async {
    for (final mode in WorkspaceNavigationMode.values) {
      final settings = await SqliteSettingsRepository(
        database,
        defaultNavigationMode: mode,
      ).load();
      expect(settings.navigationMode, mode);
    }
  });
  for (final mode in WorkspaceNavigationMode.values) {
    test(
      'missing, automatic and invalid navigation values migrate to $mode',
      () async {
        final platformRepository = SqliteSettingsRepository(
          database,
          defaultNavigationMode: mode,
        );
        for (final oldMode in [null, 'automatic', 'unknown', 42]) {
          await database.writeSetting(
            'preferences.v1',
            jsonEncode({
              'schemaVersion': 11,
              'navigationMode': ?oldMode,
              'theme': 'dark',
            }),
          );
          final loaded = await platformRepository.load();
          expect(loaded.navigationMode, mode);
          expect(loaded.theme, AppThemePreference.dark);
          await platformRepository.save(loaded);
          final snapshot = jsonDecode(
            (await database.readSetting('preferences.v1')) ?? '{}',
          ) as Map<String, Object?>;
          expect(snapshot['schemaVersion'], 16);
          expect(snapshot['navigationMode'], mode.name);
        }
        for (final selected in WorkspaceNavigationMode.values) {
          await platformRepository.save(AppSettings(navigationMode: selected));
          final loaded = await SqliteSettingsRepository(
            database,
            defaultNavigationMode: mode,
          ).load();
          expect(loaded.navigationMode, selected);
        }
      },
    );
  }
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
      expect(settings.navigationMode, WorkspaceNavigationMode.multipleTabs);
      expect(settings.font, AppFontPreference.harmonyOsSans);
      expect(settings.cacheImages, isTrue);
      expect(settings.danmakuEnabled, isFalse);
      expect(settings.danmakuOpacity, .7);
      expect(settings.danmakuFontScale, 1.2);
      expect(settings.danmakuTopMargin, 0);
      expect(settings.danmakuLineSpacing, 5);
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
      expect(snapshot['schemaVersion'], 16);
      expect(snapshot['theme'], 'dark');
      expect(database.schemaVersion, 3);
    },
  );
  test('navigation modes survive reload and unknown values use the injected default', () async {
    for (final mode in WorkspaceNavigationMode.values) {
      await repository.save(
        AppSettings(navigationMode: mode, theme: AppThemePreference.dark),
      );
      final reloaded = await repository.load();
      expect(reloaded.navigationMode, mode);
      expect(reloaded.copyWith(cacheImages: false).navigationMode, mode);
    }
    await database.writeSetting(
      'preferences.v1',
      jsonEncode({'navigationMode': 'unknown', 'theme': 'dark'}),
    );
    final reloaded = await repository.load();
    expect(reloaded.navigationMode, WorkspaceNavigationMode.multipleTabs);
    expect(reloaded.theme, AppThemePreference.dark);
  });
  test('concurrent playback migrates with compatible defaults and retains its preference', () async {
    for (final oldValue in [null, 'false', 0, false, true]) {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 12,
          'navigationMode': 'singlePage',
          'theme': 'dark',
          'allowConcurrentPlayback': ?oldValue,
        }),
      );
      final loaded = await repository.load();
      final allowed = oldValue is bool ? oldValue : true;
      expect(loaded.allowConcurrentPlayback, allowed);
      expect(loaded.concurrentPlaybackEnabled, isFalse);
      expect(loaded.theme, AppThemePreference.dark);
      await repository.save(loaded);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], 16);
      expect(snapshot['allowConcurrentPlayback'], allowed);
      expect(snapshot['navigationMode'], 'singlePage');
      final reloaded = await repository.load();
      expect(reloaded.allowConcurrentPlayback, allowed);
      expect(
        reloaded
            .copyWith(navigationMode: WorkspaceNavigationMode.multipleTabs)
            .concurrentPlaybackEnabled,
        allowed,
      );
      expect(database.schemaVersion, 3);
    }
  });
  test(
    'bundled and installed font choices survive reload independently',
    () async {
      for (final bundled in [true, false]) {
        await repository.save(
          AppSettings(
            font: bundled
                ? AppFontPreference.harmonyOsSans
                : AppFontPreference.installed,
            systemFontFamily: 'Microsoft YaHei',
            danmakuFont: bundled
                ? DanmakuFontPreference.harmonyOsSans
                : DanmakuFontPreference.installed,
            danmakuSystemFontFamily: 'Segoe UI',
          ),
        );
        final loaded = await repository.load();
        expect(
          loaded.fontFamily,
          bundled ? 'HarmonyOS Sans' : 'Microsoft YaHei',
        );
        expect(
          loaded.danmakuFontFamily,
          bundled ? 'HarmonyOS Sans' : 'Segoe UI',
        );
        expect(
          loaded.copyWith(font: AppFontPreference.system).fontFamily,
          isNull,
        );
      }
    },
  );
  test(
    'removed bundled font falls back without losing other preferences',
    () async {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 16,
          'font': 'alibabaPuHuiTi',
          'danmakuFont': 'alibabaPuHuiTi',
          'systemFontFamily': 'Microsoft YaHei',
          'danmakuSystemFontFamily': 'Segoe UI',
          'theme': 'dark',
          'autoPlay': false,
          'defaultVolume': 35,
        }),
      );
      final loaded = await repository.load();
      expect(loaded.font, AppFontPreference.harmonyOsSans);
      expect(loaded.fontFamily, 'HarmonyOS Sans');
      expect(loaded.danmakuFont, DanmakuFontPreference.system);
      expect(loaded.danmakuFontFamily, isNull);
      expect(loaded.systemFontFamily, 'Microsoft YaHei');
      expect(loaded.danmakuSystemFontFamily, 'Segoe UI');
      expect(loaded.theme, AppThemePreference.dark);
      expect(loaded.autoPlay, isFalse);
      expect(loaded.defaultVolume, 35);
      await repository.save(loaded);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['font'], 'harmonyOsSans');
      expect(snapshot['danmakuFont'], 'system');
      final reloaded = await repository.load();
      expect(reloaded.font, loaded.font);
      expect(reloaded.danmakuFont, loaded.danmakuFont);
      expect(reloaded.theme, loaded.theme);
      expect(reloaded.autoPlay, loaded.autoPlay);
      expect(database.schemaVersion, 3);
    },
  );
  test('invalid installed family fields fall back without losing other preferences', () async {
    await database.writeSetting(
      'preferences.v1',
      jsonEncode({
        'schemaVersion': 9,
        'font': 'installed',
        'systemFontFamily': 123,
        'danmakuFont': 'installed',
        'danmakuSystemFontFamily': 'bad\u0000name',
        'theme': 'dark',
      }),
    );
    final loaded = await repository.load();
    expect(loaded.fontFamily, isNull);
    expect(loaded.danmakuFontFamily, isNull);
    expect(loaded.theme, AppThemePreference.dark);
  });
  test('all configurable fields survive a repository reload', () async {
    final settings = AppSettings(
      shortcuts: const ShortcutSettings.defaults()
          .withKeys(ShortcutAction.playPause, ['Ctrl+K'])
          .withKeys(ShortcutAction.closeTab, ['Ctrl+W', 'MouseBack'])
          .withActionEnabled(ShortcutAction.fullscreen, false)
          .withPlayback(seekSeconds: 8, holdRate: 2),
      theme: AppThemePreference.light,
      allowConcurrentPlayback: false,
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
      danmakuLineSpacing: 80,
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
    expect(reloaded.allowConcurrentPlayback, isFalse);
    expect(reloaded.danmakuTopMargin, 48);
    expect(reloaded.danmakuLineSpacing, 80);
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
        'danmakuLineSpacing': 'wide',
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
    expect(s.danmakuLineSpacing, 5);
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
    'version fourteen adds default line spacing and saves changes',
    () async {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 14,
          'danmakuLineSpacing': null,
          'danmakuArea': .5,
          'danmakuTopMargin': 40,
          'danmakuBlockedWords': ['spoiler'],
        }),
      );
      final settings = await repository.load();
      expect(settings.danmakuLineSpacing, 5);
      await repository.save(settings.copyWith(danmakuLineSpacing: 80));
      final reloaded = await SqliteSettingsRepository(database).load();
      expect(reloaded.danmakuLineSpacing, 80);
      expect(reloaded.danmakuTopMargin, 40);
      expect(reloaded.danmakuArea, .5);
      expect(reloaded.danmakuBlockedWords, ['spoiler']);
      await repository.save(reloaded.copyWith(danmakuLineSpacing: 0));
      expect((await repository.load()).danmakuLineSpacing, 0);
      await repository.save(reloaded.copyWith(danmakuLineSpacing: 5));
      expect((await repository.load()).danmakuLineSpacing, 5);
      expect(database.schemaVersion, 3);
    },
  );
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
      expect(database.schemaVersion, 3);
    },
  );
}
