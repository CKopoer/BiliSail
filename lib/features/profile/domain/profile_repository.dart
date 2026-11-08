import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../live/domain/live_room.dart';

enum ProfileSection {
  videos,
  dynamics,
  folders,
  collections,
  bangumi,
  cinema,
  following,
  followers,
}

enum ProfileEntryKind { video, dynamic, folder, user, collection, season }

final class ProfileFollowGroup {
  const ProfileFollowGroup({required this.id, required this.name});

  final String id, name;
  bool get isEditable => RegExp(r'^[1-9]\d*$').hasMatch(id);
}

enum FollowGroupEdit { create, rename, delete }

/// Owner-only operations, separate from public profile browsing.
abstract interface class ProfileFollowingManagementRepository {
  Future<ProfilePage> loadManagedFollowing(
    UserId owner, {
    required int page,
    String keyword = '',
    String order = '',
    bool blacklist = false,
    required RequestCancellation cancellation,
  });

  /// Creation returns the confirmed group identity; other edits return null.
  Future<ProfileFollowGroup?> editFollowGroup(
    UserId owner,
    FollowGroupEdit edit, {
    String? groupId,
    String name = '',
    required RequestCancellation cancellation,
  });
  Future<void> sortFollowGroups(
    UserId owner,
    List<String> ids, {
    required RequestCancellation cancellation,
  });
  Future<void> setFollowingBlocked(
    UserId owner,
    UserId target,
    bool blocked, {
    required RequestCancellation cancellation,
  });
}

abstract interface class ProfileFollowGroupsRepository {
  Future<List<ProfileFollowGroup>> loadFollowGroups(
    UserId id, {
    required RequestCancellation cancellation,
  });

  Future<ProfilePage> loadFollowingGroup(
    UserId id,
    String groupId, {
    required int page,
    required RequestCancellation cancellation,
  });
}

final class ProfileCollectionId {
  const ProfileCollectionId(this.value, {required this.isSeries});
  final String value;
  final bool isSeries;
  @override
  bool operator ==(Object other) =>
      other is ProfileCollectionId &&
      other.value == value &&
      other.isSeries == isSeries;
  @override
  int get hashCode => Object.hash(value, isSeries);
}

final class ProfileSpaceDetails {
  const ProfileSpaceDetails({
    this.bannerUrl,
    this.gender = '',
    this.birthday = '',
  });
  final Uri? bannerUrl;
  final String gender, birthday;
}

/// Optional enrichment never blocks the basic public card or its content.
abstract interface class ProfileDetailsRepository {
  Future<ProfileSpaceDetails> loadDetails(
    UserId id, {
    required RequestCancellation cancellation,
  });
}

abstract interface class ProfileActionsRepository {
  Future<bool> loadBlocked(
    UserId id, {
    required RequestCancellation cancellation,
  });
  Future<void> setBlocked(
    UserId id,
    bool blocked, {
    required RequestCancellation cancellation,
  });
}

final class ProfileLiveRoom {
  const ProfileLiveRoom({required this.id, required this.isLive});

  final RoomId id;
  final bool isLive;
}

final class UserProfile {
  const UserProfile({
    required this.id,
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
  final UserId id;
  final String name, signature;
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

final class ProfileEntry {
  const ProfileEntry({
    required this.id,
    this.dynamicPost,
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.coverUrl,
    this.video,
    this.userId,
    this.publishedAt,
    this.count,
    this.collection,
    this.seasonId,
    this.imageUrls = const [],
  });
  final DynamicPost? dynamicPost;
  final String id, title, subtitle;
  final ProfileEntryKind kind;
  final Uri? coverUrl;
  final VideoSummary? video;
  final UserId? userId;
  final DateTime? publishedAt;
  final int? count;
  final ProfileCollectionId? collection;
  final String? seasonId;
  final List<Uri> imageUrls;
}

final class ProfilePage {
  const ProfilePage({required this.items, required this.hasMore, this.cursor})
    : isHidden = false;
  const ProfilePage.hidden()
    : items = const [],
      hasMore = false,
      cursor = null,
      isHidden = true;
  final List<ProfileEntry> items;
  final bool hasMore, isHidden;
  final String? cursor;
}

abstract interface class ProfileRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  });
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  });
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    ProfileCollectionId? collection,
    required RequestCancellation cancellation,
  });
}
