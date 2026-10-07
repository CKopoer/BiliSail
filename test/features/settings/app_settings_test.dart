import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('player controls default to click and preserve the chosen mode', () {
    expect(AppSettings().playerControlsMode, PlayerControlsMode.click);
    expect(
      const AppSettings.defaults().playerControlsMode,
      PlayerControlsMode.click,
    );
    expect(
      const AppSettings.defaults()
          .copyWith(playerControlsMode: PlayerControlsMode.dynamic)
          .normalized()
          .copyWith(theme: AppThemePreference.dark)
          .playerControlsMode,
      PlayerControlsMode.dynamic,
    );
  });
  test('danmaku line spacing preserves the default and normalizes bounds', () {
    expect(const AppSettings.defaults().danmakuLineSpacing, 5);
    expect(AppSettings().danmakuLineSpacing, 5);
    expect(
      const AppSettings.defaults()
          .copyWith(danmakuLineSpacing: 80)
          .normalized()
          .copyWith(danmakuOpacity: .5)
          .danmakuLineSpacing,
      80,
    );
    for (final entry in <double, double>{
      -4: 0,
      0: 0,
      200: 100,
      double.nan: 5,
      double.infinity: 5,
    }.entries) {
      expect(
        AppSettings(danmakuLineSpacing: entry.key)
            .normalized()
            .danmakuLineSpacing,
        entry.value,
      );
    }
  });
  test(
    'concurrent playback requires multiple tabs and an enabled preference',
    () {
      expect(AppSettings().allowConcurrentPlayback, isTrue);
      expect(const AppSettings.defaults().allowConcurrentPlayback, isTrue);
      for (final mode in WorkspaceNavigationMode.values) {
        for (final allowed in [false, true]) {
          final settings = const AppSettings.defaults()
              .copyWith(navigationMode: mode, allowConcurrentPlayback: allowed)
              .normalized();
          expect(settings.allowConcurrentPlayback, allowed);
          expect(
            settings.concurrentPlaybackEnabled,
            mode == WorkspaceNavigationMode.multipleTabs && allowed,
          );
          expect(
            settings
                .copyWith(theme: AppThemePreference.dark)
                .allowConcurrentPlayback,
            allowed,
          );
        }
      }
    },
  );
  test(
    'danmaku style defaults preserve existing behavior and clamp limits',
    () {
      final defaults = const AppSettings.defaults();
      expect(defaults.danmakuFont, DanmakuFontPreference.system);
      expect(defaults.danmakuStyle, DanmakuStylePreference.shadow);
      expect(defaults.danmakuBold, isFalse);
      expect(defaults.danmakuMergeDuplicates, isFalse);
      expect(defaults.danmakuBlockColored, isFalse);
      expect(defaults.danmakuMinimumWeight, 0);
      expect(defaults.danmakuOffset, Duration.zero);
      final copy = defaults
          .copyWith(
            danmakuFont: DanmakuFontPreference.harmonyOsSans,
            danmakuStyle: DanmakuStylePreference.plain,
            danmakuBold: true,
            danmakuMergeDuplicates: true,
            danmakuBlockColored: true,
            danmakuMinimumWeight: 20,
            danmakuMaxPerSecond: 0,
            danmakuOffset: const Duration(seconds: -90),
          )
          .normalized();
      expect(copy.danmakuFont, DanmakuFontPreference.harmonyOsSans);
      expect(copy.danmakuStyle, DanmakuStylePreference.plain);
      expect(copy.danmakuBold, isTrue);
      expect(copy.danmakuMergeDuplicates, isTrue);
      expect(copy.danmakuBlockColored, isTrue);
      expect(copy.danmakuMinimumWeight, 10);
      expect(copy.danmakuMaxPerSecond, 0);
      expect(copy.danmakuOffset, const Duration(seconds: -60));
      expect(
        AppSettings(
          danmakuMaxPerSecond: -1,
          danmakuMinimumWeight: -1,
        ).normalized().danmakuMaxPerSecond,
        0,
      );
    },
  );
  test('danmaku top margin defaults to zero and normalizes its bounds', () {
    expect(const AppSettings.defaults().danmakuTopMargin, 0);
    expect(AppSettings().danmakuTopMargin, 0);
    expect(
      const AppSettings.defaults()
          .copyWith(danmakuTopMargin: 48)
          .normalized()
          .danmakuTopMargin,
      48,
    );
    for (final entry in <double, double>{
      -4: 0,
      300: 200,
      double.nan: 0,
      double.infinity: 0,
    }.entries) {
      expect(
        AppSettings(danmakuTopMargin: entry.key).normalized().danmakuTopMargin,
        entry.value,
      );
    }
  });
  test('image cache defaults on and survives copy normalization', () {
    expect(const AppSettings.defaults().cacheImages, isTrue);
    expect(AppSettings().cacheImages, isTrue);
    expect(
      const AppSettings.defaults()
          .copyWith(cacheImages: false)
          .normalized()
          .cacheImages,
      isFalse,
    );
  });
  test('legacy continuous default speeds normalize to supported steps', () {
    for (final entry in <double, double>{
      .25: .5,
      1.8: 2,
      2.7: 3,
      5: 3,
      double.nan: 1,
    }.entries) {
      expect(
        AppSettings(defaultPlaybackRate: entry.key)
            .normalized()
            .defaultPlaybackRate,
        entry.value,
      );
    }
    expect(
      AppSettings(defaultPlaybackRate: 3).normalized().defaultPlaybackRate,
      3,
    );
  });
  test(
    'constructor snapshots caller lists and exposes read-only collections',
    () {
      final words = ['original'];
      final categories = ['sponsor'];
      final settings = AppSettings(
        danmakuBlockedWords: words,
        sponsorBlockCategories: categories,
      );
      words[0] = 'changed';
      words.add('later');
      categories.clear();
      expect(settings.danmakuBlockedWords, ['original']);
      expect(settings.sponsorBlockCategories, ['sponsor']);
      expect(
        () => settings.danmakuBlockedWords.add('mutation'),
        throwsUnsupportedError,
      );
      expect(
        () => settings.sponsorBlockCategories.clear(),
        throwsUnsupportedError,
      );
    },
  );
  test(
    'copyWith snapshots replacement lists without changing the original',
    () {
      const original = AppSettings.defaults();
      final words = ['replacement'];
      final categories = ['intro'];
      final copy = original.copyWith(
        danmakuBlockedWords: words,
        sponsorBlockCategories: categories,
      );
      words.clear();
      categories.add('outro');
      expect(copy.danmakuBlockedWords, ['replacement']);
      expect(copy.sponsorBlockCategories, ['intro']);
      expect(original.danmakuBlockedWords, isEmpty);
      expect(original.sponsorBlockCategories, ['sponsor']);
      expect(
        () => original.sponsorBlockCategories.add('mutation'),
        throwsUnsupportedError,
      );
    },
  );
}
