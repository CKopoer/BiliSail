import 'dynamic_models.dart';
import '../models.dart';

enum ApiProfileEntryKind { video, dynamic, folder, user }

final class ApiUserProfile {
  const ApiUserProfile({
    required this.mid,
    required this.name,
    this.avatarUrl,
    this.signature = '',
    this.level,
    this.verifyType,
    this.verifyDescription,
    this.vipLabel,
    this.followerCount,
    this.followingCount,
    this.likeCount,
    this.videoCount,
  });
  final String mid, name, signature;
  final Uri? avatarUrl;
  final int? level,
      verifyType,
      followerCount,
      followingCount,
      likeCount,
      videoCount;
  final String? verifyDescription, vipLabel;
}

final class ApiProfileEntry {
  ApiProfileEntry({
    required this.id,
    this.dynamicPost,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.coverUrl,
    this.video,
    this.userMid,
    this.publishedAt,
    this.count,
    List<Uri> imageUrls = const [],
  }) : imageUrls = List.unmodifiable(imageUrls);
  final ApiDynamicPost? dynamicPost;
  final String id, title, subtitle;
  final ApiProfileEntryKind kind;
  final Uri? coverUrl;
  final ApiVideoSummary? video;
  final String? userMid;
  final DateTime? publishedAt;
  final int? count;
  final List<Uri> imageUrls;
}
