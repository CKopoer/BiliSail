import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import 'dynamic_actions_controller.dart';

final dynamicDetailProvider = FutureProvider.autoDispose
    .family<DynamicPost, ({String id, bool byResourceId})>((
      ref,
      address,
    ) async {
      final repository = ref.watch(dynamicRepositoryProvider);
      if (repository == null) {
        throw const AppFailure(AppFailureKind.unknown, '动态服务暂不可用');
      }
      ref.watch(
        authControllerProvider.select(
          (auth) => (auth.status, auth.mid, repository.sessionEpoch),
        ),
      );
      final cancellation = RequestCancellation();
      ref.onDispose(cancellation.cancel);
      final scope = repository.accountScope;
      final epoch = repository.sessionEpoch;
      final post = await repository.detail(
        address.id,
        cancellation,
        byResourceId: address.byResourceId,
      );
      if (cancellation.isCancelled ||
          repository.accountScope != scope ||
          repository.sessionEpoch != epoch) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      return post;
    }, retry: (_, _) => null);
