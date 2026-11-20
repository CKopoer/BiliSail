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

typedef ApiArticleCollectionRef = ({String id, String name, String count});
typedef ApiArticleEntry = ({
  String id,
  bool opus,
  String title,
  String summary,
  Uri? cover,
  int? views,
});

final class ApiArticleCollection {
  const ApiArticleCollection({
    required this.name,
    required this.entries,
    required this.author,
    this.authorMid,
    this.cover,
    this.words,
    this.views,
  });
  final String name, author;
  final String? authorMid;
  final Uri? cover;
  final int? words, views;
  final List<ApiArticleEntry> entries;
}

final class ApiArticleStats {
  const ApiArticleStats({
    this.liked,
    this.favorited,
    this.likes,
    this.favorites,
    this.forwards,
    this.comments,
    this.likeForbidden = false,
    this.forwardForbidden = false,
  });
  final bool? liked, favorited;
  final int? likes, favorites, forwards, comments;
  final bool likeForbidden, forwardForbidden;
}

final class ApiArticle {
  const ApiArticle({
    required this.url,
    required this.title,
    required this.blocks,
    this.collection,
    this.stats,
    this.dynamicId,
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
  final String? authorMid, accessMessage, dynamicId;
  final ApiArticleCollectionRef? collection;
  final ApiArticleStats? stats;
  final Uri? authorAvatar;
  final DateTime? publishedAt;
  final List<ApiArticleBlock> blocks;
  final String? commentOid;
  final int? commentType, commentCount;
  final bool commentForbidden;
}
