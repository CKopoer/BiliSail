import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../live/domain/live_room.dart';
import '../../pgc/domain/pgc_repository.dart';

enum SearchCategory {
  all('综合'),
  video('视频'),
  bangumi('番剧'),
  film('影视'),
  live('直播'),
  article('专栏'),
  user('用户');

  const SearchCategory(this.label);
  final String label;

  List<SearchOrder> get orders => switch (this) {
    all || video => const [
      SearchOrder.relevance,
      SearchOrder.views,
      SearchOrder.latest,
      SearchOrder.danmaku,
      SearchOrder.favorites,
    ],
    article => const [
      SearchOrder.relevance,
      SearchOrder.reads,
      SearchOrder.latest,
      SearchOrder.likes,
      SearchOrder.comments,
    ],
    user => const [
      SearchOrder.relevance,
      SearchOrder.fansDescending,
      SearchOrder.fansAscending,
      SearchOrder.levelDescending,
      SearchOrder.levelAscending,
    ],
    _ => const [SearchOrder.relevance],
  };
  bool get hasDurationFilter => this == all || this == video;
}

enum SearchOrder {
  relevance('综合排序'),
  views('最多点击'),
  latest('最新发布'),
  danmaku('最多弹幕'),
  favorites('最多收藏'),
  reads('最多阅读'),
  likes('最多喜欢'),
  comments('最多评论'),
  fansDescending('粉丝数由高到低'),
  fansAscending('粉丝数由低到高'),
  levelDescending('等级由高到低'),
  levelAscending('等级由低到高');

  const SearchOrder(this.label);
  final String label;
}

enum SearchDuration {
  any('全部时长'),
  underTen('10分钟以下'),
  tenToThirty('10–30分钟'),
  thirtyToSixty('30–60分钟'),
  overSixty('60分钟以上');

  const SearchDuration(this.label);
  final String label;
}

enum SearchUserType {
  any('全部用户'),
  uploader('UP主'),
  ordinary('普通用户');

  const SearchUserType(this.label);
  final String label;
}

final class SearchPage {
  SearchPage({
    required List<SearchEntry> items,
    required this.hasMore,
    Map<SearchCategory, int> counts = const {},
  }) : items = List.unmodifiable(items),
       counts = Map.unmodifiable(counts);
  final List<SearchEntry> items;
  final bool hasMore;
  final Map<SearchCategory, int> counts;
}

sealed class SearchEntry {
  const SearchEntry();
  SearchCategory get category;
  String get key;
}

final class SearchVideoEntry extends SearchEntry {
  const SearchVideoEntry(this.video);
  final VideoSummary video;
  @override
  SearchCategory get category => SearchCategory.video;
  @override
  String get key => 'video:${video.id.value}';
}

final class SearchUserEntry extends SearchEntry {
  SearchUserEntry({
    required this.id,
    required this.name,
    this.avatarUrl,
    this.signature = '',
    this.fans,
    this.videoCount,
    this.level,
    this.verifyType,
    List<VideoSummary> videos = const [],
  }) : videos = List.unmodifiable(videos);
  final UserId id;
  final String name, signature;
  final Uri? avatarUrl;
  final int? fans, videoCount, level, verifyType;
  final List<VideoSummary> videos;
  @override
  SearchCategory get category => SearchCategory.user;
  @override
  String get key => 'user:${id.value}';
}

final class SearchMediaEntry extends SearchEntry {
  const SearchMediaEntry({
    required this.id,
    required this.title,
    required this.category,
    this.coverUrl,
    this.description = '',
    this.styles = '',
    this.areas = '',
    this.updateText = '',
    this.badge = '',
    this.score,
  });
  final PgcSeasonId id;
  final String title, description, styles, areas, updateText, badge;
  final Uri? coverUrl;
  final double? score;
  @override
  final SearchCategory category;
  @override
  String get key => 'season:${id.value}';
}

final class SearchLiveEntry extends SearchEntry {
  const SearchLiveEntry({
    required this.id,
    required this.title,
    required this.author,
    this.authorId,
    this.coverUrl,
    this.area = '',
    this.online,
    this.isLive,
  });
  final RoomId id;
  final String title, author, area;
  final UserId? authorId;
  final Uri? coverUrl;
  final int? online;
  final bool? isLive;
  @override
  SearchCategory get category => SearchCategory.live;
  @override
  String get key => 'live:${id.value}';
}

final class ArticleId {
  const ArticleId(this.value);
  final String value;
  Uri get url => Uri.https('www.bilibili.com', '/read/cv$value');
}

final class SearchArticleEntry extends SearchEntry {
  const SearchArticleEntry({
    required this.id,
    required this.title,
    this.author = '',
    this.authorId,
    this.coverUrl,
    this.description = '',
    this.section = '',
    this.views,
    this.likes,
    this.replies,
    this.publishedAt,
  });
  final ArticleId id;
  final String title, author, description, section;
  final UserId? authorId;
  final Uri? coverUrl;
  final int? views, likes, replies;
  final DateTime? publishedAt;
  @override
  SearchCategory get category => SearchCategory.article;
  @override
  String get key => 'article:${id.value}';
}
