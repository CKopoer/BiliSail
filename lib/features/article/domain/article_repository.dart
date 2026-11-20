import '../../../domain/article_address.dart';
import '../../../domain/request_cancellation.dart';
import 'article_document.dart';

abstract interface class ArticleRepository {
  Future<ArticleDocument> read(
    ArticleAddress address,
    RequestCancellation cancellation,
  );
  Future<ArticleCollection> collection(
    ArticleCollectionId id,
    RequestCancellation cancellation,
  );
  Future<ArticleStats> viewInfo(String cvId, RequestCancellation cancellation);
  Future<void> setFavorite(
    ArticleAddress address,
    bool favorite,
    RequestCancellation cancellation,
  );
}
