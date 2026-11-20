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
  final String title, author;
  final UserId? authorId;
  final Uri? authorAvatar;
  final DateTime? publishedAt;
  final String? accessMessage;
  final List<ArticleBlock> blocks;
  final CommentTarget? commentTarget;
  final int? commentCount;
  final bool commentForbidden;
}
