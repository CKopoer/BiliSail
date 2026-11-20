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
    .family<ArticleDocument, ArticleAddress>((ref, address) async {
      final repository = ref.watch(articleRepositoryProvider);
      if (repository == null) {
        throw const AppFailure(AppFailureKind.unknown, '专栏服务暂不可用');
      }
      final sessionEpoch = ref.watch(sessionEpochProvider);
      final epoch = ref
          .watch(
            authControllerProvider.select(
              (auth) => (auth.status, auth.mid, sessionEpoch()),
            ),
          )
          .$3;
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      final article = await repository.read(address, cancellation);
      if (cancellation.isCancelled || sessionEpoch() != epoch) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      return article;
    }, retry: (_, _) => null);
