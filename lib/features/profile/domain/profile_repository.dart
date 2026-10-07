import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';

enum ProfileSection { videos, dynamics, folders, following, followers }

enum ProfileEntryKind { video, dynamic, folder, user }

final class UserProfile {
  const UserProfile({
    required this.id,
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
  final UserId id;
  final String name, signature;
  final Uri? avatarUrl;
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
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    required RequestCancellation cancellation,
  });
}
