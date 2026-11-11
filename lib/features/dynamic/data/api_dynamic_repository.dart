import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../../shared/data/dynamic_post_mapper.dart';
import '../domain/dynamic_repository.dart';
import '../domain/dynamic_poll.dart';
import '../domain/dynamic_poll_repository.dart';

final class ApiDynamicRepository
    implements DynamicRepository, DynamicPollRepository {
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

  @override
  Future<DynamicPoll> poll(String id, RequestCancellation cancellation) =>
      requests.run(
        (context) async => _poll(
          await DynamicPollClient(client.api).detail(id, context: context),
        ),
        cancellation: cancellation,
      );

  @override
  Future<DynamicPoll> vote(
    String id,
    String voterId,
    List<int> choices,
    bool anonymous,
    RequestCancellation cancellation, {
    String? dynamicId,
  }) => _write(
    (context) async => _poll(
      await DynamicPollClient(client.api).vote(
        id: id,
        voterId: voterId,
        choices: choices,
        anonymous: anonymous,
        dynamicId: dynamicId,
        context: context,
      ),
    ),
    cancellation,
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

DynamicPoll _poll(ApiDynamicPoll poll) => DynamicPoll(
  id: poll.id,
  title: poll.title,
  description: poll.description,
  maxChoices: poll.maxChoices,
  endsAt: poll.endsAt,
  joinCount: poll.joinCount,
  options: [
    for (final option in poll.options)
      DynamicPollOption(
        index: option.index,
        text: option.text,
        count: option.count,
        imageUrl: option.imageUrl,
      ),
  ],
  myVotes: poll.myVotes,
);
