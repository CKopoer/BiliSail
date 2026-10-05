import 'dynamic_models.dart';

enum ApiHomeEntryKind { video, season, live, dynamic, folder }

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
  final ApiDynamicPost? dynamicPost;
  final String id;
  final String title;
  final ApiHomeEntryKind kind;
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
  final List<ApiHomeEntry> children;
}
