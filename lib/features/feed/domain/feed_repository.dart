import '../../../domain/page_result.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class VideoCategory {
  const VideoCategory({required this.id, required this.name});

  final String id;
  final String name;
}

abstract interface class FeedRepository {
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  });

  /// A null category selects the recommendation feed.
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  });

  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  });
}

/// Rankings are an optional capability, separate from recommendation pagination.
abstract interface class RankingFeedRepository {
  /// Ranking region IDs are independent of the legacy newlist categories.
  Future<List<VideoCategory>> loadRankingCategories({
    required RequestCancellation cancellation,
  });

  Future<PageResult<VideoSummary>> loadRanking({
    required String categoryId,
    required RequestCancellation cancellation,
  });
}
