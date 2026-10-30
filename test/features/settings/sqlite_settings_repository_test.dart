import 'dart:convert';

import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
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
    'related autoplay defaults, invalid snapshots, save and reset',
    () async {
      expect(AppSettings().continuousRelatedPlayback, isFalse);
      expect(const AppSettings.defaults().continuousRelatedPlayback, isFalse);
      for (final value in <Object?>[null, 'true', 1, true, false]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 32,
            'continuousRelatedPlayback': value,
            'continuousPlayback': true,
            'autoPlay': false,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.continuousRelatedPlayback, value is bool ? value : false);
        expect(loaded.continuousPlayback, isTrue);
        expect(loaded.autoPlay, isFalse);
        await repository.save(loaded.copyWith(continuousRelatedPlayback: true));
        expect((await repository.load()).continuousRelatedPlayback, isTrue);
      }
      await repository.save(const AppSettings.defaults());
      expect((await repository.load()).continuousRelatedPlayback, isFalse);
      expect(database.schemaVersion, 3);
    },
  );
  test(
    'stream and audio preferences migrate, validate, reset and reload',
    () async {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 31,
          'preferredQuality': 64,
          'liveStreamPreference': {
            'protocol': 'bad',
            'format': 'flv',
            'codec': 'hevc',
          },
          'preferredAudioQuality': 'future',
        }),
      );
      final initial = await repository.load();
      expect(initial.liveStreamPreference.isAutomatic, isTrue);
      expect(initial.preferredAudioQuality, AudioQualityPreference.aac192);
      expect(initial.preferredQuality, 64);
      const preference = LiveStreamPreference(
        protocol: 'http_hls',
        format: 'ts',
        codec: 'hevc',
      );
      for (final audio in AudioQualityPreference.values) {
        await repository.save(
          initial.copyWith(
            liveStreamPreference: preference,
            preferredAudioQuality: audio,
          ),
        );
        final loaded = await repository.load();
        expect(loaded.liveStreamPreference, preference);
        expect(loaded.preferredAudioQuality, audio);
        final snapshot = jsonDecode(
          (await database.readSetting('preferences.v1'))!,
        );
        expect(snapshot['schemaVersion'], 33);
        expect(snapshot['liveStreamPreference'], preference.toJson());
      }
      await repository.save(const AppSettings.defaults());
      expect(
        (await repository.load()).liveStreamPreference.isAutomatic,
        isTrue,
      );
      expect(
        (await repository.load()).preferredAudioQuality,
        AudioQualityPreference.aac192,
      );
      expect(database.schemaVersion, 3);
    },
  );
  test('prerelease checks default off, preserve saved choices and migrate old snapshots', () async {
    expect(AppSettings().checkPrereleaseUpdates, isFalse);
    expect(const AppSettings.defaults().checkPrereleaseUpdates, isFalse);
    expect((await repository.load()).checkPrereleaseUpdates, isFalse);
    for (final snapshot in <Map<String, Object?>>[
      {'schemaVersion': 30, 'theme': 'dark'},
      for (final invalid in <Object?>[null, 'true', 1, <Object>[]])
        {
          'schemaVersion': 30,
          'theme': 'dark',
          'checkPrereleaseUpdates': invalid,
        },
    ]) {
      await database.writeSetting('preferences.v1', jsonEncode(snapshot));
      final loaded = await repository.load();
      expect(loaded.checkPrereleaseUpdates, isFalse);
      expect(loaded.theme, AppThemePreference.dark);
      for (final enabled in [true, false]) {
        await repository.save(loaded.copyWith(checkPrereleaseUpdates: enabled));
        final reloaded = await SqliteSettingsRepository(database).load();
        expect(reloaded.checkPrereleaseUpdates, enabled);
        expect(reloaded.theme, AppThemePreference.dark);
      }
    }
    expect(database.schemaVersion, 3);
  });
  for (final platform in [TargetPlatform.macOS, TargetPlatform.iOS]) {
    test(
      'Apple shortcut defaults persist, preserve custom bindings and reset on $platform',
      () async {
        final repo = SqliteSettingsRepository(
          database,
          defaultShortcuts: shortcutSettingsForPlatform(platform),
        );
        expect(
          (await repo.load()).shortcuts.actionFor('Meta+W'),
          ShortcutAction.closeTab,
        );
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'theme': 'dark',
            'shortcuts': {'holdRate': 2},
          }),
        );
        final legacy = await repo.load();
        expect(legacy.shortcuts.actionFor('Meta+T'), ShortcutAction.newTab);
        await repo.save(
          legacy.copyWith(
            shortcuts: legacy.shortcuts
                .withKeys(ShortcutAction.closeTab, ['Ctrl+W'])
                .withKeys(ShortcutAction.nextTab, ['Meta+K'])
                .withKeys(ShortcutAction.previousTab, [])
                .withActionEnabled(ShortcutAction.nextTab, false),
          ),
        );
        final restored = await repo.load();
        expect(restored.shortcuts.useAppleDefaults, isTrue);
        expect(restored.shortcuts.keysFor(ShortcutAction.closeTab), ['Ctrl+W']);
        expect(restored.shortcuts.keysFor(ShortcutAction.nextTab), ['Meta+K']);
        expect(restored.shortcuts.isEnabled(ShortcutAction.nextTab), isFalse);
        expect(restored.shortcuts.keysFor(ShortcutAction.previousTab), isEmpty);
        expect(restored.shortcuts.actionFor('Meta+R'), ShortcutAction.refresh);
        await repo.save(repo.defaults);
        expect(
          (await repo.load()).shortcuts.actionFor('Shift+Meta+BracketRight'),
          ShortcutAction.nextTab,
        );
        expect(database.schemaVersion, 3);
      },
    );
  }
  test(
    'global volume setting migrates and persists independently of defaults',
    () async {
      expect(AppSettings().rememberVolumeGlobally, isFalse);
      expect(const AppSettings.defaults().rememberVolumeGlobally, isFalse);
      expect((await repository.load()).rememberVolumeGlobally, isFalse);
      for (final invalid in [null, 'true', 1, <Object>[]]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 26,
            'defaultVolume': 35.5,
            'theme': 'dark',
            'rememberVolumeGlobally': invalid,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.rememberVolumeGlobally, isFalse);
        for (final enabled in [true, false]) {
          await repository.save(
            loaded.copyWith(rememberVolumeGlobally: enabled),
          );
          final reloaded = await SqliteSettingsRepository(database).load();
          expect(reloaded.rememberVolumeGlobally, enabled);
          expect(reloaded.defaultVolume, 35.5);
          expect(reloaded.theme, AppThemePreference.dark);
        }
      }
      expect(database.schemaVersion, 3);
    },
  );
  test('remembered volume rejects invalid stored values', () async {
    expect(await repository.loadRememberedVolume(), isNull);
    for (final invalid in [
      'null',
      'true',
      'NaN',
      'Infinity',
      '-1',
      '101',
      '{}',
    ]) {
      await database.writeSetting('playback.volume.v1', invalid);
      expect(await repository.loadRememberedVolume(), isNull);
    }
    for (final volume in [0.0, 35.5, 100.0]) {
      await repository.saveRememberedVolume(volume);
      expect(
        await SqliteSettingsRepository(database).loadRememberedVolume(),
        volume,
      );
    }
  });
  test('default comments migrate and persist both choices', () async {
    expect(AppSettings().defaultShowComments, isFalse);
    expect(const AppSettings.defaults().defaultShowComments, isFalse);
    expect((await repository.load()).defaultShowComments, isFalse);
    for (final snapshot in [
      {'schemaVersion': 25, 'theme': 'dark', 'autoPlay': false},
      for (final invalid in [null, 'true', 1, <Object>[]])
        {'theme': 'dark', 'autoPlay': false, 'defaultShowComments': invalid},
    ]) {
      await database.writeSetting('preferences.v1', jsonEncode(snapshot));
      final loaded = await repository.load();
      expect(loaded.defaultShowComments, isFalse);
      for (final enabled in [true, false]) {
        await repository.save(loaded.copyWith(defaultShowComments: enabled));
        final reloaded = await SqliteSettingsRepository(database).load();
        expect(reloaded.defaultShowComments, enabled);
        expect(reloaded.theme, AppThemePreference.dark);
        expect(reloaded.autoPlay, isFalse);
        expect(
          reloaded.copyWith(defaultVolume: 50).defaultShowComments,
          enabled,
        );
      }
    }
    expect(database.schemaVersion, 3);
  });
  test(
    'sidebar preferences migrate independently and persist all choices',
    () async {
      expect((await repository.load()).sidebarStyle, SidebarStyle.automatic);
      expect((await repository.load()).sidebarCollapsed, isFalse);
      for (final invalid in [null, 42, 'invalid', true]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 24,
            'sidebarStyle': invalid,
            'sidebarCollapsed': invalid,
            'theme': 'dark',
          }),
        );
        final loaded = await repository.load();
        expect(loaded.sidebarStyle, SidebarStyle.automatic);
        expect(loaded.sidebarCollapsed, invalid is bool ? invalid : false);
        expect(loaded.theme, AppThemePreference.dark);
      }
      for (final style in SidebarStyle.values) {
        for (final collapsed in [false, true]) {
          await repository.save(
            AppSettings(sidebarStyle: style, sidebarCollapsed: collapsed),
          );
          final loaded = await repository.load();
          expect(loaded.sidebarStyle, style);
          expect(loaded.sidebarCollapsed, collapsed);
        }
      }
    },
  );
  test(
    'fullscreen swipe controls default, migrate and persist both choices',
    () async {
      expect((await repository.load()).fullscreenSwipeControls, isTrue);
      for (final value in [null, 'invalid', 0, false, true]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 23,
            'theme': 'dark',
            'fullscreenSwipeControls': value,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.fullscreenSwipeControls, value is bool ? value : true);
        expect(loaded.theme, AppThemePreference.dark);
        await repository.save(loaded.copyWith(fullscreenSwipeControls: false));
        expect((await repository.load()).fullscreenSwipeControls, isFalse);
        await repository.save(loaded.copyWith(fullscreenSwipeControls: true));
        expect((await repository.load()).fullscreenSwipeControls, isTrue);
      }
    },
  );
  for (final platform in TargetPlatform.values) {
    test('hover playback migrates and persists choices on $platform', () async {
      final platformDefault = videoCardHoverPlaybackForPlatform(platform);
      repository = SqliteSettingsRepository(
        database,
        defaultVideoCardHoverPlayback: platformDefault,
      );
      expect((await repository.load()).videoCardHoverPlayback, platformDefault);
      for (final snapshot in [
        '{"schemaVersion":22,"theme":"dark","autoPlay":false}',
        for (final invalid in ['null', '"false"', '0', '[]'])
          '{"theme":"dark","autoPlay":false,"videoCardHoverPlayback":$invalid}',
      ]) {
        await database.writeSetting('preferences.v1', snapshot);
        final loaded = await repository.load();
        expect(loaded.videoCardHoverPlayback, platformDefault);
        expect(loaded.autoPlay, isFalse);
        expect(loaded.theme, AppThemePreference.dark);
      }
      for (final enabled in [false, true]) {
        final settings = (await repository.load()).copyWith(
          videoCardHoverPlayback: enabled,
        );
        await repository.save(settings);
        final reloaded = await SqliteSettingsRepository(
          database,
          defaultVideoCardHoverPlayback: platformDefault,
        ).load();
        expect(reloaded.videoCardHoverPlayback, enabled);
        expect(reloaded.autoPlay, isFalse);
        expect(reloaded.theme, AppThemePreference.dark);
      }
      expect(database.schemaVersion, 3);
    });
  }

  test(
    'sponsor defaults preserve saved modes and category selections',
    () async {
      final defaults = await repository.load();
      expect(defaults.sponsorBlockMode, SponsorBlockMode.manual);
      expect(
        defaults.sponsorBlockCategories,
        AppSettings.supportedSponsorCategories,
      );
      for (final mode in SponsorBlockMode.values) {
        for (final categories in <List<String>>[
          [],
          ['sponsor'],
          ['intro', 'preview'],
        ]) {
          await repository.save(
            AppSettings(
              sponsorBlockMode: mode,
              sponsorBlockCategories: categories,
            ),
          );
          final loaded = await repository.load();
          expect(loaded.sponsorBlockMode, mode);
          expect(loaded.sponsorBlockCategories, categories);
        }
      }
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'sponsorBlockMode': 'unknown',
          'sponsorBlockCategories': 7,
        }),
      );
      final fallback = await repository.load();
      expect(fallback.sponsorBlockMode, SponsorBlockMode.manual);
      expect(
        fallback.sponsorBlockCategories,
        AppSettings.supportedSponsorCategories,
      );
    },
  );
  test('wheel damping migrates and survives save and reload', () async {
    expect((await repository.load()).wheelDampingRatio, 1.3);
    for (final invalid in ['null', '"invalid"', 'true', '1e999']) {
      await database.writeSetting(
        'preferences.v1',
        '{"schemaVersion":20,"theme":"dark","wheelDampingRatio":$invalid}',
      );
      final loaded = await repository.load();
      expect(loaded.wheelDampingRatio, 1.3);
      expect(loaded.theme, AppThemePreference.dark);
    }
    await database.writeSetting(
      'preferences.v1',
      '{"schemaVersion":20,"theme":"dark","cacheImages":false}',
    );
    final legacy = await repository.load();
    expect(legacy.wheelDampingRatio, 1.3);
    for (final ratio in [.5, .75, 1.0, 1.3, 1.55, 2.0]) {
      await repository.save(legacy.copyWith(wheelDampingRatio: ratio));
      final loaded = await SqliteSettingsRepository(database).load();
      expect(loaded.wheelDampingRatio, ratio);
      expect(loaded.theme, AppThemePreference.dark);
      expect(loaded.cacheImages, isFalse);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
      expect(snapshot['wheelDampingRatio'], ratio);
    }
    expect(database.schemaVersion, 3);
  });

  for (final defaults in [
    (area: .5, fontScale: .6),
    (area: .75, fontScale: .8),
    (area: .75, fontScale: 1.0),
  ]) {
    group('danmaku defaults $defaults', () {
      setUp(() {
        repository = SqliteSettingsRepository(
          database,
          defaultDanmakuArea: defaults.area,
          defaultDanmakuFontScale: defaults.fontScale,
        );
      });
      test('empty settings use platform defaults', () async {
        final loaded = await repository.load();
        expect(loaded.danmakuArea, defaults.area);
        expect(loaded.danmakuFontScale, defaults.fontScale);
      });
      test('missing and invalid fields use platform defaults', () async {
        for (final snapshot in [
          '{"theme":"dark"}',
          for (final invalid in ['null', '"invalid"', 'true', '1e999'])
            '{"theme":"dark","danmakuArea":$invalid,'
                '"danmakuFontScale":$invalid}',
        ]) {
          await database.writeSetting('preferences.v1', snapshot);
          final loaded = await repository.load();
          expect(loaded.danmakuArea, defaults.area);
          expect(loaded.danmakuFontScale, defaults.fontScale);
          expect(loaded.theme, AppThemePreference.dark);
        }
      });
      test(
        'saved values survive reload regardless of platform defaults',
        () async {
          for (final chosen in [
            (area: .5, fontScale: .6),
            (area: .75, fontScale: 1.0),
            (area: 1.0, fontScale: .2),
          ]) {
            await repository.save(
              AppSettings(
                danmakuArea: chosen.area,
                danmakuFontScale: chosen.fontScale,
                theme: AppThemePreference.dark,
              ),
            );
            final loaded = await repository.load();
            expect(loaded.danmakuArea, chosen.area);
            expect(loaded.danmakuFontScale, chosen.fontScale);
            expect(loaded.theme, AppThemePreference.dark);
          }
        },
      );
    });
  }
  test(
    'high energy platform fallback migrates and explicit preferences win',
    () async {
      for (final fallback in [false, true]) {
        final scoped = SqliteSettingsRepository(
          database,
          defaultHighEnergyProgressEnabled: fallback,
        );
        for (final invalid in [null, 'true', 1]) {
          await database.writeSetting(
            'preferences.v1',
            jsonEncode({
              'schemaVersion': 19,
              'autoPlay': false,
              'highEnergyProgressEnabled': ?invalid,
            }),
          );
          final loaded = await scoped.load();
          expect(loaded.highEnergyProgressEnabled, fallback);
          expect(loaded.autoPlay, isFalse);
        }
        for (final chosen in [true, false]) {
          await scoped.save(
            (await scoped.load()).copyWith(highEnergyProgressEnabled: chosen),
          );
          expect((await scoped.load()).highEnergyProgressEnabled, chosen);
        }
      }
    },
  );
  test(
    'live quality migrates independently and survives save and reload',
    () async {
      expect((await repository.load()).preferredLiveQuality, 10000);
      for (final invalid in [null, '250', true, -1, 112, 99999, 250.5]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 18,
            'preferredQuality': 64,
            'preferredLiveQuality': ?invalid,
          }),
        );
        final loaded = await repository.load();
        expect(loaded.preferredLiveQuality, 10000);
        expect(loaded.preferredQuality, 64);
      }
      for (final quality in AppSettings.liveQualityOptions.keys) {
        await repository.save(
          AppSettings(preferredLiveQuality: quality, preferredQuality: 120),
        );
        final loaded = await repository.load();
        expect(loaded.preferredLiveQuality, quality);
        expect(loaded.preferredQuality, 120);
        final snapshot = jsonDecode(
          (await database.readSetting('preferences.v1')) ?? '{}',
        ) as Map<String, Object?>;
        expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
        expect(snapshot['preferredLiveQuality'], quality);
      }
      expect(database.schemaVersion, 3);
    },
  );
  test(
    'normalization migrates off and each mode survives save and reload',
    () async {
      expect(
        (await repository.load()).audioNormalization,
        AudioNormalizationMode.off,
      );
      for (final old in [null, 'future', 2, true]) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 17,
            'audioNormalization': old,
            'defaultVolume': 35.5,
          }),
        );
        final settings = await repository.load();
        expect(settings.audioNormalization, AudioNormalizationMode.off);
        expect(settings.defaultVolume, 35.5);
      }
      for (final mode in AudioNormalizationMode.values) {
        await repository.save(
          AppSettings(audioNormalization: mode)
              .copyWith(defaultVolume: 30)
              .normalized(),
        );
        final loaded = await repository.load();
        expect(loaded.audioNormalization, mode);
        expect(loaded.defaultVolume, 30);
      }
      expect(database.schemaVersion, 3);
    },
  );
  test(
    'continuous playback migrates off and survives save and reload',
    () async {
      expect((await repository.load()).continuousPlayback, isFalse);
      for (final old in [null, 1, 'true']) {
        await database.writeSetting(
          'preferences.v1',
          jsonEncode({
            'schemaVersion': 16,
            'continuousPlayback': old,
            'autoPlay': false,
          }),
        );
        final settings = await repository.load();
        expect(settings.continuousPlayback, isFalse);
        expect(settings.autoPlay, isFalse);
      }
      for (final enabled in [true, false]) {
        final settings = AppSettings(
          autoPlay: false,
          continuousPlayback: enabled,
        );
        await repository.save(
          settings.copyWith(defaultVolume: 50).normalized(),
        );
        final loaded = await repository.load();
        expect(loaded.continuousPlayback, enabled);
        expect(loaded.autoPlay, isFalse);
      }
    },
  );
  for (final defaultMode in PlayerControlsMode.values) {
    test(
      'player controls default to $defaultMode and saved modes survive reload',
      () async {
        repository = SqliteSettingsRepository(
          database,
          defaultPlayerControlsMode: defaultMode,
        );
        expect((await repository.load()).playerControlsMode, defaultMode);
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
          expect(loaded.playerControlsMode, defaultMode);
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
          expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
          expect(snapshot['playerControlsMode'], mode.name);
        }
        expect(database.schemaVersion, 3);
      },
    );
  }
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
    expect(
      (await repository.load()).navigationMode,
      WorkspaceNavigationMode.dualTabs,
    );
    for (final mode in WorkspaceNavigationMode.values) {
      final settings = await SqliteSettingsRepository(
        database,
        defaultNavigationMode: mode,
      ).load();
      expect(settings.navigationMode, mode);
    }
  });
  for (final fallback in WorkspaceNavigationMode.values) {
    test('saved singlePage survives with $fallback default', () async {
      await database.writeSetting(
        'preferences.v1',
        jsonEncode({
          'schemaVersion': 21,
          'navigationMode': 'singlePage',
          'theme': 'dark',
          'autoPlay': false,
          'defaultVolume': 37,
          'allowConcurrentPlayback': true,
        }),
      );
      final platformRepository = SqliteSettingsRepository(
        database,
        defaultNavigationMode: fallback,
      );
      final loaded = await platformRepository.load();
      expect(loaded.navigationMode, WorkspaceNavigationMode.singlePage);
      expect(loaded.theme, AppThemePreference.dark);
      expect(loaded.autoPlay, isFalse);
      expect(loaded.defaultVolume, 37);
      expect(loaded.allowConcurrentPlayback, isTrue);
      expect(loaded.concurrentPlaybackEnabled, isFalse);
      await platformRepository.save(loaded);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
      expect(snapshot['navigationMode'], 'singlePage');
      expect(
        (await platformRepository.load()).navigationMode,
        WorkspaceNavigationMode.singlePage,
      );
      expect(database.schemaVersion, 3);
    });
  }
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
          expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
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
      expect(settings.navigationMode, WorkspaceNavigationMode.dualTabs);
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
      expect(settings.sponsorBlockMode, SponsorBlockMode.manual);
      expect(
        settings.sponsorBlockCategories,
        AppSettings.supportedSponsorCategories,
      );
      await repository.save(settings);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
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
    expect(reloaded.navigationMode, WorkspaceNavigationMode.dualTabs);
    expect(reloaded.theme, AppThemePreference.dark);
  });
  test('concurrent playback migrates with compatible defaults and retains its preference', () async {
    expect((await repository.load()).allowConcurrentPlayback, isFalse);
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
      final allowed = oldValue is bool ? oldValue : false;
      expect(loaded.allowConcurrentPlayback, allowed);
      expect(loaded.concurrentPlaybackEnabled, isFalse);
      expect(loaded.theme, AppThemePreference.dark);
      await repository.save(loaded);
      final snapshot = jsonDecode(
        (await database.readSetting('preferences.v1')) ?? '{}',
      ) as Map<String, Object?>;
      expect(snapshot['schemaVersion'], greaterThanOrEqualTo(28));
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
      danmakuFontScale: .2,
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
      subtitleBottomPadding: 240,
      sponsorBlockMode: SponsorBlockMode.automatic,
      sponsorBlockCategories: ['intro', 'sponsor'],
    );
    await repository.save(settings);
    final first = await database.readSetting('preferences.v1');
    final reloaded = await SqliteSettingsRepository(database).load();
    await repository.save(reloaded);
    expect(await database.readSetting('preferences.v1'), first);
    expect(reloaded.defaultVolume, 35);
    expect(reloaded.subtitleBottomPadding, 240);
    expect(reloaded.danmakuFontScale, .2);
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
    expect(s.subtitleBottomPadding, 240);
    expect(s.sponsorBlockMode, SponsorBlockMode.manual);
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
