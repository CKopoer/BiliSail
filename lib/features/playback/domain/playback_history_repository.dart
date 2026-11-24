import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/recommendation_playback_context.dart';

final class PlaybackHistoryTarget {
  const PlaybackHistoryTarget(
    this.video,
    this.cid, {
    this.episodeId,
    this.seasonId,
    this.courseAid,
  });
  final VideoId video;
  final String cid;
  final String? episodeId, seasonId, courseAid;
  String get key =>
      '${video.value}:$cid:${episodeId ?? ''}${courseAid == null ? '' : ':course:$courseAid'}';
}

final class PlaybackHistoryRecord {
  const PlaybackHistoryRecord({
    required this.target,
    required this.position,
    required this.duration,
    required this.completed,
    this.recommendation,
  });
  final PlaybackHistoryTarget target;
  final Duration position, duration;
  final bool completed;
  final RecommendationPlaybackContext? recommendation;
}

abstract interface class PlaybackHistoryRepository {
  Future<Duration?> read(
    PlaybackHistoryTarget target, {
    required String scope,
    required RequestCancellation cancellation,
  });
  Future<void> report(
    PlaybackHistoryRecord record, {
    required String scope,
    required RequestCancellation cancellation,
  });
}
