import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../shared/data/dynamic_post_mapper.dart';
import '../domain/dynamic_topic_repository.dart';
import '../domain/dynamic_repository.dart';

final class ApiDynamicTopicRepository implements DynamicTopicRepository {
  ApiDynamicTopicRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final DynamicTopicClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<DynamicTopicDetail> detail(
    String id,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final value = await client.detail(id, context: context);
    return DynamicTopicDetail(
      id: value.id,
      name: value.name,
      description: value.description,
      viewCount: value.viewCount,
      discussCount: value.discussCount,
      creatorId: UserId.tryParse(value.creatorId),
      creatorName: value.creatorName,
      creatorAvatar: value.creatorAvatar,
      favoriteCount: value.favoriteCount,
      isFavorite: value.isFavorite,
    );
  }, cancellation: cancellation);

  Future<void> _write(
    Future<void> Function(ApiRequestContext) action,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    try {
      await action(context);
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
  Future<void> favorite(
    String id,
    bool value,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.favorite(id, value, context: context),
    cancellation,
  );

  @override
  Future<void> report(
    String id,
    String reason,
    RequestCancellation cancellation,
  ) => _write(
    (context) => client.report(id, reason, context: context),
    cancellation,
  );

  @override
  Future<DynamicTopicPage> feed(
    String id, {
    required int sort,
    String? cursor,
    bool folded = false,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final page = await client.feed(
      id,
      sort: sort,
      cursor: cursor,
      folded: folded,
      context: context,
    );
    return DynamicTopicPage(
      posts: page.posts.map(mapDynamicPost).toList(),
      hasMore: page.hasMore,
      nextCursor: page.nextCursor,
      sorts: page.sorts.map((s) => DynamicTopicSort(s.id, s.name)).toList(),
      selectedSort: page.selectedSort,
      foldDescription: page.foldDescription,
    );
  }, cancellation: cancellation);
}
