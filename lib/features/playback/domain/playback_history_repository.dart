import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class PlaybackHistoryTarget {
  const PlaybackHistoryTarget(
    this.video,
    this.cid, {
    this.episodeId,
    this.seasonId,
  });
  final VideoId video;
  final String cid;
  final String? episodeId, seasonId;
  String get key => '${video.value}:$cid:${episodeId ?? ''}';
}

final class PlaybackHistoryRecord {
  const PlaybackHistoryRecord({
    required this.target,
    required this.position,
    required this.duration,
    required this.completed,
  });
  final PlaybackHistoryTarget target;
  final Duration position, duration;
  final bool completed;
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
