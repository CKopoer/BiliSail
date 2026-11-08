import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';

class FollowingRepository
    implements
        ProfileRepository,
        ProfileFollowGroupsRepository,
        ProfileFollowingManagementRepository {
  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  final queries = <(String, String, bool, int)>[];
  final edits = <(FollowGroupEdit, String?, String)>[];
  final blocks = <(UserId, bool)>[];
  final memberQueries = <(String, int)>[];
  List<String>? sorted;
  int groupReads = 0;
  int contentRevision = 0;
  List<ProfileFollowGroup> groups = [
    const ProfileFollowGroup(id: '0', name: '默认分组'),
    const ProfileFollowGroup(id: '-10', name: '特别关注'),
    const ProfileFollowGroup(id: '1', name: '知识'),
    const ProfileFollowGroup(id: '2', name: '音乐'),
  ];
  List<ProfileFollowGroup>? staleGroups;
  Completer<ProfilePage>? pendingRead;
  Completer<List<ProfileFollowGroup>>? pendingGroups;
  Completer<void>? pendingWrite;
  RequestCancellation? readCancellation, writeCancellation;
  AppFailure? writeFailure, readFailure;

  @override
  Future<ProfilePage> loadManagedFollowing(
    UserId owner, {
    required int page,
    String keyword = '',
    String order = '',
    bool blacklist = false,
    required RequestCancellation cancellation,
  }) async {
    queries.add((keyword, order, blacklist, page));
    readCancellation = cancellation;
    if (readFailure case final failure?) throw failure;
    return pendingRead?.future ??
        followingPage(
          '${blacklist
              ? '黑名单'
              : keyword.isEmpty
              ? '关注'
              : keyword}-$page$_revision',
          more: page < 2,
        );
  }

  @override
  Future<ProfileFollowGroup?> editFollowGroup(
    UserId owner,
    FollowGroupEdit edit, {
    String? groupId,
    String name = '',
    required RequestCancellation cancellation,
  }) async {
    edits.add((edit, groupId, name));
    await _write(cancellation);
    groups = switch (edit) {
      FollowGroupEdit.create => [
        ...groups,
        ProfileFollowGroup(id: '3', name: name),
      ],
      FollowGroupEdit.rename => [
        for (final group in groups)
          if (group.id == groupId)
            ProfileFollowGroup(id: group.id, name: name)
          else
            group,
      ],
      FollowGroupEdit.delete =>
        groups.where((group) => group.id != groupId).toList(),
    };
    return edit == FollowGroupEdit.create ? groups.last : null;
  }

  Future<void> _write(RequestCancellation cancellation) async {
    writeCancellation = cancellation;
    if (writeFailure case final failure?) throw failure;
    if (pendingWrite case final pending?) await pending.future;
  }

  @override
  Future<void> sortFollowGroups(
    UserId owner,
    List<String> ids, {
    required RequestCancellation cancellation,
  }) async {
    sorted = ids;
    await _write(cancellation);
    groups = [
      for (final group in groups)
        if (!group.isEditable) group,
      for (final id in ids) groups.firstWhere((group) => group.id == id),
    ];
  }

  @override
  Future<void> setFollowingBlocked(
    UserId owner,
    UserId target,
    bool blocked, {
    required RequestCancellation cancellation,
  }) async {
    blocks.add((target, blocked));
    await _write(cancellation);
  }

  @override
  Future<List<ProfileFollowGroup>> loadFollowGroups(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    groupReads++;
    return pendingGroups?.future ?? staleGroups ?? groups;
  }

  @override
  Future<ProfilePage> loadFollowingGroup(
    UserId id,
    String groupId, {
    required int page,
    required RequestCancellation cancellation,
  }) async {
    memberQueries.add((groupId, page));
    return followingPage('分组$groupId-$page$_revision');
  }

  String get _revision => contentRevision == 0 ? '' : '-r$contentRevision';
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '本人');
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => null;
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    ProfileCollectionId? collection,
    required RequestCancellation cancellation,
  }) async => const ProfilePage(items: [], hasMore: false);
}

ProfilePage followingPage(String title, {bool more = false}) => ProfilePage(
  items: [
    ProfileEntry(
      id: title,
      kind: ProfileEntryKind.user,
      title: title,
      subtitle: '简单简介',
      userId: const UserId('9'),
    ),
  ],
  hasMore: more,
);
