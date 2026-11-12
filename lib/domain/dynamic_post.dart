import 'comment_target.dart';
import 'user.dart';
import 'video.dart';

enum DynamicTextKind { plain, emoji, mention, topic, link }

enum DynamicCardKind {
  article,
  pgc,
  course,
  season,
  music,
  medialist,
  live,
  ugc,
  goods,
  reservation,
  vote,
  lottery,
  match,
  common,
  unknown,
}

final class DynamicTopic {
  const DynamicTopic({required this.name, this.id, this.url});
  final String name;
  final String? id;
  final Uri? url;
}

final class DynamicContentCard {
  const DynamicContentCard({
    required this.kind,
    required this.title,
    this.description = '',
    this.detail = '',
    this.badge = '',
    this.coverUrl,
    this.url,
    this.actionLabel = '',
    this.actionUrl,
    this.reservation,
  });
  final DynamicCardKind kind;
  final String title, description, detail, badge, actionLabel;
  final Uri? coverUrl, url, actionUrl;
  final DynamicReservation? reservation;
}

final class DynamicReservation {
  const DynamicReservation({
    required this.id,
    required this.status,
    required this.type,
    required this.total,
    this.description = '',
    this.checkedText = '已预约',
    this.uncheckedText = '预约',
    this.disabled = false,
    this.ended = false,
    this.hasJump = false,
  });
  final String id, description, checkedText, uncheckedText;
  final int status, type, total;
  final bool disabled, ended, hasJump;
  bool get checked => status == type;
  bool get canToggle => !disabled && !ended && !hasJump;
  String get label => checked ? checkedText : uncheckedText;

  // Fresh card capabilities take precedence over a cached account action.
  DynamicReservation withCachedState(DynamicReservation? cached) =>
      cached == null || cached.id != id || cached.type != type
      ? this
      : updated(cached.status, cached.total, cached.description);

  DynamicReservation updated(int status, int total, String description) =>
      DynamicReservation(
        id: id,
        status: status,
        type: type,
        total: total,
        description: description,
        checkedText: checkedText,
        uncheckedText: uncheckedText,
        disabled: disabled,
        ended: ended,
        hasJump: hasJump,
      );
}

final class DynamicTextSpan {
  const DynamicTextSpan({
    this.kind = DynamicTextKind.plain,
    required this.text,
    this.imageUrl,
    this.linkUrl,
    this.userId,
    this.emojiSize = 1,
  });
  final DynamicTextKind kind;
  final String text;
  final Uri? imageUrl, linkUrl;
  final UserId? userId;
  final double emojiSize;
}

final class DynamicPost {
  DynamicPost({
    required this.id,
    this.title = '',
    this.authorName = '',
    this.authorId,
    this.authorAvatarUrl,
    this.authorPendantUrl,
    this.publishedAt,
    this.publishText = '',
    this.actionText = '',
    this.text = '',
    this.topic,
    this.badge = '',
    this.notice = '',
    List<DynamicContentCard> contentCards = const [],
    List<DynamicTextSpan> spans = const [],
    List<Uri> imageUrls = const [],
    Map<Uri, double> imageAspectRatios = const {},
    this.video,
    this.original,
    this.repostCount,
    this.commentCount,
    this.likeCount,
    this.typeLabel = '',
    this.linkTitle = '',
    this.linkDescription = '',
    this.linkCoverUrl,
    this.linkUrl,
    this.commentTarget,
    this.liked = false,
    this.commentForbidden = false,
    this.repostForbidden = false,
    this.likeForbidden = false,
    this.unavailable = false,
    this.pinned = false,
    this.onlySelf = false,
    this.editable = false,
  }) : contentCards = List.unmodifiable(contentCards),
       spans = List.unmodifiable(spans),
       imageUrls = List.unmodifiable(imageUrls),
       imageAspectRatios = Map.unmodifiable(imageAspectRatios);
  final String id,
      title,
      authorName,
      publishText,
      actionText,
      text,
      typeLabel,
      linkTitle,
      linkDescription;
  final UserId? authorId;
  final DynamicTopic? topic;
  final String badge, notice;
  final List<DynamicContentCard> contentCards;
  final Uri? authorAvatarUrl, authorPendantUrl, linkCoverUrl, linkUrl;
  final DateTime? publishedAt;
  final List<DynamicTextSpan> spans;
  final List<Uri> imageUrls;

  /// Width / height of each original picture; absent values use a stable slot.
  final Map<Uri, double> imageAspectRatios;
  final VideoSummary? video;
  final DynamicPost? original;
  final int? repostCount, commentCount, likeCount;
  final CommentTarget? commentTarget;
  final bool unavailable,
      pinned,
      onlySelf,
      editable,
      liked,
      commentForbidden,
      repostForbidden,
      likeForbidden;

  DynamicPost withManagement({
    bool? pinned,
    bool? onlySelf,
    bool? commentForbidden,
  }) => DynamicPost(
    id: id,
    title: title,
    authorName: authorName,
    authorId: authorId,
    authorAvatarUrl: authorAvatarUrl,
    authorPendantUrl: authorPendantUrl,
    publishedAt: publishedAt,
    publishText: publishText,
    actionText: actionText,
    text: text,
    topic: topic,
    badge: badge,
    notice: notice,
    contentCards: contentCards,
    spans: spans,
    imageUrls: imageUrls,
    imageAspectRatios: imageAspectRatios,
    video: video,
    original: original,
    repostCount: repostCount,
    commentCount: commentCount,
    likeCount: likeCount,
    typeLabel: typeLabel,
    linkTitle: linkTitle,
    linkDescription: linkDescription,
    linkCoverUrl: linkCoverUrl,
    linkUrl: linkUrl,
    commentTarget: commentTarget,
    liked: liked,
    commentForbidden: commentForbidden ?? this.commentForbidden,
    repostForbidden: repostForbidden,
    likeForbidden: likeForbidden,
    unavailable: unavailable,
    pinned: pinned ?? this.pinned,
    onlySelf: onlySelf ?? this.onlySelf,
    editable: editable,
  );
}
