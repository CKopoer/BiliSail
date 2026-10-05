import 'user.dart';

final class VideoId {
  const VideoId(this.value);

  final String value;

  bool get isValid => RegExp(r'^BV[0-9A-Za-z]{10}$').hasMatch(value);

  @override
  bool operator ==(Object other) => other is VideoId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class VideoSummary {
  const VideoSummary({
    required this.id,
    required this.title,
    required this.coverUrl,
    required this.author,
    required this.duration,
    this.playCount,
    this.danmakuCount,
    this.publishedAt,
    this.authorAvatarUrl,
    this.authorId,
    this.recommendationReason,
  });

  final VideoId id;
  final String title;
  final String coverUrl;
  final String author;
  final Duration duration;
  final int? playCount;
  final int? danmakuCount;
  final DateTime? publishedAt;
  final Uri? authorAvatarUrl;
  final UserId? authorId;
  final String? recommendationReason;
}

final class VideoPart {
  const VideoPart({
    required this.cid,
    required this.page,
    required this.title,
    required this.duration,
  });

  final String cid;
  final int page;
  final String title;
  final Duration duration;
}

final class VideoDetail {
  const VideoDetail({
    required this.summary,
    required this.description,
    required this.parts,
    this.tags = const [],
    this.aid,
    this.authorMid,
    this.likeCount,
    this.coinCount,
    this.favoriteCount,
    this.replyCount,
    this.collection,
  });

  final VideoSummary summary;
  final String description;
  final List<VideoPart> parts;
  final List<String> tags;
  final String? aid;
  final String? authorMid;
  final int? likeCount;
  final int? coinCount;
  final int? favoriteCount;
  final int? replyCount;
  final VideoCollection? collection;
}

final class VideoCollection {
  const VideoCollection({
    required this.id,
    required this.title,
    required this.entries,
    this.playCount,
  });
  final String id;
  final String title;
  final List<VideoCollectionEntry> entries;
  final int? playCount;
}

final class VideoCollectionEntry {
  const VideoCollectionEntry({
    required this.id,
    required this.title,
    required this.parts,
    this.duration,
  });
  final VideoId id;
  final String title;
  final List<VideoPart> parts;
  final Duration? duration;
}
