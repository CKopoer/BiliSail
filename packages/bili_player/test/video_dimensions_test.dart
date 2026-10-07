import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/video_dimensions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' show VideoParams;

void main() {
  test('display dimensions include pixel aspect correction', () {
    final dimensions = videoDisplayDimensions(
      const VideoParams(w: 720, h: 576, dw: 1024, dh: 576),
    );
    expect(dimensions?.width, 1024);
    expect(dimensions?.height, 576);
  });

  for (final rotation in [0, 90, 180, 270, -90, 450]) {
    test('display dimensions follow rotation $rotation', () {
      final dimensions = videoDisplayDimensions(
        VideoParams(w: 1920, h: 1080, rotate: rotation),
      );
      final rotated = rotation % 180 != 0;
      expect(dimensions?.width, rotated ? 1080 : 1920);
      expect(dimensions?.height, rotated ? 1920 : 1080);
    });
  }

  test(
    'missing rotation retains dimensions and invalid display size falls back',
    () {
      final dimensions = videoDisplayDimensions(
        const VideoParams(w: 1080, h: 1920, dw: 0, dh: 1920),
      );
      expect(dimensions?.width, 1080);
      expect(dimensions?.height, 1920);
    },
  );

  test('incomplete or invalid decoded dimensions remain unknown', () {
    for (final params in [
      const VideoParams(),
      const VideoParams(w: 1920),
      const VideoParams(w: 0, h: 1080),
      const VideoParams(w: 1920, h: -1),
    ]) {
      expect(videoDisplayDimensions(params), isNull);
    }
  });

  test('snapshot retains dimensions through state changes and clears for a new source', () {
    const snapshot = PlaybackSnapshot(
      phase: PlaybackPhase.playing,
      generation: 1,
      videoDimensions: VideoDimensions(1080, 1920),
    );
    final paused = snapshot.copyWith(phase: PlaybackPhase.paused);
    expect(paused.videoDimensions?.width, 1080);
    expect(paused.videoDimensions?.height, 1920);
    const opening = PlaybackSnapshot(
      phase: PlaybackPhase.opening,
      generation: 2,
    );
    expect(opening.videoDimensions, isNull);
  });
}
