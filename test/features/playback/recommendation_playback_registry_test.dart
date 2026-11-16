import 'package:bilisail/domain/recommendation_playback_context.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/recommendation_playback_registry.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'opaque navigation references isolate videos, episodes and account epochs',
    () {
      final registry = RecommendationPlaybackRegistry();
      const video = VideoId('BV17x411w7KC');
      const context = RecommendationPlaybackContext(
        videoId: 'BV17x411w7KC',
        trackId: 'sensitive-server-track',
        sessionEpoch: 0,
      );
      final id = registry.capture(context);
      expect(id, isNot(contains(context.trackId)));
      expect(registry.resolve(id, video, 0), same(context));
      expect(registry.resolve(id, const VideoId('other'), 0), isNull);
      expect(registry.resolve(id, video, 0, episodeId: '7'), isNull);
      const episode = RecommendationPlaybackContext(
        episodeId: '7',
        trackId: 'episode-track',
        sessionEpoch: 0,
      );
      final episodeRoute = registry.capture(episode);
      expect(
        registry.resolve(episodeRoute, video, 0, episodeId: '7'),
        same(episode),
      );
      expect(registry.resolve(episodeRoute, video, 0, episodeId: '8'), isNull);
      expect(registry.resolve(episodeRoute, video, 0), isNull);
      expect(registry.resolve(id, video, 1), isNull);
      expect(registry.resolve(id, video, 0), isNull);
      expect(RecommendationPlaybackRegistry().resolve(id, video, 0), isNull);
    },
  );

  test('opening many recommendations keeps a fixed capacity', () {
    final registry = RecommendationPlaybackRegistry();
    const video = VideoId('BV17x411w7KC');
    final oldest = registry.capture(
      const RecommendationPlaybackContext(
        videoId: 'BV17x411w7KC',
        trackId: 'first',
        sessionEpoch: 0,
      ),
    );
    String? latest;
    for (var i = 0; i < RecommendationPlaybackRegistry.maximumEntries; i++) {
      latest = registry.capture(
        RecommendationPlaybackContext(
          videoId: video.value,
          trackId: '$i',
          sessionEpoch: 0,
        ),
      );
    }
    expect(registry.resolve(oldest, video, 0), isNull);
    expect(registry.resolve(latest, video, 0)?.trackId, '63');
  });
}
