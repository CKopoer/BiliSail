import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_poll.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_poll_repository.dart';

final pollNow = DateTime.utc(2026, 11, 11);
DynamicPoll pollFixture({
  int maxChoices = 2,
  Set<int> myVotes = const {},
  bool ended = false,
  bool images = false,
}) => DynamicPoll(
  id: '42',
  title: '测试投票标题',
  description: '投票说明',
  maxChoices: maxChoices,
  endsAt: pollNow.add(Duration(days: ended ? -1 : 1)),
  joinCount: 3,
  options: [
    const DynamicPollOption(index: 4, text: '选项甲', count: 1),
    DynamicPollOption(
      index: 9,
      text: '选项乙',
      count: 2,
      imageUrl: images ? Uri.https('i0.hdslb.com', '/fixture.jpg') : null,
    ),
    const DynamicPollOption(index: 12, text: '选项丙', count: 0),
  ],
  myVotes: myVotes,
);

final class DynamicPollRepositoryFake implements DynamicPollRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  DynamicPoll loaded = pollFixture();
  Completer<DynamicPoll>? pendingRead, pendingVote;
  Object? readError, voteError;
  RequestCancellation? lastCancellation;
  int reads = 0;
  final votes =
      <
        ({
          String id,
          String voterId,
          List<int> choices,
          bool anonymous,
          String? dynamicId,
        })
      >[];
  @override
  Future<DynamicPoll> poll(String id, RequestCancellation cancellation) async {
    reads++;
    lastCancellation = cancellation;
    if (readError case final error?) throw error;
    return pendingRead?.future ?? loaded;
  }

  @override
  Future<DynamicPoll> vote(
    String id,
    String voterId,
    List<int> choices,
    bool anonymous,
    RequestCancellation cancellation, {
    String? dynamicId,
  }) async {
    votes.add((
      id: id,
      voterId: voterId,
      choices: choices,
      anonymous: anonymous,
      dynamicId: dynamicId,
    ));
    lastCancellation = cancellation;
    if (voteError case final error?) throw error;
    return pendingVote?.future ?? pollFixture(myVotes: choices.toSet());
  }
}
