enum ApiArticleBlockKind { paragraph, heading, quote, code, divider, image }

final class ApiArticleText {
  const ApiArticleText(
    this.text, {
    this.link,
    this.bold = false,
    this.italic = false,
    this.strike = false,
  });

  final String text;
  final Uri? link;
  final bool bold, italic, strike;
}

final class ApiArticleBlock {
  const ApiArticleBlock(
    this.kind, {
    this.text = const [],
    this.image,
    this.aspectRatio,
  });

  final ApiArticleBlockKind kind;
  final List<ApiArticleText> text;
  final Uri? image;
  final double? aspectRatio;
}

final class ApiArticle {
  const ApiArticle({
    required this.url,
    required this.title,
    required this.blocks,
    this.author = '',
    this.authorMid,
    this.authorAvatar,
    this.publishedAt,
    this.accessMessage,
    this.commentOid,
    this.commentType,
    this.commentCount,
    this.commentForbidden = false,
  });

  final Uri url;
  final String title, author;
  final String? authorMid, accessMessage;
  final Uri? authorAvatar;
  final DateTime? publishedAt;
  final List<ApiArticleBlock> blocks;
  final String? commentOid;
  final int? commentType, commentCount;
  final bool commentForbidden;
}
