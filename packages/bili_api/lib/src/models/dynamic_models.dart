import '../models.dart';

enum ApiDynamicTextKind { plain, emoji, mention, topic, link }

enum ApiDynamicCardKind {
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

final class ApiDynamicTopic {
  const ApiDynamicTopic({required this.name, this.id, this.url});
  final String name;
  final String? id;
  final Uri? url;
}

/// A displayable major or additional module, without account write semantics.
final class ApiDynamicContentCard {
  const ApiDynamicContentCard({
    required this.kind,
    required this.title,
    this.description = '',
    this.detail = '',
    this.badge = '',
    this.coverUrl,
    this.url,
    this.actionLabel = '',
    this.actionUrl,
  });
  final ApiDynamicCardKind kind;
  final String title, description, detail, badge, actionLabel;
  final Uri? coverUrl, url, actionUrl;
}

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
    this.topic,
    this.badge = '',
    this.notice = '',
    List<ApiDynamicContentCard> contentCards = const [],
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
  final String? authorId;
  final ApiDynamicTopic? topic;
  final String badge, notice;
  final List<ApiDynamicContentCard> contentCards;
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
