import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import 'home_channel.dart';

enum HomeEntryKind { video, season, live, dynamic, folder }

final class HomeEntry {
  const HomeEntry({
    required this.id,
    this.dynamicPost,
    required this.title,
    required this.kind,
    this.coverUrl,
    this.subtitle = '',
    this.description = '',
    this.bvid,
    this.url,
    this.authorName = '',
    this.authorAvatarUrl,
    this.authorMid,
    this.duration,
    this.publishedAt,
    this.publishText = '',
    this.playCountText = '',
    this.danmakuCountText = '',
    this.popularityText = '',
    this.areaName = '',
    this.children = const [],
  });
  final DynamicPost? dynamicPost;
  final String id;
  final String title;
  final HomeEntryKind kind;
  final Uri? coverUrl;
  final String subtitle;
  final String description;
  final String? bvid;
  final Uri? url;
  final String authorName;
  final Uri? authorAvatarUrl;
  final String? authorMid;
  final Duration? duration;
  final DateTime? publishedAt;
  final String publishText;
  final String playCountText;
  final String danmakuCountText;
  final String popularityText;
  final String areaName;
  final List<HomeEntry> children;
}

final class HomePage {
  const HomePage(this.items, {required this.hasMore, this.nextCursor});
  final List<HomeEntry> items;
  final bool hasMore;
  final String? nextCursor;
}

typedef HomeQuery = ({
  HomeChannel channel,
  String section,
  String scope,
  String? folderId,
});

abstract interface class HomeRepository {
  String get accountScope;
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  });
}
