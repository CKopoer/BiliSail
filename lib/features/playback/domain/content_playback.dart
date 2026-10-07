import '../../../domain/request_cancellation.dart';
import 'playback_repository.dart';

/// Identity used by the content resolver; it is never a synthetic video ID.
sealed class ContentPlaybackTarget {
  const ContentPlaybackTarget();
  String get key;

  @override
  bool operator ==(Object other) =>
      other is ContentPlaybackTarget && other.key == key;
  @override
  int get hashCode => key.hashCode;
}

final class PgcPlaybackTarget extends ContentPlaybackTarget {
  const PgcPlaybackTarget(this.episodeId, {this.cid, this.seasonId});
  final String episodeId;
  final String? seasonId;

  /// The selected episode's real content ID, used by the shared on-demand
  /// danmaku protocol even when no UGC detail/part is supplied.
  final String? cid;
  @override
  String get key => 'episode:$episodeId${cid == null ? '' : ':$cid'}';
}

final class LivePlaybackTarget extends ContentPlaybackTarget {
  const LivePlaybackTarget(this.roomId);
  final String roomId;
  @override
  String get key => 'live:$roomId';
}

/// An indexed, verified local task. It must never fall back to a network URL.
final class OfflinePlaybackTarget extends ContentPlaybackTarget {
  const OfflinePlaybackTarget(this.taskId, {this.episodeId});
  final String taskId;
  final String? episodeId;
  @override
  String get key => 'offline:$taskId';
}

abstract interface class ContentPlaybackRepository {
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  });
}
