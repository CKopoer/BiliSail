import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import 'home_channel.dart';

enum HomeEntryKind { video, season, live, dynamic, folder, collection }

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
    this.aid,
    this.previewCid,
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
    this.contentCount,
    this.viewCount,
    this.isPrivate,
    this.createdAt,
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
  final String? aid;
  final String? previewCid;
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
  final int? contentCount;
  final int? viewCount;
  final bool? isPrivate;
  final DateTime? createdAt;
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

/// Optional write capability of the account's collected folders/UGC collections.
abstract interface class HomeSubscriptionRepository {
  Future<void> unsubscribeFavorite(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  });
}

abstract interface class HomeWatchLaterRepository {
  Future<void> removeWatchLater(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  });
}
