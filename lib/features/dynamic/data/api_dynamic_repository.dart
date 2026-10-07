import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../shared/data/dynamic_post_mapper.dart';
import '../domain/dynamic_repository.dart';

final class ApiDynamicRepository implements DynamicRepository {
  ApiDynamicRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final DynamicClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<DynamicPost> detail(String id, RequestCancellation cancellation) =>
      requests.run(
        (context) async =>
            mapDynamicPost(await client.detail(id, context: context)),
        cancellation: cancellation,
      );

  Future<T> _write<T>(
    Future<T> Function(ApiRequestContext) operation,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    try {
      return await operation(context);
    } on ApiFailure catch (error) {
      if (context.cancellation?.isCancelled == true) rethrow;
      if (const {
        ApiFailureCategory.network,
        ApiFailureCategory.timeout,
        ApiFailureCategory.protocol,
        ApiFailureCategory.http,
      }.contains(error.category)) {
        throw const DynamicWriteUncertain();
      }
      rethrow;
    }
  }, cancellation: cancellation);

  @override
  Future<void> like(String id, bool liked, RequestCancellation cancellation) =>
      _write(
        (context) => client.like(id, liked, context: context),
        cancellation,
      );
  @override
  Future<String> repost(
    String id,
    String text,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.repost(id, text, context: context),
    cancellation,
  );
}
