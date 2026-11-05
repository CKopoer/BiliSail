import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';

const _id = UserId('7');

void main() {
  late _Profile repository;
  late AuthFake auth;
  late ProviderContainer container;
  ProfileState state() => container.read(profileControllerProvider(_id));
  ProfileController controller() =>
      container.read(profileControllerProvider(_id).notifier);

  setUp(() {
    repository = _Profile();
    auth = AuthFake();
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repository),
        authRepositoryProvider.overrideWithValue(auth),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await auth.stream.close();
  });

  Future<void> mount(
    WidgetTester tester, {
    bool active = true,
    ProfileSection section = ProfileSection.videos,
  }) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Scaffold(
            body: WorkspaceActivity(
              active: active,
              child: ProfileScreen(
                id: _id,
                isSelf: true,
                initialSection: section,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final section in ProfileSection.values) {
    testWidgets('${section.name} prefetches before reaching the bottom', (
      tester,
    ) async {
      await mount(tester, section: section);
      expect(repository.pages(section), [1]);
      expect(find.text('加载更多', skipOffstage: false), findsNothing);

      await _wheel(tester, 100);
      expect(repository.pages(section), [1]);
      await _nearBottom(tester);
      await tester.pumpAndSettle();
      expect(repository.pages(section), [1, 2]);
      expect(state().current.items, hasLength(60));
      expect(_position(tester).extentAfter, greaterThan(0));

      await tester.scrollUntilVisible(
        find.text('已显示全部可见内容'),
        500,
        scrollable: find
            .descendant(of: _list(tester), matching: find.byType(Scrollable))
            .first,
      );
      await _wheel(tester, 100);
      await tester.pumpAndSettle();
      expect(repository.pages(section), [1, 2]);
      expect(find.text('已显示全部可见内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('folder videos also prefetch using the selected folder', (
    tester,
  ) async {
    await mount(tester, section: ProfileSection.folders);
    await tester.tap(find.text('folders-1-0'));
    await tester.pumpAndSettle();
    expect(state().folderId, 'folders-1-0');
    expect(
      repository.pages(ProfileSection.folders, folderId: state().folderId),
      [1],
    );
    await _nearBottom(tester);
    await tester.pumpAndSettle();
    expect(
      repository.pages(ProfileSection.folders, folderId: state().folderId),
      [1, 2],
    );
    expect(find.text('加载更多', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final count in [0, 1]) {
    testWidgets(
      'fills a short first page with $count items without scrolling',
      (tester) async {
        repository.itemCount = count;
        await mount(tester);
        expect(repository.pages(ProfileSection.videos), [1, 2]);
        expect(state().current.items, hasLength(count + 30));
        expect(_position(tester).pixels, 0);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('keeps automatic pagination single flight and retains position', (
    tester,
  ) async {
    final pending = Completer<ProfilePage>();
    repository.pending = pending;
    await mount(tester);
    await _nearBottom(tester);
    for (var i = 0; i < 4; i++) {
      await _wheel(tester, 10);
    }
    expect(repository.pages(ProfileSection.videos), [1, 2]);
    expect(state().current.loading, isTrue);
    final offset = _position(tester).pixels;
    pending.complete(_page(ProfileSection.videos, 2));
    await tester.pumpAndSettle();
    expect(state().current.items, hasLength(60));
    expect(_position(tester).pixels, closeTo(offset, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'failed pagination waits for an explicit retry of the same page',
    (tester) async {
      repository.failNext = true;
      await mount(tester);
      await _nearBottom(tester);
      await tester.pumpAndSettle();
      expect(state().current.items, hasLength(30));
      expect(state().current.message, '下一页加载失败');
      await _wheel(tester, 1000);
      await tester.pumpAndSettle();
      expect(repository.pages(ProfileSection.videos), [1, 2]);
      _position(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repository.pages(ProfileSection.videos), [1, 2, 2]);
      expect(state().current.items, hasLength(60));
      expect(state().current.message, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('hidden workspace waits until activation to fill a short page', (
    tester,
  ) async {
    repository.itemCount = 1;
    await mount(tester, active: false);
    expect(repository.pages(ProfileSection.videos), [1]);
    await mount(tester);
    expect(repository.pages(ProfileSection.videos), [1, 2]);
    expect(tester.takeException(), isNull);
  });

  for (final count in [0, 1]) {
    testWidgets('pauses repeated pages with $count items until manual retry', (
      tester,
    ) async {
      repository
        ..itemCount = count
        ..repeatPages = true;
      await mount(tester);
      // An empty first page already consumes one of the three attempts.
      final lastPage = count == 0 ? 3 : 4;
      expect(repository.pages(ProfileSection.videos), [
        for (var page = 1; page <= lastPage; page++) page,
      ]);
      expect(state().current.hasMore, isTrue);
      expect(state().current.cursor, '$lastPage');
      expect(find.text('连续多页没有新内容，可重试继续加载'), findsOneWidget);
      await _wheel(tester, 500);
      await tester.pumpAndSettle();
      expect(repository.pages(ProfileSection.videos), hasLength(lastPage));
      repository.repeatPages = false;
      _position(tester).jumpTo(0);
      await tester.pumpAndSettle();
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(repository.pages(ProfileSection.videos).last, lastPage + 1);
      expect(state().current.items, hasLength(count + 30));
      expect(state().current.message, isNull);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('late hidden-tab page does not paginate the newly selected tab', (
    tester,
  ) async {
    final pending = Completer<ProfilePage>();
    repository.pending = pending;
    await mount(tester);
    await _nearBottom(tester);
    controller().select(ProfileSection.following);
    await tester.pumpAndSettle();
    expect(repository.pages(ProfileSection.following), [1]);
    // A duplicate page remains near the bottom with more server pages, but its
    // retained viewport is now inactive and must not start another request.
    pending.complete(_page(ProfileSection.videos, 1));
    await tester.pumpAndSettle();
    expect(repository.pages(ProfileSection.videos), [1, 2]);
    expect(repository.pages(ProfileSection.following), [1]);
    expect(state().section, ProfileSection.following);
    expect(tester.takeException(), isNull);
  });

  testWidgets('private lists never trigger automatic pagination', (
    tester,
  ) async {
    repository.hidden = true;
    await mount(tester, section: ProfileSection.followers);
    expect(repository.pages(ProfileSection.followers), [1]);
    expect(find.text('该用户未公开粉丝列表'), findsOneWidget);
    expect(find.text('加载更多', skipOffstage: false), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Finder _list(WidgetTester tester) {
  final viewport = tester.getRect(
    find.byKey(const ValueKey('profile-section-swipe')),
  );
  return find.byWidget(
    find.byType(CustomScrollView).evaluate().singleWhere((element) {
      final rect = tester.getRect(find.byWidget(element.widget));
      return (rect.left - viewport.left).abs() < .1;
    }).widget,
  );
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find
          .descendant(of: _list(tester), matching: find.byType(Scrollable))
          .first,
    )
    .position;

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(_list(tester)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _nearBottom(WidgetTester tester) async {
  await _wheel(tester, _position(tester).extentAfter - 400);
}

final class _Profile implements ProfileRepository {
  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 1;
  int itemCount = 30;
  bool failNext = false;
  bool hidden = false;
  bool repeatPages = false;
  Completer<ProfilePage>? pending;
  final calls = <(ProfileSection, String?, int)>[];

  List<int> pages(ProfileSection section, {String? folderId}) => [
    for (final call in calls)
      if (call.$1 == section && call.$2 == folderId) call.$3,
  ];

  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) async => UserProfile(id: id, name: '主页');

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
  }) async {
    calls.add((section, folderId, page));
    if (hidden) return const ProfilePage.hidden();
    if (repeatPages) {
      return ProfilePage(
        items: _page(section, 1, count: itemCount).items,
        hasMore: true,
        cursor: '$page',
      );
    }
    if (page == 2) {
      if (failNext) {
        failNext = false;
        throw const AppFailure(AppFailureKind.network, '下一页加载失败');
      }
      final request = pending;
      pending = null;
      if (request != null) return request.future;
    }
    return _page(
      section,
      page,
      count: page == 1 ? itemCount : 30,
      folderId: folderId,
    );
  }
}

ProfilePage _page(
  ProfileSection section,
  int page, {
  int count = 30,
  String? folderId,
}) => ProfilePage(
  items: [for (var i = 0; i < count; i++) _entry(section, page, i, folderId)],
  hasMore: page < 2,
  cursor: '$page',
);

ProfileEntry _entry(
  ProfileSection section,
  int page,
  int index,
  String? folderId,
) {
  final id = '${section.name}-$page-$index';
  if (section == ProfileSection.videos || folderId != null) {
    return ProfileEntry(
      id: id,
      kind: ProfileEntryKind.video,
      title: id,
      video: VideoSummary(
        id: VideoId(
          'BV00000${page.toString().padLeft(2, '0')}${index.toString().padLeft(3, '0')}',
        ),
        title: id,
        author: 'UP',
        coverUrl: '',
        duration: const Duration(minutes: 1),
      ),
    );
  }
  if (section == ProfileSection.dynamics) {
    return ProfileEntry(
      id: id,
      kind: ProfileEntryKind.dynamic,
      title: id,
      dynamicPost: DynamicPost(id: id, authorName: 'UP', text: id),
    );
  }
  return ProfileEntry(
    id: id,
    title: id,
    kind: section == ProfileSection.folders
        ? ProfileEntryKind.folder
        : ProfileEntryKind.user,
    userId: const UserId('8'),
  );
}
