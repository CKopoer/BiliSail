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
        final stats = article.stats;
        return ArticleDocument(
          url: article.url,
          title: article.title,
          dynamicId: article.dynamicId,
          stats: stats == null ? null : _stats(stats),
          collection: switch (article.collection) {
            final info? => (
              id: ArticleCollectionId(info.id),
              name: info.name,
              count: info.count,
            ),
            null => null,
          },
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

  @override
  Future<ArticleCollection> collection(
    ArticleCollectionId id,
    RequestCancellation cancellation,
  ) async {
    try {
      return await requests.run((context) async {
        final data = await client.collection(id.value, context: context);
        final authorMid = data.authorMid;
        return ArticleCollection(
          name: data.name,
          author: data.author,
          cover: data.cover,
          authorId: authorMid == null ? null : UserId(authorMid),
          views: data.views,
          words: data.words,
          entries: List.unmodifiable(
            data.entries.map(
              (entry) => (
                address: ArticleAddress(
                  entry.opus ? ArticleKind.opus : ArticleKind.column,
                  entry.id,
                ),
                title: entry.title,
                summary: entry.summary,
                cover: entry.cover,
                views: entry.views,
              ),
            ),
          ),
        );
      }, cancellation: cancellation);
    } on AppFailure catch (failure) {
      if (failure.kind == AppFailureKind.notFound) {
        throw const AppFailure(AppFailureKind.notFound, '文集不存在或已被删除');
      }
      rethrow;
    }
  }

  static ArticleStats _stats(ApiArticleStats stats) => ArticleStats(
    liked: stats.liked,
    favorited: stats.favorited,
    likes: stats.likes,
    favorites: stats.favorites,
    forwards: stats.forwards,
    comments: stats.comments,
    likeForbidden: stats.likeForbidden,
    forwardForbidden: stats.forwardForbidden,
  );

  @override
  Future<ArticleStats> viewInfo(
    String cvId,
    RequestCancellation cancellation,
  ) => requests.run(
    (context) async => _stats(await client.viewInfo(cvId, context: context)),
    cancellation: cancellation,
  );

  @override
  Future<void> setFavorite(
    ArticleAddress address,
    bool favorite,
    RequestCancellation cancellation,
  ) => requests.run(
    (context) => client.setFavorite(
      address.id,
      opus: address.kind == ArticleKind.opus,
      favorite: favorite,
      context: context,
    ),
    cancellation: cancellation,
  );

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
