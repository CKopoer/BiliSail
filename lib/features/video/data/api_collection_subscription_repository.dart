import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/collection_subscription_repository.dart';
import '../domain/video_actions_repository.dart';

final class ApiCollectionSubscriptionRepository
    implements CollectionSubscriptionRepository {
  ApiCollectionSubscriptionRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;

  final CollectionSubscriptionClient client;
  final ApiRequests requests;
  final String Function() _scope;

  @override
  String get accountScope => _scope();

  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<bool> isSubscribed(
    CollectionSubscriptionTarget target,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final scope = accountScope;
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    final result = await client.isSubscribed(
      target.videoId.value,
      aid: target.aid,
      context: context,
    );
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    return result;
  }, cancellation: cancellation);

  @override
  Future<void> setSubscribed(
    CollectionSubscriptionTarget target,
    bool subscribed,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final scope = accountScope;
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    try {
      await client.setSubscribed(
        target.collectionId.value,
        subscribed,
        context: context,
      );
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.http,
        ApiFailureCategory.protocol,
      }.contains(error.category)) {
        throw const UnknownWriteOutcome();
      }
      rethrow;
    }
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
  }, cancellation: cancellation);
}
