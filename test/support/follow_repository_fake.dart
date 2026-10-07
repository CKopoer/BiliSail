import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';

class FollowRepositoryFake implements VideoAuthorRepository {
  @override
  String accountScope = 'guest';
  @override
  int sessionEpoch = 0;
  bool following = false;
  Object? failure;
  Completer<void>? pending;
  int reads = 0;
  final writes = <(String, bool)>[];

  @override
  Future<VideoAuthor> load(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async {
    reads++;
    return VideoAuthor(following: following);
  }

  @override
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  ) async {
    writes.add((id.value, following));
    if (failure case final error?) throw error;
    await pending?.future;
    this.following = following;
  }

  @override
  Future<FollowGroupSelection> loadGroups(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async => const FollowGroupSelection(
    groups: [FollowGroup(id: '1', name: '测试分组')],
    selectedIds: {},
  );

  @override
  Future<void> saveGroups(
    VideoAuthorId id,
    Set<String> groupIds,
    RequestCancellation cancellation,
  ) async {}
}
