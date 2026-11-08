import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';
import 'profile_following_fakes.dart';

const id = UserId('7');
const signedIn = AuthState(status: AuthStatus.signedIn, mid: '7');
void main() {
  late FollowingRepository repo;
  late AuthFake auth;
  late ProviderContainer container;
  var disposed = false;
  ProfileController controller() =>
      container.read(profileControllerProvider(id).notifier);
  ProfileState state() => container.read(profileControllerProvider(id));
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    disposed = false;
    repo = FollowingRepository();
    auth = AuthFake()..state = signedIn;
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(profileControllerProvider(id), (_, _) {});
    await flush();
    controller().select(ProfileSection.following);
    await flush();
  });
  tearDown(() async {
    if (!disposed) container.dispose();
    await auth.stream.close();
  });

  test(
    'search is remote, paged and separate from video filters and groups',
    () async {
      controller().filter(keyword: '视频关键字');
      controller().selectFollowingGroup('1');
      await flush();
      controller().searchFollowing(' 搜索用户 ');
      await flush();
      expect(state().keyword, '视频关键字');
      expect(state().followingKeyword, '搜索用户');
      expect(state().followingGroupId, isNull);
      await controller().load();
      expect(repo.queries.takeLast(2), [
        ('搜索用户', '', false, 1),
        ('搜索用户', '', false, 2),
      ]);
      expect(state().current.items.map((e) => e.title), ['搜索用户-1', '搜索用户-2']);
      controller().selectFollowingGroup('1');
      await flush();
      expect(state().followingKeyword, '');
      expect(state().current.items.single.title, '分组1-1');
    },
  );

  test(
    'rapid search, sort and blacklist changes cancel and reject old responses',
    () async {
      final pending = repo.pendingRead = Completer<ProfilePage>();
      controller().searchFollowing('旧查询');
      final read = repo.readCancellation;
      repo.pendingRead = null;
      controller().orderFollowing('attention');
      await flush();
      expect(read?.isCancelled, true);
      pending.completeError(const AppFailure(AppFailureKind.network, '旧错误'));
      await flush();
      expect(state().current.message, isNull);
      expect(state().followingKeyword, '');
      expect(repo.queries.last, ('', 'attention', false, 1));
      final late = repo.pendingRead = Completer<ProfilePage>();
      final old = controller().load();
      final oldRead = repo.readCancellation;
      repo.pendingRead = null;
      controller().showFollowingBlacklist(true);
      await flush();
      expect(oldRead?.isCancelled, true);
      late.complete(followingPage('迟到的关注'));
      await old;
      expect(state().showBlacklist, true);
      expect(state().current.items.single.title, '黑名单-1');
      await controller().load();
      expect(repo.queries.last, ('', 'attention', true, 2));
      controller().select(ProfileSection.followers);
      await flush();
      controller().select(ProfileSection.following);
      expect(state().showBlacklist, true);
      expect(state().current.page, 2);
    },
  );

  test('group writes reconcile names, selection and ordering; reserved groups cannot change', () async {
    expect(
      await controller().editFollowGroup(FollowGroupEdit.create, name: '新分组'),
      true,
    );
    expect(state().followGroups?.last.name, '新分组');
    controller().selectFollowingGroup('1');
    await flush();
    expect(
      await controller().editFollowGroup(
        FollowGroupEdit.rename,
        groupId: '1',
        name: '改名',
      ),
      true,
    );
    expect(state().followingGroupId, '1');
    expect(
      await controller().editFollowGroup(FollowGroupEdit.delete, groupId: '1'),
      true,
    );
    expect(state().followingGroupId, isNull);
    expect(state().followingUncertain, false);
    expect(state().current.items.single.title, '关注-1');
    expect(await controller().sortFollowGroups(['3', '2']), true);
    expect(state().followGroups?.map((e) => e.id), ['0', '-10', '3', '2']);
    final writes = repo.edits.length;
    expect(
      await controller().editFollowGroup(FollowGroupEdit.delete, groupId: '0'),
      false,
    );
    expect(
      await controller().editFollowGroup(
        FollowGroupEdit.rename,
        groupId: '-10',
        name: '改名',
      ),
      false,
    );
    expect(
      await controller().editFollowGroup(FollowGroupEdit.create, name: ''),
      false,
    );
    expect(await controller().sortFollowGroups(['2', '2']), false);
    expect(repo.edits.length, writes);
  });

  test(
    'write single flight and unknown outcomes require read reconciliation',
    () async {
      final pending = repo.pendingWrite = Completer<void>();
      final first = controller().editFollowGroup(
        FollowGroupEdit.create,
        name: '一次',
      );
      expect(state().followingBusy, true);
      expect(
        await controller().editFollowGroup(FollowGroupEdit.create, name: '重复'),
        false,
      );
      pending.completeError(const AppFailure(AppFailureKind.timeout, '超时'));
      expect(await first, false);
      expect(repo.edits.length, 1);
      expect(state().followingUncertain, true);
      expect(
        await controller().setFollowingBlocked(const UserId('9'), true),
        false,
      );
      repo.pendingWrite = null;
      repo.readFailure = const AppFailure(AppFailureKind.network, '读失败');
      await controller().refreshFollowingManagement();
      expect(state().followingUncertain, true);
      repo.readFailure = null;
      await controller().refreshFollowingManagement();
      expect(state().followingUncertain, false);
      expect(
        await controller().setFollowingBlocked(const UserId('9'), true),
        true,
      );
      expect(repo.blocks, [(const UserId('9'), true)]);
      expect(await controller().setFollowingBlocked(id, true), false);
    },
  );

  for (final operation in ['create', 'rename', 'delete', 'sort']) {
    test(
      '$operation refreshes group data and retained members after changing section',
      () async {
        controller().selectFollowingGroup('1');
        await flush();
        final memberReads = repo.memberQueries.length;
        final allReads = repo.queries.length;
        final groupReads = repo.groupReads;
        final pending = repo.pendingWrite = Completer<void>();
        final write = switch (operation) {
          'create' => controller().editFollowGroup(
            FollowGroupEdit.create,
            name: '新增',
          ),
          'rename' => controller().editFollowGroup(
            FollowGroupEdit.rename,
            groupId: '1',
            name: '新名称',
          ),
          'delete' => controller().editFollowGroup(
            FollowGroupEdit.delete,
            groupId: '1',
          ),
          _ => controller().sortFollowGroups(['2', '1']),
        };
        controller().select(ProfileSection.followers);
        await flush();
        final followers = state().lists[ProfileSection.followers];
        repo.contentRevision = 1;
        pending.complete();
        expect(await write, true);
        expect(state().section, ProfileSection.followers);
        expect(
          identical(state().lists[ProfileSection.followers], followers),
          true,
        );
        expect(repo.groupReads, groupReads + 1);
        final following = state().lists[ProfileSection.following]!;
        expect(following.page, 1);
        expect(
          following.items.single.title,
          operation == 'delete' ? '关注-1-r1' : '分组1-1-r1',
        );
        expect(
          repo.memberQueries.length,
          memberReads + (operation == 'delete' ? 0 : 1),
        );
        expect(repo.queries.length, allReads + (operation == 'delete' ? 1 : 0));
        expect(state().followingUncertain, false);
        switch (operation) {
          case 'create':
            expect(state().followGroups?.last.name, '新增');
          case 'rename':
            expect(
              state().followGroups?.firstWhere((group) => group.id == '1').name,
              '新名称',
            );
          case 'delete':
            expect(
              state().followGroups?.any((group) => group.id == '1'),
              false,
            );
            expect(state().followingGroupId, isNull);
          case 'sort':
            expect(state().followGroups?.map((group) => group.id), [
              '0',
              '-10',
              '2',
              '1',
            ]);
        }
        final readsAfterRefresh = (
          repo.memberQueries.length,
          repo.queries.length,
        );
        controller().select(ProfileSection.following);
        expect(state().current, same(following));
        expect((
          repo.memberQueries.length,
          repo.queries.length,
        ), readsAfterRefresh);
      },
    );
  }

  test(
    'deleting selected group refreshes fallback content exactly once',
    () async {
      controller().selectFollowingGroup('1');
      await flush();
      final allReads = repo.queries.length;
      final memberReads = repo.memberQueries.length;
      expect(
        await controller().editFollowGroup(
          FollowGroupEdit.delete,
          groupId: '1',
        ),
        true,
      );
      expect(repo.queries.length, allReads + 1);
      expect(repo.memberQueries.length, memberReads);
      expect(state().current.items.single.title, '关注-1');
    },
  );

  test(
    'group refresh cancels pre-write paging before awaiting group data',
    () async {
      final pendingPage = repo.pendingRead = Completer<ProfilePage>();
      final paging = controller().load();
      final oldRead = repo.readCancellation;
      repo.pendingRead = null;
      final groups = repo.pendingGroups = Completer<List<ProfileFollowGroup>>();
      repo.contentRevision = 1;
      final write = controller().editFollowGroup(
        FollowGroupEdit.create,
        name: '新增',
      );
      await flush();
      expect(oldRead?.isCancelled, true);
      pendingPage.complete(followingPage('操作前的分页内容'));
      await paging;
      expect(
        state().current.items.any((entry) => entry.title == '操作前的分页内容'),
        false,
      );
      groups.complete(repo.groups);
      expect(await write, true);
      expect(state().current.items.single.title, '关注-1-r1');
    },
  );

  test('account transition cancels pending reads and writes and clears private state', () async {
    final pending = repo.pendingWrite = Completer<void>();
    final write = controller().setFollowingBlocked(const UserId('9'), false);
    final writeCancellation = repo.writeCancellation;
    final late = repo.pendingRead = Completer<ProfilePage>();
    controller().searchFollowing('私密查询');
    final read = repo.readCancellation;
    repo.accountScope = 'user:8';
    repo.sessionEpoch++;
    auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await flush();
    expect(writeCancellation?.isCancelled, true);
    expect(read?.isCancelled, true);
    pending.complete();
    late.complete(followingPage('旧账号数据'));
    expect(await write, false);
    await flush();
    expect(state().followingManagementAvailable, false);
    expect(state().followingKeyword, '');
    expect(state().followGroups, isNull);
    expect(state().followingBusy, false);
    expect(
      await controller().editFollowGroup(FollowGroupEdit.create, name: '非法'),
      false,
    );
  });

  test(
    'closing page cancels both operations and ignores their completions',
    () async {
      final pending = repo.pendingWrite = Completer<void>();
      final write = controller().setFollowingBlocked(const UserId('9'), true);
      final writeCancellation = repo.writeCancellation;
      final late = repo.pendingRead = Completer<ProfilePage>();
      controller().searchFollowing('查询');
      final read = repo.readCancellation;
      container.dispose();
      disposed = true;
      expect(writeCancellation?.isCancelled, true);
      expect(read?.isCancelled, true);
      pending.complete();
      late.complete(followingPage('关闭后数据'));
      expect(await write, false);
      await flush();
    },
  );

  test('confirmed group changes survive stale reads until the server acknowledges them', () async {
    repo.staleGroups = List.of(repo.groups);
    expect(
      await controller().editFollowGroup(FollowGroupEdit.create, name: '新增'),
      true,
    );
    expect(state().followGroups?.last.id, '3');
    await controller().loadFollowGroups();
    expect(state().followGroups?.last.id, '3');
    // Once a read acknowledges creation, later external edits are accepted.
    repo.staleGroups = null;
    await controller().loadFollowGroups();
    repo.groups = [
      for (final group in repo.groups)
        if (group.id == '3')
          const ProfileFollowGroup(id: '3', name: '其他客户端修改')
        else
          group,
    ];
    await controller().loadFollowGroups();
    expect(state().followGroups?.last.name, '其他客户端修改');
    repo.staleGroups = List.of(repo.groups);
    expect(
      await controller().editFollowGroup(
        FollowGroupEdit.rename,
        groupId: '3',
        name: '重命名',
      ),
      true,
    );
    expect(state().followGroups?.last.name, '重命名');
    expect(await controller().sortFollowGroups(['3', '2', '1']), true);
    expect(
      state().followGroups
          ?.where((group) => group.isEditable)
          .map((group) => group.id),
      ['3', '2', '1'],
    );
    expect(
      await controller().editFollowGroup(FollowGroupEdit.delete, groupId: '3'),
      true,
    );
    await controller().loadFollowGroups();
    expect(state().followGroups?.any((group) => group.id == '3'), false);
    repo.staleGroups = null;
    await controller().loadFollowGroups();
    expect(state().followGroups?.any((group) => group.id == '3'), false);
  });
}

extension<T> on Iterable<T> {
  Iterable<T> takeLast(int count) => skip(length - count);
}
