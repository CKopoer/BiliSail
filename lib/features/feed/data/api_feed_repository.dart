import '../../../domain/user.dart';

import 'package:bili_api/bili_api.dart';

import '../../../shared/data/video_access_mapper.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/page_result.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/recommendation_source.dart';
import '../../../domain/app_failure.dart';
import 'app_recommendation_identity_store.dart';
import '../../video/domain/video_actions_repository.dart';
import '../domain/feed_repository.dart';
import '../domain/popular_feed.dart';

class ApiFeedRepository
    implements
        FeedRepository,
        PopularFeedRepository,
        RankingFeedRepository,
        AppRecommendationFeedRepository,
        RecommendationFeedbackRepository {
  ApiFeedRepository(this.api, this.requests, {this.appIdentity});
  final AppRecommendationIdentityStore? appIdentity;
  final BiliApiClient api;
  final ApiRequests requests;

  @override
  String get feedbackScope => 'session:${requests.sessionEpoch}';

  @override
  Future<void> rejectRecommendation(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) => _submitFeedback(feedback, undo: false, cancellation: cancellation);

  @override
  Future<void> undoRecommendationFeedback(
    RecommendationFeedback feedback, {
    required RequestCancellation cancellation,
  }) => _submitFeedback(feedback, undo: true, cancellation: cancellation);

  Future<void> _submitFeedback(
    RecommendationFeedback feedback, {
    required bool undo,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    try {
      if (feedback.source == RecommendationSource.app) {
        final store = appIdentity;
        if (store == null) {
          throw const ApiFailure(
            ApiFailureCategory.unavailable,
            'app_feedback',
          );
        }
        final identity = await store.requestIdentity();
        final token = identity.accessToken;
        if (identity.revision != feedback.identityRevision) {
          throw const ApiFailure(ApiFailureCategory.cancelled, 'app_feedback');
        }
        if (token == null) {
          throw const AppFailure(
            AppFailureKind.authentication,
            '请在账号菜单重新登录后再反馈 App 推荐',
          );
        }
        final reason = feedback.selectedReason;
        await AppRecommendationClient(api).feedback(
          aid: feedback.aid,
          buvid: identity.buvid,
          accessToken: token,
          undo: undo,
          reason: reason == null
              ? null
              : ApiAppFeedbackReason(
                  id: reason.id,
                  name: reason.name,
                  kind: reason.kind == RecommendationFeedbackReasonKind.dislike
                      ? ApiAppFeedbackKind.dislike
                      : ApiAppFeedbackKind.feedback,
                ),
          context: context,
        );
        if (identity.revision != store.revision) {
          throw const ApiFailure(ApiFailureCategory.cancelled, 'app_feedback');
        }
        return;
      }
      final client = FeedCardActionsClient(api);
      final value = ApiRecommendationFeedback(
        aid: feedback.aid,
        goto: feedback.goto,
        trackId: feedback.trackId,
        ownerMid: feedback.ownerMid,
      );
      if (undo) {
        await client.undoRecommendationFeedback(value, context: context);
      } else {
        await client.rejectRecommendation(value, context: context);
      }
    } on ApiFailure catch (failure) {
      if (context.cancellation?.isCancelled != true &&
          {
            ApiFailureCategory.network,
            ApiFailureCategory.timeout,
            ApiFailureCategory.http,
            ApiFailureCategory.protocol,
          }.contains(failure.category)) {
        throw const UnknownWriteOutcome();
      }
      rethrow;
    }
  }, cancellation: cancellation);

  @override
  Future<PageResult<VideoSummary>> loadAppRecommendations({
    required int page,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final store = appIdentity;
    if (store == null) {
      throw const ApiFailure(ApiFailureCategory.unavailable, 'app_recommended');
    }
    final identity = await store.requestIdentity();
    ApiPage<ApiAppRecommendation> result;
    try {
      result = await AppRecommendationClient(api).load(
        page: page,
        buvid: identity.buvid,
        accessToken: identity.accessToken,
        appAccountMid: identity.accountMid,
        context: context,
      );
    } on ApiFailure catch (failure) {
      if (failure.category == ApiFailureCategory.authentication &&
          identity.accessToken != null &&
          identity.revision == store.revision) {
        await store.invalidateAuthorization();
      }
      rethrow;
    }
    if (identity.revision != store.revision) {
      throw const ApiFailure(ApiFailureCategory.cancelled, 'app_recommended');
    }
    return PageResult(
      hasMore: result.hasMore,
      items: List.unmodifiable(
        result.items.map((item) {
          final video = item.video;
          return VideoSummary(
            id: VideoId(video.bvid),
            title: video.title,
            coverUrl: video.coverUrl?.toString() ?? '',
            author: video.ownerName,
            authorId: UserId.tryParse(video.ownerMid),
            duration: video.duration,
            previewCid: video.previewCid,
            playCount: video.playCount,
            danmakuCount: video.danmakuCount,
            likeCount: video.likeCount,
            categoryName: video.categoryName,
            isFollowed: video.isFollowed,
            recommendationReason: video.recommendationReason,
            recommendationFeedback: RecommendationFeedback.app(
              aid: item.aid,
              ownerMid: video.ownerMid ?? '0',
              identityRevision: identity.revision,
              reasons: item.reasons
                  .map(
                    (reason) => RecommendationFeedbackReason(
                      id: reason.id,
                      name: reason.name,
                      kind: reason.kind == ApiAppFeedbackKind.dislike
                          ? RecommendationFeedbackReasonKind.dislike
                          : RecommendationFeedbackReasonKind.feedback,
                    ),
                  )
                  .toList(),
            ),
          );
        }),
      ),
    );
  }, cancellation: cancellation);

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

  @override
  Future<List<PopularWeek>> loadPopularWeeks({
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final weeks = await api.getPopularWeeks(context: context);
    return List.unmodifiable([
      for (final week in weeks)
        PopularWeek(
          number: week.number,
          name: week.name,
          subject: week.subject,
        ),
    ]);
  }, cancellation: cancellation);

  @override
  Future<PageResult<VideoSummary>> loadPopularWeek({
    required int number,
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) async =>
        _mapPage(await api.getPopularWeek(number: number, context: context)),
    cancellation: cancellation,
  );

  @override
  Future<PageResult<VideoSummary>> loadPrecious({
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) async => _mapPage(await api.getPreciousVideos(context: context)),
    cancellation: cancellation,
  );

  PageResult<VideoSummary> _mapPage(ApiPage<ApiVideoSummary> result) =>
      PageResult(
        items: result.items
            .map(
              (item) => VideoSummary(
                id: VideoId(item.bvid),
                access: mapVideoAccess(item.access),
                previewCid: item.previewCid,
                title: item.title,
                coverUrl: item.coverUrl?.toString() ?? '',
                author: item.ownerName,
                authorAvatarUrl: item.ownerAvatarUrl,
                authorId: UserId.tryParse(item.ownerMid),
                duration: item.duration,
                playCount: item.playCount,
                likeCount: item.likeCount,
                categoryName: item.categoryName,
                isFollowed: item.isFollowed,
                danmakuCount: item.danmakuCount,
                publishedAt: item.publishedAt,
                recommendationReason: item.recommendationReason,
                recommendationFeedback: switch (item.recommendationFeedback) {
                  final feedback? => RecommendationFeedback(
                    aid: feedback.aid,
                    goto: feedback.goto,
                    trackId: feedback.trackId,
                    ownerMid: feedback.ownerMid,
                  ),
                  null => null,
                },
              ),
            )
            .toList(growable: false),
        hasMore: result.hasMore,
      );
}
