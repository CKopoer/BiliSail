import '../../../domain/user.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/page_result.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/feed_repository.dart';

class ApiFeedRepository implements FeedRepository, RankingFeedRepository {
  ApiFeedRepository(this.api, this.requests);
  final BiliApiClient api;
  final ApiRequests requests;

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [
    VideoCategory(id: '1', name: '动画'),
    VideoCategory(id: '3', name: '音乐'),
    VideoCategory(id: '4', name: '游戏'),
    VideoCategory(id: '5', name: '娱乐'),
    VideoCategory(id: '36', name: '知识'),
    VideoCategory(id: '188', name: '科技'),
    VideoCategory(id: '160', name: '生活'),
    VideoCategory(id: '211', name: '美食'),
    VideoCategory(id: '217', name: '动物圈'),
    VideoCategory(id: '119', name: '鬼畜'),
    VideoCategory(id: '155', name: '时尚'),
    VideoCategory(id: '181', name: '影视'),
  ];

  @override
  Future<List<VideoCategory>> loadRankingCategories({
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final regions = await RankingClient(api).getRegions(context: context);
    return List.unmodifiable([
      for (final region in regions)
        VideoCategory(id: region.id, name: region.name),
    ]);
  }, cancellation: cancellation);

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) async => _mapPage(
      categoryId == null
          ? await api.getRecommended(page: page, context: context)
          : await api.getRegionalVideos(
              categoryId: categoryId,
              page: page,
              context: context,
            ),
    ),
    cancellation: cancellation,
  );

  @override
  Future<PageResult<VideoSummary>> loadRanking({
    required String categoryId,
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) async => _mapPage(
      await api.getRanking(categoryId: categoryId, context: context),
    ),
    cancellation: cancellation,
  );

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final result = await api.getPopular(page: page, context: context);
    return _mapPage(result);
  }, cancellation: cancellation);

  PageResult<VideoSummary> _mapPage(ApiPage<ApiVideoSummary> result) =>
      PageResult(
        items: result.items
            .map(
              (item) => VideoSummary(
                id: VideoId(item.bvid),
                title: item.title,
                coverUrl: item.coverUrl?.toString() ?? '',
                author: item.ownerName,
                authorAvatarUrl: item.ownerAvatarUrl,
                authorId: UserId.tryParse(item.ownerMid),
                duration: item.duration,
                playCount: item.playCount,
                danmakuCount: item.danmakuCount,
                publishedAt: item.publishedAt,
                recommendationReason: item.recommendationReason,
              ),
            )
            .toList(growable: false),
        hasMore: result.hasMore,
      );
}
