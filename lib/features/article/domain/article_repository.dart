import '../../../domain/article_address.dart';
import '../../../domain/request_cancellation.dart';
import 'article_document.dart';

abstract interface class ArticleRepository {
  Future<ArticleDocument> read(
    ArticleAddress address,
    RequestCancellation cancellation,
  );
}
