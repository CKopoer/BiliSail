import 'package:bilisail/features/video/application/video_author_controller.dart';

import '../../support/follow_repository_fake.dart';

import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/core/platform/external_links.dart';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/features/profile/presentation/profile_video_card.dart';

const id = UserId('7');
const entry = ProfileEntry(
  id: 'a',
  kind: ProfileEntryKind.user,
  title: '用户甲',
  userId: UserId('9'),
);
void main() {
  late _Repo repo;
  late _Auth auth;
  late ProviderContainer container;
  late ProfileController controller;
  ProfileState state() => container.read(profileControllerProvider(id));
  setUp(() async {
    repo = _Repo();
    auth = _Auth();
    container = ProviderContainer(
      overrides: [
        videoAuthorRepositoryProvider.overrideWithValue(FollowRepositoryFake()),
        profileRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
    container.listen(profileControllerProvider(id), (_, _) {});
    controller = container.read(profileControllerProvider(id).notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    auth.stream.close();
  });
  testWidgets('space dynamic and forwarded live cards open the room callback', (
    tester,
  ) async {
    final opened = <RoomId>[], browser = <Uri>[];
    final live = DynamicPost(
      id: '91',
      linkTitle: '空间直播间',
      linkUrl: Uri.parse('https://live.bilibili.com/12'),
    );
    for (final forwarded in [false, true]) {
      repo.items = [
        ProfileEntry(
          id: '90',
          kind: ProfileEntryKind.dynamic,
          title: '',
          dynamicPost: forwarded ? DynamicPost(id: '90', original: live) : live,
        ),
      ];
      repo.hasMore = false;
      controller.select(ProfileSection.dynamics);
      await controller.load(refresh: true);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [
              externalLinkOpenerProvider.overrideWithValue((uri) async {
                browser.add(uri);
                return true;
              }),
            ],
            child: MaterialApp(
              home: Scaffold(
                body: ProfileScreen(
                  id: id,
                  initialSection: ProfileSection.dynamics,
                  onOpenLiveRoom: opened.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('空间直播间'));
      await tester.tap(find.text('空间直播间'));
      await tester.pumpAndSettle();
    }
    expect(opened, [const RoomId('12'), const RoomId('12')]);
    expect(browser, isEmpty);
    expect(tester.takeException(), isNull);
  });
  test(
    'details failure preserves the basic card and list; retry recovers',
    () async {
      repo.detailsFailure = const AppFailure(AppFailureKind.network, '资料失败');
      await controller.loadDetails();
      expect(state().detailsMessage, '资料失败');
      expect(state().profile?.name, '个人主页');
      expect(state().current.items, [entry]);
      repo.detailsFailure = null;
      await controller.loadDetails();
      expect(state().details?.gender, '保密');
      expect(state().detailsMessage, isNull);
    },
  );
  test('details refresh and account change reject late enrichment', () async {
    final pending = repo.detailsPending = Completer<ProfileSpaceDetails>();
    final old = controller.loadDetails();
    final read = repo.detailsRead;
    repo.detailsPending = null;
    await controller.loadDetails();
    expect(read?.isCancelled, true);
    pending.complete(const ProfileSpaceDetails(gender: '旧资料'));
    await old;
    expect(state().details?.gender, '保密');
    final accountPending = repo.detailsPending =
        Completer<ProfileSpaceDetails>();
    final accountRead = controller.loadDetails();
    final cancellation = repo.detailsRead;
    repo.detailsPending = null;
    repo.epoch++;
    auth.emit(const AuthState());
    await Future<void>.delayed(Duration.zero);
    expect(cancellation?.isCancelled, true);
    accountPending.complete(const ProfileSpaceDetails(gender: '上个账号资料'));
    await accountRead;
    expect(state().details?.gender, '保密');
  });
  test(
    'collections keep an independent folder path and cancel old archives',
    () async {
      controller.openFolder(
        const ProfileEntry(
          id: '55',
          kind: ProfileEntryKind.folder,
          title: '收藏夹',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      final pending = repo.pending = Completer<ProfilePage>();
      controller.openCollection(
        const ProfileEntry(
          id: 'season:1',
          kind: ProfileEntryKind.collection,
          title: '旧合集',
          collection: ProfileCollectionId('1', isSeries: false),
        ),
      );
      final read = repo.read;
      repo.pending = null;
      repo.items = const [];
      controller.openCollection(
        const ProfileEntry(
          id: 'series:1',
          kind: ProfileEntryKind.collection,
          title: '新系列',
          collection: ProfileCollectionId('1', isSeries: true),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(read?.isCancelled, true);
      pending.complete(const ProfilePage(items: [entry], hasMore: false));
      await Future<void>.delayed(Duration.zero);
      expect(
        state().collection,
        const ProfileCollectionId('1', isSeries: true),
      );
      expect(state().current.items, isEmpty);
      expect(state().folderId, '55');
      expect(repo.collection, state().collection);
      controller.closeCollection();
      await Future<void>.delayed(Duration.zero);
      expect(state().collection, isNull);
      expect(state().folderId, '55');
      controller.select(ProfileSection.folders);
      expect(state().folderTitle, '收藏夹');
    },
  );
  test('refresh cancels pagination and ignores its late response', () async {
    final pending = Completer<ProfilePage>();
    repo.pending = pending;
    final pagination = controller.load();
    final read = repo.read;
    repo.pending = null;
    repo.items = const [];
    await controller.load(refresh: true);
    expect(read?.isCancelled, true);
    pending.complete(const ProfilePage(items: [entry], hasMore: false));
    await pagination;
    expect(state().current.items, isEmpty);
  });
  test('new sort and search supersede old query response', () async {
    final pending = Completer<ProfilePage>();
    repo.pending = pending;
    final old = controller.load(refresh: true);
    repo.pending = null;
    repo.items = const [];
    controller.filter(order: 'click', keyword: '新投稿');
    await Future<void>.delayed(Duration.zero);
    pending.complete(const ProfilePage(items: [entry], hasMore: true));
    await old;
    expect(state().keyword, '新投稿');
    expect(state().order, 'click');
    expect(state().current.items, isEmpty);
  });
  test('new profile refresh rejects old profile response', () async {
    final pending = Completer<UserProfile>();
    repo.profilePending = pending;
    final old = controller.loadProfile();
    final read = repo.profileRead;
    repo.profilePending = null;
    await controller.loadProfile();
    expect(read?.isCancelled, true);
    pending.complete(const UserProfile(id: id, name: '迟到资料'));
    await old;
    expect(state().profile?.name, '个人主页');
  });
  test(
    'live lookup failures preserve profile and list, retry restores room',
    () async {
      repo.liveFailure = const AppFailure(AppFailureKind.network, '直播查询失败');
      await controller.loadLiveRoom();
      expect(state().liveRoomMessage, '直播查询失败');
      expect(state().profile?.name, '个人主页');
      expect(state().current.items, isNotEmpty);
      repo.liveFailure = null;
      repo.liveRoom = const ProfileLiveRoom(id: RoomId('1024'), isLive: true);
      await controller.loadLiveRoom();
      expect(state().liveRoom?.id, const RoomId('1024'));
      expect(state().liveRoomMessage, isNull);
    },
  );
  test(
    'live refresh cancels old lookup and removes a room that was closed',
    () async {
      final pending = Completer<ProfileLiveRoom?>();
      repo.livePending = pending;
      final old = controller.loadLiveRoom();
      final read = repo.liveRead;
      repo.livePending = null;
      repo.liveRoom = const ProfileLiveRoom(id: RoomId('1024'), isLive: false);
      await controller.loadLiveRoom();
      expect(read?.isCancelled, true);
      pending.complete(const ProfileLiveRoom(id: RoomId('999'), isLive: true));
      await old;
      expect(state().liveRoom?.id, const RoomId('1024'));
      repo.liveRoom = null;
      await controller.refresh();
      expect(state().liveRoom, isNull);
    },
  );
  test(
    'account changes cancel live lookup and discard its late room',
    () async {
      final pending = Completer<ProfileLiveRoom?>();
      repo.livePending = pending;
      final old = controller.loadLiveRoom();
      final read = repo.liveRead;
      repo.livePending = null;
      repo.epoch++;
      auth.emit(const AuthState());
      await Future<void>.delayed(Duration.zero);
      expect(read?.isCancelled, true);
      pending.complete(const ProfileLiveRoom(id: RoomId('999'), isLive: true));
      await old;
      expect(state().liveRoom, isNull);
    },
  );
  test('closing a profile cancels its live lookup', () async {
    final pending = Completer<ProfileLiveRoom?>();
    repo.livePending = pending;
    final old = controller.loadLiveRoom();
    final read = repo.liveRead;
    container.dispose();
    expect(read?.isCancelled, true);
    pending.complete(const ProfileLiveRoom(id: RoomId('999'), isLive: true));
    await old;
  });
  test('profile failure does not remove list and list reload preserves profile error', () async {
    repo.profileFailure = const AppFailure(AppFailureKind.network, '资料加载失败');
    await controller.loadProfile();
    await controller.load(refresh: true);
    expect(state().current.items, isNotEmpty);
    expect(state().profileMessage, '资料加载失败');
    expect(state().profileLoading, false);
    repo.profileFailure = null;
    await controller.loadProfile();
    expect(state().profileMessage, isNull);
  });
  testWidgets('real videos use responsive lazy columns and navigation', (
    tester,
  ) async {
    const video = VideoSummary(
      id: VideoId('BV1234567890'),
      title: '真实投稿',
      coverUrl: '',
      author: '作者',
      duration: Duration(seconds: 20),
    );
    repo.items = List.generate(
      30,
      (index) => ProfileEntry(
        id: '$index',
        kind: ProfileEntryKind.video,
        title: '投稿',
        video: video,
      ),
    );
    await controller.load(refresh: true);
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    VideoSummary? opened;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: ProfileScreen(id: id, onOpenVideo: (value) => opened = value),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final grid = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      3,
    );
    expect(find.text('真实投稿').evaluate().length, lessThan(30));
    await tester.tap(find.text('真实投稿').first);
    expect(opened?.id, video.id);
    await tester.binding.setSurfaceSize(const Size(375, 900));
    await tester.pumpAndSettle();
    final narrow = tester.widget<SliverGrid>(find.byType(SliverGrid));
    expect(
      (narrow.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount)
          .crossAxisCount,
      1,
    );
    expect(tester.takeException(), isNull);
  });
  test(
    'account transition clears private data and cancels late reads',
    () async {
      final pending = Completer<ProfilePage>();
      repo.pending = pending;
      final loading = controller.load();
      final read = repo.read;
      repo.pending = null;
      repo.items = const [];
      repo.epoch++;
      auth.emit(const AuthState());
      await Future<void>.delayed(Duration.zero);
      expect(read?.isCancelled, true);
      pending.complete(const ProfilePage(items: [entry], hasMore: false));
      await loading;
      expect(state().current.items, isEmpty);
    },
  );
  test(
    'pagination deduplicates and section switches preserve results',
    () async {
      await controller.load();
      expect(state().current.items.length, 1);
      controller.select(ProfileSection.followers);
      await Future<void>.delayed(Duration.zero);
      controller.select(ProfileSection.videos);
      expect(state().current.page, 2);
      expect(state().current.items.length, 1);
    },
  );
  test(
    'bounded lists stop at 500 entries and disposal cancels reads',
    () async {
      repo.items = List.generate(
        510,
        (index) => ProfileEntry(
          id: '$index',
          kind: ProfileEntryKind.user,
          title: '$index',
        ),
      );
      await controller.load(refresh: true);
      expect(state().current.items.length, 500);
      expect(state().current.hasMore, false);
      final pending = Completer<ProfilePage>();
      repo.pending = pending;
      final load = controller.load(refresh: true);
      final read = repo.read;
      container.dispose();
      expect(read?.isCancelled, true);
      pending.complete(const ProfilePage(items: [], hasMore: false));
      await load;
    },
  );
  testWidgets('list error keeps profile and offers retry', (tester) async {
    repo.failure = const AppFailure(AppFailureKind.permission, '此列表不可见');
    await controller.load(refresh: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ProfileScreen(id: id)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('此列表不可见'), findsOneWidget);
    expect(find.text('个人主页'), findsOneWidget);
    repo.failure = null;
    repo.hasMore = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('用户甲'), findsOneWidget);
  });
  for (final section in [
    ProfileSection.following,
    ProfileSection.followers,
    ProfileSection.folders,
    ProfileSection.bangumi,
    ProfileSection.cinema,
  ]) {
    testWidgets(
      'hidden ${section.name} is a privacy state and can be refreshed',
      (tester) async {
        controller.select(section);
        await tester.pump();
        expect(state().current.items, isNotEmpty);
        repo.isHidden = true;
        await controller.load();
        expect(state().current.items, isEmpty);
        expect(state().current.isHidden, isTrue);
        expect(state().current.hasMore, isFalse);
        expect(state().current.message, isNull);
        final reads = repo.listReads;
        await controller.load();
        expect(repo.listReads, reads);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: ProfileScreen(id: id, initialSection: section),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final label = switch (section) {
          ProfileSection.following => '关注',
          ProfileSection.followers => '粉丝',
          ProfileSection.folders => '收藏夹',
          ProfileSection.bangumi => '追番',
          ProfileSection.cinema => '追剧',
          _ => throw StateError('Unexpected section'),
        };
        expect(find.text('该用户未公开$label列表'), findsOneWidget);
        expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
        expect(find.text('重试'), findsNothing);
        expect(find.text('$label暂无公开内容'), findsNothing);
        expect(find.text('个人主页'), findsOneWidget);
        repo.isHidden = false;
        await controller.refresh();
        await tester.pumpAndSettle();
        expect(state().current.isHidden, isFalse);
        expect(find.text('用户甲'), findsOneWidget);
        expect(find.text('该用户未公开$label列表'), findsNothing);
      },
    );
  }
  test('a late hidden result cannot replace a newer public result', () async {
    final pending = Completer<ProfilePage>();
    repo.pending = pending;
    final old = controller.load(refresh: true);
    repo.pending = null;
    await controller.load(refresh: true);
    pending.complete(const ProfilePage.hidden());
    await old;
    expect(state().current.isHidden, isFalse);
    expect(state().current.items, isNotEmpty);
  });
  testWidgets('user navigation and narrow enlarged layout', (tester) async {
    UserId? opened;
    await tester.binding.setSurfaceSize(const Size(375, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(375, 900),
              textScaler: TextScaler.linear(1.5),
            ),
            child: Scaffold(
              body: ProfileScreen(
                id: id,
                onOpenUser: (value) => opened = value,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('用户甲'));
    expect(opened, const UserId('9'));
    expect(tester.takeException(), isNull);
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(find.byKey(const ValueKey('profile-search-toggle')));
      await tester.pumpAndSettle();
    }
    await tester.enterText(find.byType(TextField), '关键词');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repo.keyword, '关键词');
  });
  testWidgets('header relation counts select their matching profile sections', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ProfileScreen(id: id)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('profile-following-stat')));
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.following);
    await tester.tap(find.byKey(const ValueKey('profile-followers-stat')));
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.followers);
    await tester.tap(find.byKey(const ValueKey('profile-tab-videos')));
    await tester.pumpAndSettle();
    expect(state().section, ProfileSection.videos);
    expect(find.byKey(const ValueKey('profile-video-search')), findsOneWidget);
  });
  for (final (width, scale) in [(1920.0, 1.0), (375.0, 2.0)]) {
    testWidgets(
      'profile favorite videos share the grid at $width, scale $scale',
      (tester) async {
        const video = VideoSummary(
          id: VideoId('BV1234567890'),
          title: '收藏视频',
          coverUrl: '',
          author: '收藏作者',
          authorId: UserId('9'),
          duration: Duration(seconds: 125),
          playCount: 12345,
          danmakuCount: 67,
        );
        repo.items = [
          for (var i = 0; i < 30; i++)
            ProfileEntry(
              id: '$i',
              kind: ProfileEntryKind.video,
              title: video.title,
              video: video,
            ),
          const ProfileEntry(
            id: 'unavailable',
            kind: ProfileEntryKind.video,
            title: '已失效视频',
          ),
        ];
        controller.openFolder(
          const ProfileEntry(
            id: '42',
            kind: ProfileEntryKind.folder,
            title: '收藏夹',
          ),
        );
        await tester.pump();
        await tester.binding.setSurfaceSize(Size(width, 1080));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        VideoSummary? opened;
        UserId? author;
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
                body: ProfileScreen(
                  id: id,
                  initialSection: ProfileSection.folders,
                  onOpenVideo: (value) => opened = value,
                  onOpenUser: (value) => author = value,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(VideoCard), findsWidgets);
        expect(find.byType(ProfileVideoCard), findsNothing);
        expect(find.byType(VideoCard).evaluate().length, lessThan(30));
        final rect = tester.getRect(find.byType(VideoCard).first);
        expect(rect.width, closeTo(width == 1920 ? 298 : 343, .1));
        await tester.tap(find.text('收藏作者').first);
        expect(author, const UserId('9'));
        await tester.tap(find.text('收藏视频').first);
        expect(opened, video);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('empty state remains visible and refresh available', (
    tester,
  ) async {
    repo.items = const [];
    repo.hasMore = false;
    await controller.load(refresh: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: ProfileScreen(id: id)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('投稿暂无公开内容'), findsOneWidget);
    expect(find.text('刷新'), findsOneWidget);
  });
}

class _Repo implements ProfileRepository, ProfileDetailsRepository {
  AppFailure? detailsFailure;
  Completer<ProfileSpaceDetails>? detailsPending;
  RequestCancellation? detailsRead;
  ProfileCollectionId? collection;
  @override
  Future<ProfileSpaceDetails> loadDetails(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    detailsRead = cancellation;
    if (detailsFailure case final error?) throw error;
    return detailsPending?.future ?? const ProfileSpaceDetails(gender: '保密');
  }

  ProfileLiveRoom? liveRoom;
  AppFailure? liveFailure;
  Completer<ProfileLiveRoom?>? livePending;
  RequestCancellation? liveRead;
  @override
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    liveRead = cancellation;
    if (liveFailure case final error?) throw error;
    return switch (livePending) {
      final pending? => await pending.future,
      null => liveRoom,
    };
  }

  int epoch = 0;
  int listReads = 0;
  bool isHidden = false;
  bool hasMore = true;
  List<ProfileEntry> items = const [entry];
  Completer<ProfilePage>? pending;
  RequestCancellation? read;
  String? keyword;
  AppFailure? failure;
  AppFailure? profileFailure;
  Completer<UserProfile>? profilePending;
  RequestCancellation? profileRead;
  @override
  String get accountScope => 'account-$epoch';
  @override
  int get sessionEpoch => epoch;
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async {
    profileRead = cancellation;
    if (profileFailure case final error?) throw error;
    return profilePending?.future ?? UserProfile(id: id, name: '个人主页');
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
  }) async {
    listReads++;
    this.collection = collection;
    read = cancellation;
    this.keyword = keyword;
    if (failure case final error?) throw error;
    return pending?.future ??
        (isHidden
            ? const ProfilePage.hidden()
            : ProfilePage(items: items, hasMore: hasMore, cursor: '$page'));
  }
}

class _Auth implements AuthRepository {
  final stream = StreamController<AuthState>.broadcast(sync: true);
  AuthState value = const AuthState(status: AuthStatus.signedIn, mid: '7');
  void emit(AuthState state) {
    value = state;
    stream.add(state);
  }

  @override
  AuthState get current => value;
  @override
  Stream<AuthState> get changes => stream.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}
