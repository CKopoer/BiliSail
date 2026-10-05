import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

abstract interface class VideoRepository {
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  });
}
