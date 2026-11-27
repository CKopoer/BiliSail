import 'request_cancellation.dart';
import 'video.dart';

abstract interface class VideoCoverRepository {
  Duration get cover43Cooldown;

  Future<Map<VideoId, Uri>> loadCover43Urls(
    List<VideoId> ids, {
    required RequestCancellation cancellation,
  });
}
