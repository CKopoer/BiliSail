import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../live/domain/live_room.dart';
import '../../pgc/domain/pgc_repository.dart';
import '../domain/search_repository.dart';
import '../domain/search_result.dart';

class ApiSearchRepository implements SearchRepository {
  ApiSearchRepository(BiliApiClient api, this.requests)
    : client = SearchClient(api);
  final SearchClient client;
  final ApiRequests requests;

  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final result = await client.search(
      query,
      type: _type(category),
      page: page,
      order: switch (order) {
        SearchOrder.relevance => 'totalrank',
        SearchOrder.views || SearchOrder.reads => 'click',
        SearchOrder.latest => 'pubdate',
        SearchOrder.danmaku => 'dm',
        SearchOrder.favorites => 'stow',
        SearchOrder.likes => 'attention',
        SearchOrder.comments => 'scores',
        SearchOrder.fansDescending || SearchOrder.fansAscending => 'fans',
        SearchOrder.levelDescending || SearchOrder.levelAscending => 'level',
      },
      orderSort:
          order == SearchOrder.fansAscending ||
              order == SearchOrder.levelAscending
          ? 1
          : 0,
      duration: duration.index,
      userType: userType.index,
      context: context,
    );
    return SearchPage(
      items: result.items.map(_entry).toList(),
      hasMore: result.hasMore,
      counts: result.counts.map((k, v) => MapEntry(_category(k), v)),
    );
  }, cancellation: cancellation);

  static ApiSearchType _type(SearchCategory category) => switch (category) {
    SearchCategory.all => ApiSearchType.all,
    SearchCategory.video => ApiSearchType.video,
    SearchCategory.bangumi => ApiSearchType.bangumi,
    SearchCategory.film => ApiSearchType.film,
    SearchCategory.live => ApiSearchType.live,
    SearchCategory.article => ApiSearchType.article,
    SearchCategory.user => ApiSearchType.user,
  };
  static SearchCategory _category(ApiSearchType type) => switch (type) {
    ApiSearchType.all => SearchCategory.all,
    ApiSearchType.video => SearchCategory.video,
    ApiSearchType.bangumi => SearchCategory.bangumi,
    ApiSearchType.film => SearchCategory.film,
    ApiSearchType.live => SearchCategory.live,
    ApiSearchType.article => SearchCategory.article,
    ApiSearchType.user => SearchCategory.user,
  };
  static VideoSummary _video(ApiVideoSummary v) => VideoSummary(
    id: VideoId(v.bvid),
    title: v.title,
    coverUrl: v.coverUrl?.toString() ?? '',
    author: v.ownerName,
    authorAvatarUrl: v.ownerAvatarUrl,
    authorId: UserId.tryParse(v.ownerMid),
    duration: v.duration,
    playCount: v.playCount,
    danmakuCount: v.danmakuCount,
    publishedAt: v.publishedAt,
  );
  static SearchEntry _entry(ApiSearchItem item) => switch (item) {
    ApiSearchVideo(:final video) => SearchVideoEntry(_video(video)),
    ApiSearchUser() => SearchUserEntry(
      id: UserId(item.mid),
      name: item.name,
      avatarUrl: item.avatarUrl,
      signature: item.signature,
      fans: item.fans,
      videoCount: item.videoCount,
      level: item.level,
      verifyType: item.verifyType,
      videos: item.videos.map(_video).toList(),
    ),
    ApiSearchMedia() => SearchMediaEntry(
      id: PgcSeasonId(item.seasonId),
      title: item.title,
      category: _category(item.type),
      coverUrl: item.coverUrl,
      description: item.description,
      styles: item.styles,
      areas: item.areas,
      updateText: item.updateText,
      badge: item.badge,
      score: item.score,
    ),
    ApiSearchLive() => SearchLiveEntry(
      id: RoomId(item.roomId),
      title: item.title,
      author: item.author,
      authorId: UserId.tryParse(item.authorMid),
      coverUrl: item.coverUrl,
      area: item.area,
      online: item.online,
      isLive: item.isLive,
    ),
    ApiSearchArticle() => SearchArticleEntry(
      id: ArticleId(item.id),
      title: item.title,
      author: item.author,
      authorId: UserId.tryParse(item.authorMid),
      coverUrl: item.coverUrl,
      description: item.description,
      section: item.category,
      views: item.views,
      likes: item.likes,
      replies: item.replies,
      publishedAt: item.publishedAt,
    ),
  };
}
