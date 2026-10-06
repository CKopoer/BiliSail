import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import 'playback_repository.dart';

/// Resolves only the video representation needed by a muted card preview.
abstract interface class VideoPreviewRepository {
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  });
}
