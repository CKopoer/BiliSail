import '../../../domain/user.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/video_repository.dart';

class ApiVideoRepository implements VideoRepository {
  ApiVideoRepository(this.api, this.requests);
  final BiliApiClient api;
  final ApiRequests requests;

  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final detail = await api.getVideoDetail(id.value, context: context);
    final collection = detail.collection;
    return VideoDetail(
      aid: detail.aid,
      replyCount: detail.replyCount,
      collection: collection == null
          ? null
          : VideoCollection(
              id: collection.id,
              title: collection.title,
              playCount: collection.playCount,
              entries: collection.entries
                  .map(
                    (entry) => VideoCollectionEntry(
                      id: VideoId(entry.bvid),
                      title: entry.title,
                      duration: entry.duration,
                      parts: entry.pages
                          .map(
                            (p) => VideoPart(
                              cid: p.cid,
                              page: p.page,
                              title: p.title,
                              duration: p.duration,
                            ),
                          )
                          .toList(growable: false),
                    ),
                  )
                  .toList(growable: false),
            ),
      authorMid: detail.ownerMid,
      likeCount: detail.likeCount,
      coinCount: detail.coinCount,
      favoriteCount: detail.favoriteCount,
      summary: VideoSummary(
        id: VideoId(detail.bvid),
        previewCid: detail.pages.firstOrNull?.cid,
        title: detail.title,
        coverUrl: detail.coverUrl?.toString() ?? '',
        author: detail.ownerName,
        authorAvatarUrl: detail.ownerAvatarUrl,
        authorId: UserId.tryParse(detail.ownerMid),
        playCount: detail.playCount,
        danmakuCount: detail.danmakuCount,
        publishedAt: detail.publishedAt,
        duration: detail.pages.fold(
          Duration.zero,
          (sum, page) => sum + page.duration,
        ),
      ),
      description: detail.description,
      parts: detail.pages
          .map(
            (page) => VideoPart(
              cid: page.cid,
              page: page.page,
              title: page.title,
              duration: page.duration,
            ),
          )
          .toList(growable: false),
    );
  }, cancellation: cancellation);
}
