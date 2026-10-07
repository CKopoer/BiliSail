import 'comment_target.dart';
import 'user.dart';
import 'video.dart';

enum DynamicTextKind { plain, emoji, mention, topic, link }

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
    this.publishedAt,
    this.publishText = '',
    this.actionText = '',
    this.text = '',
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
  }) : spans = List.unmodifiable(spans),
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
  final Uri? authorAvatarUrl, linkCoverUrl, linkUrl;
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
      liked,
      commentForbidden,
      repostForbidden,
      likeForbidden;
}
