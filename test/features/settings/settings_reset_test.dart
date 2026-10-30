import 'dart:convert';

import 'package:bilisail/app/platform_defaults.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/data/sqlite_settings_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.iOS,
  ]) {
    test('reset saves and reloads all defaults for $platform', () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = SqliteSettingsRepository(
        database,
        defaultNavigationMode: workspaceNavigationModeForPlatform(platform),
        defaultShortcuts: shortcutSettingsForPlatform(platform),
        defaultHighEnergyProgressEnabled: highEnergyProgressEnabledForPlatform(
          platform,
        ),
        defaultDanmakuArea: danmakuAreaForPlatform(platform),
        defaultDanmakuFontScale: danmakuFontScaleForPlatform(platform),
        defaultPlayerControlsMode: playerControlsModeForPlatform(platform),
        defaultVideoCardHoverPlayback: videoCardHoverPlaybackForPlatform(
          platform,
        ),
      );
      final defaults = await repository.load();
      await repository.save(defaults);
      final expected = jsonDecode(
        (await database.readSetting('preferences.v1'))!,
      );
      await database.writeSetting('downloads.v1', '{"concurrency":2}');
      await repository.save(
        defaults.copyWith(
          theme: AppThemePreference.dark,
          navigationMode: WorkspaceNavigationMode.multipleTabs,
          allowConcurrentPlayback: true,
          font: AppFontPreference.installed,
          systemFontFamily: 'Custom font',
          cacheImages: false,
          checkPrereleaseUpdates: true,
          wheelDampingRatio: .5,
          autoPlay: false,
          videoCardHoverPlayback: !defaults.videoCardHoverPlayback,
          continuousPlayback: true,
          continuousRelatedPlayback: true,
          preferredQuality: 120,
          defaultPlaybackRate: 2,
          defaultVolume: 20,
          rememberVolumeGlobally: true,
          danmakuEnabled: false,
          danmakuArea: .25,
          danmakuFontScale: 1.5,
          highEnergyProgressEnabled: !defaults.highEnergyProgressEnabled,
          playerControlsMode:
              defaults.playerControlsMode == PlayerControlsMode.click
              ? PlayerControlsMode.dynamic
              : PlayerControlsMode.click,
          danmakuBlockedWords: ['blocked'],
          subtitlesEnabled: true,
          sponsorBlockMode: SponsorBlockMode.disabled,
          sponsorBlockCategories: [],
          shortcuts: const ShortcutSettings.defaults()
              .withEnabled(false)
              .withKeys(ShortcutAction.closeTab, ['MouseForward']),
        ),
      );
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repository),
          settingsDefaultsProvider.overrideWithValue(repository.defaults),
        ],
      );
      addTearDown(container.dispose);
      await container.read(settingsControllerProvider.future);

      await container
          .read(settingsControllerProvider.notifier)
          .resetToDefaults();

      expect(
        jsonDecode((await database.readSetting('preferences.v1'))!),
        expected,
      );
      expect(await database.readSetting('downloads.v1'), '{"concurrency":2}');
      void expectPlatformDefaults(AppSettings settings) {
        expect(
          settings.shortcuts.keysFor(ShortcutAction.closeTab),
          defaults.shortcuts.keysFor(ShortcutAction.closeTab),
        );
        expect(
          settings.shortcuts.keysFor(ShortcutAction.nextTab),
          defaults.shortcuts.keysFor(ShortcutAction.nextTab),
        );
        expect(settings.theme, AppThemePreference.system);
        expect(settings.checkPrereleaseUpdates, isFalse);
        expect(settings.navigationMode, defaults.navigationMode);
        expect(settings.danmakuArea, defaults.danmakuArea);
        expect(settings.danmakuFontScale, defaults.danmakuFontScale);
        expect(settings.playerControlsMode, defaults.playerControlsMode);
        expect(
          settings.videoCardHoverPlayback,
          defaults.videoCardHoverPlayback,
        );
        expect(
          settings.highEnergyProgressEnabled,
          defaults.highEnergyProgressEnabled,
        );
        expect(settings.shortcuts.toJson(), defaults.shortcuts.toJson());
      }

      expectPlatformDefaults(
        container.read(settingsControllerProvider).requireValue,
      );
      container.invalidate(settingsControllerProvider);
      expectPlatformDefaults(
        await container.read(settingsControllerProvider.future),
      );
    });
  }
}
