import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class VideoComment {
  const VideoComment({
    required this.id,
    required this.author,
    required this.avatarUrl,
    required this.message,
    required this.likeCount,
    this.publishedAt,
  });
  final String id;
  final String author;
  final String avatarUrl;
  final String message;
  final int likeCount;
  final DateTime? publishedAt;
}

final class VideoCommentsPage {
  const VideoCommentsPage({required this.comments, required this.hasMore});
  final List<VideoComment> comments;
  final bool hasMore;
}

abstract interface class VideoExtrasRepository {
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  });
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  });
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  });
}
