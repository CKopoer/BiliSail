import '../models.dart';

enum ApiDynamicTextKind { plain, emoji, mention, topic, link }

final class ApiDynamicTextSpan {
  const ApiDynamicTextSpan({
    this.kind = ApiDynamicTextKind.plain,
    required this.text,
    this.imageUrl,
    this.linkUrl,
    this.userId,
    this.emojiSize = 1,
  });
  final ApiDynamicTextKind kind;
  final String text;
  final Uri? imageUrl, linkUrl;
  final String? userId;
  final double emojiSize;
}

final class ApiDynamicPost {
  ApiDynamicPost({
    required this.id,
    this.title = '',
    this.authorName = '',
    this.authorId,
    this.authorAvatarUrl,
    this.publishedAt,
    this.publishText = '',
    this.actionText = '',
    this.text = '',
    List<ApiDynamicTextSpan> spans = const [],
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
    this.commentOid,
    this.commentType,
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
  final String? authorId;
  final Uri? authorAvatarUrl, linkCoverUrl, linkUrl;
  final DateTime? publishedAt;
  final List<ApiDynamicTextSpan> spans;
  final List<Uri> imageUrls;

  /// Width / height from the response, keyed by the original image URL.
  final Map<Uri, double> imageAspectRatios;
  final ApiVideoSummary? video;
  final ApiDynamicPost? original;
  final int? repostCount, commentCount, likeCount;
  final String? commentOid;
  final int? commentType;
  final bool unavailable,
      liked,
      commentForbidden,
      repostForbidden,
      likeForbidden;
}
