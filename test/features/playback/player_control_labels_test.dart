import 'package:bilisail/domain/video_quality.dart';
import 'package:bilisail/features/playback/presentation/player_control_labels.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'default quality and playback controls use the same protocol labels',
    () {
      const expected = {
        16: '360P',
        32: '480P',
        64: '720P',
        74: '720P60',
        80: '1080P',
        112: '1080P+',
        116: '1080P60',
        120: '4K',
        125: 'HDR',
        126: '杜比视界',
        127: '8K',
      };
      expect(videoQualityOptions, expected);
      for (final entry in expected.entries) {
        expect(playbackQualityLabel(entry.key), entry.value);
      }
      expect(playbackQualityLabel(null), '画质');
      expect(playbackQualityLabel(999), '999');
    },
  );
}
