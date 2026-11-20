import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/article_address.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/article_document.dart';
import '../domain/article_repository.dart';

final articleRepositoryProvider = Provider<ArticleRepository?>((ref) => null);

final articleProvider = FutureProvider.autoDispose
    .family<ArticleDocument, ArticleAddress>(
      (ref, address) => _read(
        ref,
        (repository, cancellation) => repository.read(address, cancellation),
      ),
      retry: (_, _) => null,
    );

final articleCollectionProvider = FutureProvider.autoDispose
    .family<ArticleCollection, ArticleCollectionId>(
      (ref, id) => _read(
        ref,
        (repository, cancellation) => repository.collection(id, cancellation),
      ),
      retry: (_, _) => null,
    );

final articleInfoProvider = FutureProvider.autoDispose
    .family<ArticleStats, String>(
      (ref, cvId) => _read(
        ref,
        (repository, cancellation) => repository.viewInfo(cvId, cancellation),
      ),
      retry: (_, _) => null,
    );

Future<T> _read<T>(
  Ref ref,
  Future<T> Function(ArticleRepository, RequestCancellation) load,
) async {
  final repository = ref.watch(articleRepositoryProvider);
  if (repository == null) {
    throw const AppFailure(AppFailureKind.unknown, '专栏服务暂不可用');
  }
  final epoch = _watchAccount(ref);
  final cancellation = RequestCancellation();
  ref.onDispose(cancellation.cancel);
  final value = await load(repository, cancellation);
  if (cancellation.isCancelled || ref.read(sessionEpochProvider)() != epoch) {
    throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
  }
  return value;
}

int _watchAccount(Ref ref) {
  final current = ref.watch(sessionEpochProvider);
  return ref
      .watch(
        authControllerProvider.select(
          (auth) => (auth.status, auth.mid, current()),
        ),
      )
      .$3;
}

typedef ArticleFavoriteState = ({
  bool busy,
  bool? favorite,
  int? count,
  bool uncertain,
});
final articleFavoriteProvider = NotifierProvider.autoDispose
    .family<ArticleFavoriteController, ArticleFavoriteState, ArticleAddress>(
      ArticleFavoriteController.new,
    );

class ArticleFavoriteController extends Notifier<ArticleFavoriteState> {
  ArticleFavoriteController(this.address);
  final ArticleAddress address;
  late RequestCancellation _cancellation;
  late int _epoch;

  @override
  ArticleFavoriteState build() {
    _epoch = _watchAccount(ref);
    _cancellation = RequestCancellation();
    ref.onDispose(_cancellation.cancel);
    return (busy: false, favorite: null, count: null, uncertain: false);
  }

  Future<String?> toggle(bool initialFavorite, int? initialCount) async {
    final repository = ref.read(articleRepositoryProvider);
    if (repository == null ||
        state.busy ||
        state.uncertain ||
        !ref.read(authControllerProvider).isSignedIn) {
      return null;
    }
    final cancellation = _cancellation;
    bool active() =>
        !cancellation.isCancelled &&
        ref.mounted &&
        ref.read(sessionEpochProvider)() == _epoch;
    final previous = state;
    final current = previous.favorite ?? initialFavorite;
    final count = previous.count ?? initialCount;
    state = (
      busy: true,
      favorite: previous.favorite,
      count: previous.count,
      uncertain: false,
    );
    try {
      await repository.setFavorite(address, !current, cancellation);
      if (!active()) return null;
      state = (
        busy: false,
        favorite: !current,
        count: count == null
            ? null
            : (count + (current ? -1 : 1)).clamp(0, 0x7fffffffffffffff),
        uncertain: false,
      );
      return null;
    } catch (error) {
      if (!active()) return null;
      final uncertain =
          error is! AppFailure ||
          const {
            AppFailureKind.network,
            AppFailureKind.timeout,
            AppFailureKind.protocol,
          }.contains(error.kind);
      state = (
        busy: false,
        favorite: previous.favorite,
        count: previous.count,
        uncertain: uncertain,
      );
      if (uncertain) return '收藏结果未确认，请刷新后核对';
      return error.kind == AppFailureKind.cancelled ? null : error.message;
    }
  }
}
