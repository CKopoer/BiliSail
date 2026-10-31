import 'user.dart';
import 'recommendation_source.dart';
import 'video_access.dart';
export 'video_access.dart';

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
    this.likeCount,
    this.categoryName,
    this.isFollowed,
    this.danmakuCount,
    this.publishedAt,
    this.authorAvatarUrl,
    this.authorId,
    this.recommendationReason,
    this.recommendationFeedback,
    this.recommendationTarget,
    this.previewCid,
    this.access = const VideoAccess(),
  });

  final VideoId id;
  final String title;
  final String coverUrl;
  final String author;
  final Duration duration;
  final int? playCount;
  final int? likeCount;
  final String? categoryName;
  final bool? isFollowed;
  final int? danmakuCount;
  final DateTime? publishedAt;
  final Uri? authorAvatarUrl;
  final UserId? authorId;
  final String? recommendationReason;
  final RecommendationFeedback? recommendationFeedback;
  final RecommendationTarget? recommendationTarget;

  /// Optional page ID already supplied by a list, avoiding a detail read.
  final String? previewCid;
  final VideoAccess access;
}

enum RecommendationTargetKind {
  video,
  episode,
  season,
  live,
  dynamic,
  external,
  unsupported,
}

final class RecommendationTarget {
  const RecommendationTarget({required this.kind, this.id = '', this.url});
  final RecommendationTargetKind kind;
  final String id;
  final Uri? url;
}

/// Opaque recommendation context returned by the Web feed, kept in memory.
final class RecommendationFeedback {
  const RecommendationFeedback({
    required this.aid,
    required this.goto,
    required this.trackId,
    required this.ownerMid,
  }) : source = RecommendationSource.web,
       reasons = const [],
       selectedReason = null,
       identityRevision = 0;
  RecommendationFeedback.app({
    required this.aid,
    required this.ownerMid,
    required List<RecommendationFeedbackReason> reasons,
    required this.identityRevision,
    this.selectedReason,
    this.goto = 'av',
  }) : source = RecommendationSource.app,
       trackId = '',
       reasons = List.unmodifiable(reasons);
  final String aid, goto, trackId, ownerMid;
  final RecommendationSource source;
  final List<RecommendationFeedbackReason> reasons;
  final RecommendationFeedbackReason? selectedReason;
  final int identityRevision;
  RecommendationFeedback selectReason(RecommendationFeedbackReason reason) {
    if (!reasons.any(
      (item) => item.id == reason.id && item.kind == reason.kind,
    )) {
      throw ArgumentError('Unknown recommendation feedback reason');
    }
    return RecommendationFeedback.app(
      aid: aid,
      goto: goto,
      ownerMid: ownerMid,
      reasons: reasons,
      identityRevision: identityRevision,
      selectedReason: reason,
    );
  }
}

enum RecommendationFeedbackReasonKind { dislike, feedback }

final class RecommendationFeedbackReason {
  const RecommendationFeedbackReason({
    required this.id,
    required this.name,
    required this.kind,
  });
  final String id, name;
  final RecommendationFeedbackReasonKind kind;
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

final class VideoStaffMember {
  const VideoStaffMember({
    required this.name,
    required this.title,
    this.id,
    this.avatarUrl,
    this.highlightedRole = false,
    this.nicknameColor,
  });

  final String name, title;
  final UserId? id;
  final Uri? avatarUrl;
  final bool highlightedRole;
  final String? nicknameColor;
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
    this.staff = const [],
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
  final List<VideoStaffMember> staff;
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
