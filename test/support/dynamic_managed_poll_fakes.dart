import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_poll_repository.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_poll.dart';

DynamicPoll sampleDynamicPoll({
  List<int> votes = const [],
  DateTime? endsAt,
  int maxChoices = 2,
}) => DynamicPoll(
  id: '123',
  title: '周末去哪儿',
  description: '一起选择',
  endsAt: endsAt ?? DateTime.now().add(const Duration(days: 1)),
  maxChoices: maxChoices,
  joinCount: 10,
  myVotes: votes.toSet(),
  options: const [
    DynamicPollOption(index: 1, text: '公园', count: 6),
    DynamicPollOption(index: 2, text: '海边', count: 3),
    DynamicPollOption(index: 3, text: '书店', count: 1),
  ],
);

class DynamicPollFake
    implements DynamicPollRepository, DynamicPollSocialRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  DynamicPoll value = sampleDynamicPoll();
  final votes =
      <
        ({
          String id,
          String mid,
          List<int> choices,
          bool anonymous,
          String? dynamicId,
        })
      >[];
  RequestCancellation? lastRequest;
  Completer<DynamicPoll>? pendingLoad, pendingVote;
  Object? loadError, voteError;
  @override
  Future<DynamicPoll> poll(String id, RequestCancellation c) async {
    lastRequest = c;
    if (loadError case final e?) throw e;
    return pendingLoad?.future ?? value;
  }

  @override
  Future<List<DynamicPollFollowee>> followees(
    String id,
    RequestCancellation c,
  ) async => [
    const DynamicPollFollowee(UserId('8'), '关注的人', [1], null),
  ];
  @override
  Future<DynamicPoll> vote(
    String id,
    String mid,
    List<int> choices,
    bool anonymous,
    RequestCancellation c, {
    String? dynamicId,
  }) async {
    lastRequest = c;
    votes.add((
      id: id,
      mid: mid,
      choices: List.of(choices),
      anonymous: anonymous,
      dynamicId: dynamicId,
    ));
    if (voteError case final e?) throw e;
    return pendingVote?.future ?? sampleDynamicPoll(votes: choices);
  }
}
