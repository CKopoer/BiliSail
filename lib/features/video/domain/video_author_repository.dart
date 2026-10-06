import '../../../domain/request_cancellation.dart';

final class VideoAuthorId {
  const VideoAuthorId(this.value);
  final String value;
  @override
  bool operator ==(Object other) =>
      other is VideoAuthorId && value == other.value;
  @override
  int get hashCode => value.hashCode;
}

final class VideoAuthor {
  const VideoAuthor({
    required this.following,
    this.followerCount,
    this.likeCount,
  });
  final bool following;
  final int? followerCount, likeCount;

  VideoAuthor withFollowing(bool following) => VideoAuthor(
    following: following,
    followerCount: followerCount,
    likeCount: likeCount,
  );
}

final class FollowGroup {
  const FollowGroup({required this.id, required this.name});

  final String id;
  final String name;
}

final class FollowGroupSelection {
  const FollowGroupSelection({required this.groups, required this.selectedIds});

  final List<FollowGroup> groups;
  final Set<String> selectedIds;
}

abstract interface class VideoAuthorRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<VideoAuthor> load(VideoAuthorId id, RequestCancellation cancellation);
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  );
  Future<FollowGroupSelection> loadGroups(
    VideoAuthorId id,
    RequestCancellation cancellation,
  );
  Future<void> saveGroups(
    VideoAuthorId id,
    Set<String> groupIds,
    RequestCancellation cancellation,
  );
}
