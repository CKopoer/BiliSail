import '../../../domain/article_address.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/comment_target.dart';
import '../../../domain/user.dart';

enum ArticleBlockKind { paragraph, heading, quote, code, divider, image }

typedef ArticleText = ({
  String text,
  Uri? link,
  bool bold,
  bool italic,
  bool strike,
});

final class ArticleBlock {
  const ArticleBlock(
    this.kind, {
    this.text = const [],
    this.image,
    this.aspectRatio,
  });

  final ArticleBlockKind kind;
  final List<ArticleText> text;
  final Uri? image;
  final double? aspectRatio;
}

final class ArticleDocument {
  const ArticleDocument({
    required this.url,
    required this.title,
    required this.blocks,
    this.collection,
    this.dynamicId,
    this.stats,
    this.author = '',
    this.authorId,
    this.authorAvatar,
    this.publishedAt,
    this.accessMessage,
    this.commentTarget,
    this.commentCount,
    this.commentForbidden = false,
  });

  final Uri url;
  final String? dynamicId;
  final ArticleCollectionRef? collection;
  final ArticleStats? stats;
  final String title, author;
  final UserId? authorId;
  final Uri? authorAvatar;
  final DateTime? publishedAt;
  final String? accessMessage;
  final List<ArticleBlock> blocks;
  final CommentTarget? commentTarget;
  final int? commentCount;
  final bool commentForbidden;

  String? get statsCvId =>
      stats == null && commentTarget?.type == CommentTargetType.article
      ? commentTarget?.oid
      : null;

  DynamicPost? actionPost(ArticleStats? actions) {
    final id = dynamicId;
    if (id == null || accessMessage != null) return null;
    return DynamicPost(
      id: id,
      title: title,
      authorId: authorId,
      authorName: author,
      authorAvatarUrl: authorAvatar,
      commentTarget: commentTarget,
      commentCount: commentCount,
      imageUrls: [?blocks.map((block) => block.image).nonNulls.firstOrNull],
      liked: actions?.liked ?? false,
      likeCount: actions?.likes,
      repostCount: actions?.forwards,
      repostForbidden: actions?.forwardForbidden ?? false,
      likeForbidden: actions?.likeForbidden ?? false,
    );
  }
}

typedef ArticleCollectionRef = ({
  ArticleCollectionId id,
  String name,
  String count,
});

typedef ArticleEntry = ({
  ArticleAddress address,
  String title,
  String summary,
  Uri? cover,
  int? views,
});

final class ArticleCollection {
  const ArticleCollection({
    required this.name,
    required this.entries,
    required this.author,
    this.authorId,
    this.cover,
    this.views,
    this.words,
  });
  final String name, author;
  final UserId? authorId;
  final Uri? cover;
  final int? views, words;
  final List<ArticleEntry> entries;
}

final class ArticleStats {
  const ArticleStats({
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
