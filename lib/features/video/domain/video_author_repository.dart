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

abstract interface class VideoAuthorRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<VideoAuthor> load(VideoAuthorId id, RequestCancellation cancellation);
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  );
}
