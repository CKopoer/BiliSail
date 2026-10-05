import '../models.dart';

enum ApiSearchType { all, video, bangumi, film, live, article, user }

final class ApiSearchPage {
  ApiSearchPage({
    required List<ApiSearchItem> items,
    required this.hasMore,
    Map<ApiSearchType, int> counts = const {},
  }) : items = List.unmodifiable(items),
       counts = Map.unmodifiable(counts);

  final List<ApiSearchItem> items;
  final bool hasMore;

  /// Only totals supplied by the server; absence does not mean zero.
  final Map<ApiSearchType, int> counts;
}

sealed class ApiSearchItem {
  const ApiSearchItem();
}

final class ApiSearchVideo extends ApiSearchItem {
  const ApiSearchVideo(this.video);
  final ApiVideoSummary video;
}

final class ApiSearchUser extends ApiSearchItem {
  ApiSearchUser({
    required this.mid,
    required this.name,
    this.avatarUrl,
    this.signature = '',
    this.fans,
    this.videoCount,
    this.level,
    this.verifyType,
    List<ApiVideoSummary> videos = const [],
  }) : videos = List.unmodifiable(videos);
  final String mid, name, signature;
  final Uri? avatarUrl;
  final int? fans, videoCount, level, verifyType;
  final List<ApiVideoSummary> videos;
}

final class ApiSearchMedia extends ApiSearchItem {
  const ApiSearchMedia({
    required this.seasonId,
    required this.title,
    required this.type,
    this.coverUrl,
    this.description = '',
    this.styles = '',
    this.areas = '',
    this.updateText = '',
    this.badge = '',
    this.score,
  });
  final String seasonId, title, description, styles, areas, updateText, badge;
  final ApiSearchType type;
  final Uri? coverUrl;
  final double? score;
}

final class ApiSearchLive extends ApiSearchItem {
  const ApiSearchLive({
    required this.roomId,
    required this.title,
    required this.author,
    this.authorMid,
    this.coverUrl,
    this.area = '',
    this.online,
    this.isLive,
  });
  final String roomId, title, author, area;
  final String? authorMid;
  final Uri? coverUrl;
  final int? online;
  final bool? isLive;
}

final class ApiSearchArticle extends ApiSearchItem {
  const ApiSearchArticle({
    required this.id,
    required this.title,
    this.author = '',
    this.authorMid,
    this.coverUrl,
    this.description = '',
    this.category = '',
    this.views,
    this.likes,
    this.replies,
    this.publishedAt,
  });
  final String id, title, author, description, category;
  final String? authorMid;
  final Uri? coverUrl;
  final int? views, likes, replies;
  final DateTime? publishedAt;
}
