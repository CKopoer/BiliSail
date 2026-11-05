import 'dynamic_models.dart';
import '../models.dart';

enum ApiProfileEntryKind { video, dynamic, folder, user, collection, season }

final class ApiProfileSpaceDetails {
  const ApiProfileSpaceDetails({
    this.bannerUrl,
    this.gender = '',
    this.birthday = '',
  });
  final Uri? bannerUrl;
  final String gender, birthday;
}

final class ApiProfileLiveRoom {
  const ApiProfileLiveRoom({required this.roomId, required this.isLive});

  final String roomId;
  final bool isLive;
}

final class ApiProfileRelationPrivacy {
  const ApiProfileRelationPrivacy({
    required this.followingHidden,
    required this.followersHidden,
  });

  final bool followingHidden, followersHidden;
}

final class ApiProfileContentPrivacy {
  const ApiProfileContentPrivacy({
    required this.foldersHidden,
    required this.seasonsHidden,
  });
  final bool foldersHidden, seasonsHidden;
}

final class ApiUserProfile {
  const ApiUserProfile({
    required this.mid,
    required this.name,
    this.avatarUrl,
    this.pendantUrl,
    this.bannerUrl,
    this.vipLabelImageUrl,
    this.vipStatus,
    this.vipType,
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
  final Uri? avatarUrl, pendantUrl, bannerUrl, vipLabelImageUrl;
  final int? vipStatus, vipType;
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
    this.collectionId,
    this.isSeries = false,
    this.seasonId,
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
  final String? collectionId, seasonId;
  final bool isSeries;
  final List<Uri> imageUrls;
}
