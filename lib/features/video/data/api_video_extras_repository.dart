import '../../../domain/user.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/video_extras_repository.dart';

class ApiVideoExtrasRepository implements VideoExtrasRepository {
  ApiVideoExtrasRepository(this.api, this.requests);
  final BiliApiClient api;
  final ApiRequests requests;
  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) => api.getVideoTags(id.value, context: context),
    cancellation: cancellation,
  );
  @override
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final items = await api.getRelatedVideos(id.value, context: context);
    return items
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
          ),
        )
        .toList(growable: false);
  }, cancellation: cancellation);
  @override
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final detail = await api.getVideoDetail(id.value, context: context);
    final result = await api.getVideoComments(
      detail.aid,
      page: page,
      context: context,
    );
    return VideoCommentsPage(
      comments: result.items
          .map(
            (item) => VideoComment(
              id: item.id,
              author: item.author,
              avatarUrl: item.avatarUrl?.toString() ?? '',
              message: item.message,
              likeCount: item.likeCount,
              publishedAt: item.publishedAt,
            ),
          )
          .toList(growable: false),
      hasMore: result.hasMore,
    );
  }, cancellation: cancellation);
}
