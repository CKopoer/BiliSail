import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/shared/ui/content_section_tabs.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _id = UserId('7');
const _signedIn = AuthState(
  status: AuthStatus.signedIn,
  mid: '7',
  userName: '本人',
);

void main() {
  late _Repository repo;
  late AuthFake auth;
  late ProviderContainer container;
  var containerDisposed = false;
  ProfileState state() => container.read(profileControllerProvider(_id));
  ProfileController controller() =>
      container.read(profileControllerProvider(_id).notifier);
  Future<void> flush() => Future<void>.delayed(Duration.zero);

  setUp(() {
    containerDisposed = false;
    repo = _Repository();
    auth = AuthFake()..state = _signedIn;
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(profileControllerProvider(_id), (_, _) {});
  });
  tearDown(() async {
    if (!containerDisposed) container.dispose();
    await auth.stream.close();
  });

  test(
    'groups load lazily; group paging and other sections remain separate',
    () async {
      await flush();
      expect(repo.groupReads, 0);
      controller().select(ProfileSection.followers);
      await flush();
      expect(repo.groupReads, 0);
      controller().select(ProfileSection.following);
      await flush();
      expect(repo.groupReads, 1);
      expect(state().current.items.single.title, '全部关注用户');
      controller().selectFollowingGroup('1');
      await flush();
      expect(state().current.items.single.title, '分组1用户1');
      await controller().load();
      expect(repo.memberReads, [('1', 1), ('1', 2)]);
      expect(state().current.items.map((entry) => entry.title), [
        '分组1用户1',
        '分组1用户2',
      ]);
      controller().select(ProfileSection.videos);
      await flush();
      controller().select(ProfileSection.following);
      expect(state().followingGroupId, '1');
      expect(state().current.page, 2);
      expect(repo.groupReads, 1);
      controller().selectFollowingGroup(null);
      await flush();
      expect(state().current.items.single.title, '全部关注用户');
      expect(state().current.page, 1);
    },
  );

  test(
    'rapid group switches cancel paging and ignore late success and failure',
    () async {
      controller().select(ProfileSection.following);
      await flush();
      controller().selectFollowingGroup('1');
      await flush();
      final pending = repo.membersPending = Completer<ProfilePage>();
      final old = controller().load();
      final read = repo.memberCancellation;
      repo.membersPending = null;
      controller().selectFollowingGroup('2');
      await flush();
      expect(read?.isCancelled, true);
      pending.completeError(const AppFailure(AppFailureKind.network, '过期错误'));
      await old;
      expect(state().followingGroupId, '2');
      expect(state().current.items.single.title, '分组2用户1');
      expect(state().current.message, isNull);

      final late = repo.membersPending = Completer<ProfilePage>();
      final stale = controller().load(refresh: true);
      repo.membersPending = null;
      controller().selectFollowingGroup(null);
      await flush();
      late.complete(_page('旧分组用户'));
      await stale;
      expect(state().followingGroupId, isNull);
      expect(state().current.items.single.title, '全部关注用户');
    },
  );

  test('group refresh rejects older reads and falls back if selected group disappeared', () async {
    controller().select(ProfileSection.following);
    await flush();
    controller().selectFollowingGroup('1');
    await flush();
    final pending = repo.groupsPending = Completer<List<ProfileFollowGroup>>();
    final old = controller().loadFollowGroups();
    final read = repo.groupsCancellation;
    repo.groupsPending = null;
    repo.groups = const [ProfileFollowGroup(id: '0', name: '默认分组')];
    await controller().loadFollowGroups();
    await flush();
    expect(read?.isCancelled, true);
    expect(state().followingGroupId, isNull);
    expect(state().current.items.single.title, '全部关注用户');
    pending.complete(const [ProfileFollowGroup(id: '1', name: '过期分组')]);
    await old;
    expect(state().followGroups?.single.id, '0');
  });

  test(
    'account changes cancel and discard private group names and members',
    () async {
      controller().select(ProfileSection.following);
      await flush();
      final pending = repo.groupsPending =
          Completer<List<ProfileFollowGroup>>();
      final old = controller().loadFollowGroups();
      final groupRead = repo.groupsCancellation;
      final members = repo.membersPending = Completer<ProfilePage>();
      controller().selectFollowingGroup('1');
      final memberRead = repo.memberCancellation;
      repo.scope = 'user:8';
      repo.epoch++;
      auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '8'));
      await flush();
      expect(groupRead?.isCancelled, true);
      expect(memberRead?.isCancelled, true);
      pending.complete(const [ProfileFollowGroup(id: '99', name: '前账号私密分组')]);
      members.complete(_page('前账号用户'));
      await old;
      await flush();
      expect(state().followGroups, isNull);
      expect(state().followingGroupId, isNull);
      expect(state().followGroupsAvailable, false);
      controller().select(ProfileSection.following);
      await flush();
      expect(state().current.items.single.title, '全部关注用户');
      expect(repo.groupReads, 2);
    },
  );

  test('closing the controller cancels a pending group read', () async {
    await flush();
    repo.groupsPending = Completer<List<ProfileFollowGroup>>();
    controller().select(ProfileSection.following);
    final read = repo.groupsCancellation;
    container.dispose();
    containerDisposed = true;
    expect(read?.isCancelled, true);
    repo.groupsPending!.complete(const []);
    await flush();
  });

  Future<void> mount(
    WidgetTester tester, {
    double width = 375,
    double scale = 1,
    ProfileSection initialSection = ProfileSection.following,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: ProfileScreen(id: _id, initialSection: initialSection),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (width, scale) in [(320.0, 2.0), (900.0, 1.0)]) {
    testWidgets('shared group tabs scroll and select at $width/$scale', (
      tester,
    ) async {
      repo.groups = [
        ...repo.groups,
        for (var i = 3; i <= 18; i++)
          ProfileFollowGroup(id: '$i', name: '兴趣分组$i'),
      ];
      await mount(tester, width: width, scale: scale);
      expect(find.byType(ContentSectionTabs<String>), findsOneWidget);
      expect(find.text('全部关注用户'), findsOneWidget);
      final tab = find.byKey(const ValueKey('profile-follow-group-18'));
      final horizontal = find.descendant(
        of: find.byType(ContentSectionTabs<String>),
        matching: find.byType(SingleChildScrollView),
      );
      await tester.drag(horizontal, const Offset(-3000, 0));
      await tester.pumpAndSettle();
      await tester.tap(tab);
      await tester.pumpAndSettle();
      expect(state().followingGroupId, '18');
      expect(find.text('分组18用户1'), findsOneWidget);
      expect(find.text('全部关注用户'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'group strip retains its state and scroll without refetching on section switches',
    (tester) async {
      repo.groups = [
        ...repo.groups,
        for (var i = 3; i <= 18; i++)
          ProfileFollowGroup(id: '$i', name: '兴趣分组$i'),
      ];
      await mount(tester);
      final strip = find.byType(ContentSectionTabs<String>);
      final stripState = tester.state(strip);
      final scroll = tester
          .widget<SingleChildScrollView>(
            find.descendant(
              of: strip,
              matching: find.byType(SingleChildScrollView),
            ),
          )
          .controller!;
      scroll.jumpTo(420);
      await tester.pumpAndSettle();
      final offset = scroll.offset;
      for (final section in [
        ProfileSection.videos,
        ProfileSection.dynamics,
        ProfileSection.followers,
      ]) {
        controller().select(section);
        await tester.pumpAndSettle();
        expect(stripState.mounted, true);
        expect(strip.hitTestable(), findsNothing);
        expect(repo.groupReads, 1);
        controller().select(ProfileSection.following);
        await tester.pumpAndSettle();
        expect(tester.state(strip), same(stripState));
        expect(scroll.offset, closeTo(offset, .1));
        expect(repo.groupReads, 1);
      }
      await tester.pumpWidget(const SizedBox());
      expect(stripState.mounted, false);
    },
  );

  testWidgets(
    'group strip initializes on first visit and releases on session reset',
    (tester) async {
      await mount(tester, initialSection: ProfileSection.videos);
      final strip = find.byType(
        ContentSectionTabs<String>,
        skipOffstage: false,
      );
      expect(strip, findsNothing);
      expect(repo.groupReads, 0);
      controller().select(ProfileSection.following);
      await tester.pumpAndSettle();
      final stripState = tester.state(strip);
      expect(repo.groupReads, 1);
      controller().select(ProfileSection.videos);
      await tester.pumpAndSettle();
      repo.epoch++;
      auth.emit(
        const AuthState(status: AuthStatus.signedIn, mid: '7', userName: '新会话'),
      );
      await tester.pumpAndSettle();
      expect(stripState.mounted, false);
      expect(strip, findsNothing);
      expect(state().followGroups, isNull);
    },
  );

  testWidgets(
    'group failure keeps all followings usable; retry recovers and empty groups render',
    (tester) async {
      repo.groupsFailure = const AppFailure(AppFailureKind.network, '分组读取失败');
      await mount(tester);
      expect(find.text('全部关注用户'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-follow-groups-retry')),
        findsOneWidget,
      );
      repo.groupsFailure = null;
      await tester.tap(
        find.byKey(const ValueKey('profile-follow-groups-retry')),
      );
      await tester.pumpAndSettle();
      repo.empty = true;
      await tester.tap(find.byKey(const ValueKey('profile-follow-group-0')));
      await tester.pumpAndSettle();
      expect(state().followingGroupId, '0');
      expect(state().current.items, isEmpty);
      expect(find.text('关注暂无公开内容'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('profile-follow-groups-retry')),
        findsNothing,
      );
    },
  );
}

ProfilePage _page(String title, {bool more = false}) => ProfilePage(
  items: [
    ProfileEntry(
      id: title,
      kind: ProfileEntryKind.user,
      title: title,
      userId: const UserId('9'),
    ),
  ],
  hasMore: more,
);

class _Repository implements ProfileRepository, ProfileFollowGroupsRepository {
  String scope = 'user:7';
  int epoch = 1, groupReads = 0;
  bool empty = false;
  List<ProfileFollowGroup> groups = const [
    ProfileFollowGroup(id: '0', name: '默认分组'),
    ProfileFollowGroup(id: '-10', name: '特别关注'),
    ProfileFollowGroup(id: '1', name: '知识'),
    ProfileFollowGroup(id: '2', name: '音乐'),
  ];
  AppFailure? groupsFailure;
  Completer<List<ProfileFollowGroup>>? groupsPending;
  Completer<ProfilePage>? membersPending;
  RequestCancellation? groupsCancellation, memberCancellation;
  final memberReads = <(String, int)>[];

  @override
  String get accountScope => scope;
  @override
  int get sessionEpoch => epoch;
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
  Future<List<ProfileFollowGroup>> loadFollowGroups(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    groupReads++;
    groupsCancellation = cancellation;
    if (groupsFailure case final failure?) throw failure;
    return groupsPending?.future ?? groups;
  }

  @override
  Future<ProfilePage> loadFollowingGroup(
    UserId id,
    String groupId, {
    required int page,
    required RequestCancellation cancellation,
  }) async {
    memberReads.add((groupId, page));
    memberCancellation = cancellation;
    return membersPending?.future ??
        (empty
            ? const ProfilePage(items: [], hasMore: false)
            : _page('分组$groupId用户$page', more: groupId == '1' && page == 1));
  }

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
  }) async => _page(section == ProfileSection.following ? '全部关注用户' : '其他栏目');
}
