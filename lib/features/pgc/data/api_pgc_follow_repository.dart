import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/pgc_follow_repository.dart';
import '../domain/pgc_repository.dart';

final class ApiPgcFollowRepository implements PgcFollowRepository {
  ApiPgcFollowRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;

  final PgcClient client;
  final ApiRequests requests;
  final String Function() _scope;

  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  String _requireAccount() {
    final scope = accountScope;
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录后再追番');
    }
    return scope;
  }

  void _checkScope(String scope) {
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
  }

  @override
  Future<bool> isFollowed(PgcSeasonId id, RequestCancellation cancellation) =>
      requests.run((context) async {
        final scope = _requireAccount();
        final followed = await client.isFollowed(id.value, context: context);
        _checkScope(scope);
        return followed;
      }, cancellation: cancellation);

  @override
  Future<void> setFollowed(
    PgcSeasonId id,
    bool followed,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final scope = _requireAccount();
    try {
      await client.setFollowed(id.value, followed, context: context);
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.http,
        ApiFailureCategory.protocol,
      }.contains(error.category)) {
        throw const PgcFollowWriteUncertain();
      }
      rethrow;
    }
    _checkScope(scope);
  }, cancellation: cancellation);
}
