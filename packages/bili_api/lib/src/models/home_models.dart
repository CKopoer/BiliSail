import 'dynamic_models.dart';

enum ApiHomeEntryKind { video, season, live, dynamic, folder, collection }

final class ApiHomeEntry {
  const ApiHomeEntry({
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
  final ApiDynamicPost? dynamicPost;
  final String id;
  final String title;
  final ApiHomeEntryKind kind;
  final Uri? coverUrl;
  final String subtitle;
  final String description;
  final String? bvid;

  /// Decimal archive ID, independent of the card's stable BVID identity.
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
  final List<ApiHomeEntry> children;
}
