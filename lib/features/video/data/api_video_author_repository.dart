import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/video_actions_repository.dart';
import '../domain/video_author_repository.dart';

final class ApiVideoAuthorRepository implements VideoAuthorRepository {
  ApiVideoAuthorRepository(
    this.client,
    this.groupClient,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final VideoAuthorClient client;
  final FollowGroupClient groupClient;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;

  @override
  Future<VideoAuthor> load(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final author = await client.load(id.value, context: context);
    return VideoAuthor(
      following: author.following,
      followerCount: author.followerCount,
      likeCount: author.likeCount,
    );
  }, cancellation: cancellation);

  @override
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    try {
      await client.follow(id.value, following, context: context);
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
  }, cancellation: cancellation);

  @override
  Future<FollowGroupSelection> loadGroups(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    final groups = await groupClient.groups(context: context);
    final selected = await groupClient.membership(id.value, context: context);
    return FollowGroupSelection(
      groups: List.unmodifiable(
        groups.map((group) => FollowGroup(id: group.id, name: group.name)),
      ),
      selectedIds: Set.unmodifiable(selected),
    );
  }, cancellation: cancellation);

  @override
  Future<void> saveGroups(
    VideoAuthorId id,
    Set<String> groupIds,
    RequestCancellation cancellation,
  ) => requests.run((context) async {
    try {
      await groupClient.save(id.value, groupIds, context: context);
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
  }, cancellation: cancellation);
}
