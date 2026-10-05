import 'package:bili_lite/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
