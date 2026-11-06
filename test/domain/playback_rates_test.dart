import 'package:bilisail/domain/playback_rates.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'custom rates are sorted, bounded, immutable and retain required values',
    () {
      final input = [
        4.0,
        1.75,
        0.25,
        1.75,
        double.nan,
        double.infinity,
        -1.0,
        6.0,
        1.234,
      ];
      final settings = AppSettings(playbackRates: input);
      input.clear();
      expect(settings.playbackRates, [0.25, 0.5, 1, 1.75, 2, 4]);
      expect(() => settings.playbackRates.add(3), throwsUnsupportedError);
      expect(
        settings.copyWith(autoPlay: false).playbackRates,
        settings.playbackRates,
      );
      final full = PlaybackRates.normalize([
        0.25,
        0.3,
        0.4,
        0.6,
        0.7,
        0.8,
        3,
        4,
        5,
      ]);
      expect(full, hasLength(9));
      expect(full, containsAll(PlaybackRates.requiredValues));
      expect(PlaybackRates.normalize([]), PlaybackRates.requiredValues);
    },
  );

  test('custom steps and legacy defaults use the configured options', () {
    final options = AppSettings(playbackRates: [1.1, 1.75, 4]).playbackRates;
    expect(PlaybackRates.faster(1, options), 1.1);
    expect(PlaybackRates.slower(2, options), 1.75);
    expect(PlaybackRates.faster(5, options), 4);
    expect(PlaybackRates.slower(0.25, options), 0.5);
    expect(PlaybackRates.faster(double.nan, options), 1.1);
    expect(PlaybackRates.nearest(1.74, options), 1.75);
    expect(
      AppSettings(
        playbackRates: options,
        defaultPlaybackRate: 1.75,
      ).normalized().defaultPlaybackRate,
      1.75,
    );
    expect(
      AppSettings(defaultPlaybackRate: 1.6).normalized().defaultPlaybackRate,
      1.5,
    );
    expect(const AppSettings.defaults().playbackRates, PlaybackRates.values);
  });
}
