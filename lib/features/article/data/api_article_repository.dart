import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/article_address.dart';
import '../../../domain/comment_target.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/article_document.dart';
import '../domain/article_repository.dart';

final class ApiArticleRepository implements ArticleRepository {
  const ApiArticleRepository(this.client, this.requests);

  final ArticleClient client;
  final ApiRequests requests;

  @override
  Future<ArticleDocument> read(
    ArticleAddress address,
    RequestCancellation cancellation,
  ) async {
    try {
      return await requests.run((context) async {
        final article = await client.read(
          address.id,
          opus: address.kind == ArticleKind.opus,
          context: context,
        );
        final authorMid = article.authorMid;
        return ArticleDocument(
          url: article.url,
          title: article.title,
          author: article.author,
          authorId: authorMid == null ? null : UserId(authorMid),
          authorAvatar: article.authorAvatar,
          publishedAt: article.publishedAt,
          accessMessage: article.accessMessage,
          commentTarget: CommentTarget.fromTypeValue(
            article.commentOid,
            article.commentType,
          ),
          commentCount: article.commentCount,
          commentForbidden: article.commentForbidden,
          blocks: List.unmodifiable(article.blocks.map(_block)),
        );
      }, cancellation: cancellation);
    } on AppFailure catch (failure) {
      if (failure.kind == AppFailureKind.notFound) {
        throw const AppFailure(AppFailureKind.notFound, '专栏不存在或已被删除');
      }
      rethrow;
    }
  }

  static ArticleBlock _block(ApiArticleBlock block) => ArticleBlock(
    switch (block.kind) {
      ApiArticleBlockKind.paragraph => ArticleBlockKind.paragraph,
      ApiArticleBlockKind.heading => ArticleBlockKind.heading,
      ApiArticleBlockKind.quote => ArticleBlockKind.quote,
      ApiArticleBlockKind.code => ArticleBlockKind.code,
      ApiArticleBlockKind.divider => ArticleBlockKind.divider,
      ApiArticleBlockKind.image => ArticleBlockKind.image,
    },
    image: block.image,
    aspectRatio: block.aspectRatio,
    text: List.unmodifiable(
      block.text.map(
        (run) => (
          text: run.text,
          link: run.link,
          bold: run.bold,
          italic: run.italic,
          strike: run.strike,
        ),
      ),
    ),
  );
}
