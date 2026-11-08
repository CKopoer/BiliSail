import 'dart:async';

import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/profile/application/profile_controller.dart';
import 'package:bilisail/features/profile/domain/profile_repository.dart';
import 'package:bilisail/features/profile/presentation/profile_screen.dart';
import 'package:bilisail/features/profile/presentation/profile_user_card.dart';
import 'package:bilisail/features/video/application/video_author_controller.dart';
import 'package:bilisail/features/video/domain/video_author_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../messages/message_fakes.dart';
import 'profile_following_fakes.dart';

const _id = UserId('7');
void main() {
  late FollowingRepository repo;
  late AuthFake auth;
  late ProviderContainer container;
  late ValueNotifier<bool> visible;
  late _AuthorRepository authorRepo;
  ProfileController controller() =>
      container.read(profileControllerProvider(_id).notifier);
  Future<void> mount(
    WidgetTester tester, {
    double width = 900,
    double scale = 1,
  }) async {
    tester.view.physicalSize = Size(width, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    repo = FollowingRepository();
    authorRepo = _AuthorRepository(repo);
    auth = AuthFake()
      ..state = const AuthState(status: AuthStatus.signedIn, mid: '7');
    visible = ValueNotifier(true);
    container = ProviderContainer(
      overrides: [
        profileRepositoryProvider.overrideWithValue(repo),
        authRepositoryProvider.overrideWithValue(auth),
        videoAuthorRepositoryProvider.overrideWithValue(authorRepo),
      ],
    );
    addTearDown(() async {
      container.dispose();
      visible.dispose();
      await auth.stream.close();
    });
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
            body: ValueListenableBuilder<bool>(
              valueListenable: visible,
              builder: (_, show, _) => show
                  ? const ProfileScreen(
                      id: _id,
                      isSelf: true,
                      initialSection: ProfileSection.following,
                    )
                  : const SizedBox(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String title) async {
    await tester.tap(find.byTooltip('关注管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester, String value) async {
    await tester.enterText(find.byType(TextFormField), value);
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
  }

  testWidgets('create rename delete and sorting use project dialogs', (
    tester,
  ) async {
    await mount(tester);
    await action(tester, '新建分组');
    await submit(tester, '新分组');
    expect(repo.edits.single, (FollowGroupEdit.create, null, '新分组'));
    expect(find.widgetWithText(TextButton, '新分组'), findsOneWidget);
    controller().selectFollowingGroup('3');
    await tester.pumpAndSettle();
    repo.contentRevision = 1;
    await action(tester, '重命名分组');
    await submit(tester, '重命名');
    expect(repo.edits.last, (FollowGroupEdit.rename, '3', '重命名'));
    expect(find.widgetWithText(TextButton, '重命名'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '新分组'), findsNothing);
    expect(find.text('分组3-1-r1'), findsOneWidget);
    await action(tester, '删除分组');
    expect(find.textContaining('关注关系会保留'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(repo.edits.last.$1, FollowGroupEdit.delete);
    expect(find.widgetWithText(TextButton, '重命名'), findsNothing);
    expect(find.text('关注-1-r1'), findsOneWidget);
    expect(
      container.read(profileControllerProvider(_id)).followingGroupId,
      isNull,
    );
    await action(tester, '分组排序');
    final reorder = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    reorder.onReorderItem!(0, 1);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(repo.sorted, ['2', '1']);
    final group2 = find.byKey(const ValueKey('profile-follow-group-2'));
    final group1 = find.byKey(const ValueKey('profile-follow-group-1'));
    expect(
      tester.getTopLeft(group2).dx,
      lessThan(tester.getTopLeft(group1).dx),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('search all following and clearing restore remote list', (
    tester,
  ) async {
    await mount(tester);
    final search = find.byKey(const ValueKey('profile-following-search'));
    await tester.enterText(search, '名字');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();
    expect(repo.queries.any((query) => query.$1 == '名字'), true);
    expect(find.text('全部关注的搜索结果'), findsOneWidget);
    expect(find.text('名字-1'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(container.read(profileControllerProvider(_id)).followingKeyword, '');
    expect(find.text('全部关注的搜索结果'), findsNothing);
  });

  testWidgets('created and deleted top tabs survive stale group reads', (
    tester,
  ) async {
    await mount(tester);
    repo.staleGroups = List.of(repo.groups);
    final pending = repo.pendingGroups = Completer<List<ProfileFollowGroup>>();
    await action(tester, '新建分组');
    await tester.enterText(find.byType(TextFormField), '新分组');
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final created = find.byKey(const ValueKey('profile-follow-group-3'));
    // The top tab appears from the successful POST, before GET completes.
    expect(created.hitTestable(), findsOneWidget);
    pending.complete(repo.staleGroups);
    await tester.pumpAndSettle();
    repo.pendingGroups = null;
    expect(created, findsOneWidget);
    expect(find.widgetWithText(TextButton, '新分组'), findsOneWidget);
    await tester.tap(created);
    await tester.pumpAndSettle();
    repo.staleGroups = List.of(repo.groups);
    await action(tester, '删除分组');
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(created, findsNothing);
    expect(find.text('关注-1'), findsOneWidget);
    await controller().loadFollowGroups();
    await tester.pumpAndSettle();
    expect(created, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'relationship state loads only for an explicit action; nested dialogs close with page',
    (tester) async {
      await mount(tester);
      expect(authorRepo.reads, 0);
      await tester.tap(find.byTooltip('管理 关注-1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关注与分组设置'));
      await tester.pumpAndSettle();
      expect(authorRepo.reads, 1);
      await tester.tap(find.text('已关注'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('设置分组'));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      visible.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(authorRepo.groupCancellation?.isCancelled, true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('blacklist supports add and confirmed remove in compact cards', (
    tester,
  ) async {
    await mount(tester);
    await action(tester, '黑名单管理');
    expect(
      find.byKey(const ValueKey('profile-follow-group-all')),
      findsNothing,
    );
    expect(find.byType(ProfileUserCard), findsWidgets);
    await action(tester, '加入黑名单');
    await submit(tester, '9007199254740993123');
    expect(repo.blocks.last, (const UserId('9007199254740993123'), true));
    await tester.tap(find.byTooltip('管理 黑名单-1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('移出黑名单'));
    await tester.pumpAndSettle();
    expect(repo.blocks.length, 1);
    await tester.tap(find.widgetWithText(FilledButton, '确认'));
    await tester.pumpAndSettle();
    expect(repo.blocks.last, (const UserId('9'), false));
    await tester.tap(find.byTooltip('返回关注'));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('profile-following-search')),
      findsOneWidget,
    );
  });

  for (final closePage in [false, true]) {
    testWidgets(
      'dialog draft is discarded on ${closePage ? 'page close' : 'account change'}',
      (tester) async {
        await mount(tester);
        await action(tester, '新建分组');
        await tester.enterText(find.byType(TextFormField), '私密草稿');
        if (closePage) {
          visible.value = false;
        } else {
          repo.accountScope = 'user:8';
          repo.sessionEpoch++;
          auth.emit(const AuthState(status: AuthStatus.signedIn, mid: '8'));
        }
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(find.text('私密草稿'), findsNothing);
        expect(repo.edits, isEmpty);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('tools and cards fit a narrow viewport with double text scale', (
    tester,
  ) async {
    await mount(tester, width: 320, scale: 2);
    expect(find.byType(ProfileUserCard), findsWidgets);
    await action(tester, '新建分组');
    await submit(tester, '分组');
    expect(repo.edits.single.$3, '分组');
    expect(tester.takeException(), isNull);
  });
}

class _AuthorRepository implements VideoAuthorRepository {
  _AuthorRepository(this.profile);
  final FollowingRepository profile;
  int reads = 0;
  RequestCancellation? groupCancellation;
  @override
  String get accountScope => profile.accountScope;
  @override
  int get sessionEpoch => profile.sessionEpoch;
  @override
  Future<VideoAuthor> load(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async {
    reads++;
    return const VideoAuthor(following: true);
  }

  @override
  Future<void> follow(
    VideoAuthorId id,
    bool following,
    RequestCancellation cancellation,
  ) async {}
  @override
  Future<FollowGroupSelection> loadGroups(
    VideoAuthorId id,
    RequestCancellation cancellation,
  ) async {
    groupCancellation = cancellation;
    return const FollowGroupSelection(
      groups: [FollowGroup(id: '1', name: '知识')],
      selectedIds: {},
    );
  }

  @override
  Future<void> saveGroups(
    VideoAuthorId id,
    Set<String> groupIds,
    RequestCancellation cancellation,
  ) async {}
}
