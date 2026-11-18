import '../support/material_tooltip_finder.dart';

import 'dart:async';

import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/content_link.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/presentation/account_button.dart';
import 'package:bilisail/features/auth/presentation/account_menu.dart';
import 'package:bilisail/features/auth/presentation/account_screen.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/downloads/application/download_controller.dart';
import 'package:bilisail/features/downloads/domain/download_repository.dart';
import 'package:bilisail/features/downloads/presentation/downloads_screen.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/library/presentation/history_screen.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/features/settings/presentation/settings_screen.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/shared/ui/paging_tab_strip.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';
import '../features/messages/message_fakes.dart';
import '../support/dynamic_fakes.dart';

const _dynamicTarget = CommentTarget('456', CommentTargetType.album);

void main() {
  late _HistoryRepository history;
  late _HomeRepository home;
  late _DownloadRepository downloads;
  late MessageRepositoryFake messages;

  setUp(() {
    history = _HistoryRepository();
    home = _HomeRepository();
    downloads = _DownloadRepository();
    messages = MessageRepositoryFake()..more = false;
  });

  Future<GoRouter> mount(
    WidgetTester tester, {
    double width = 1200,
    bool signedIn = true,
    bool showAccountMenu = false,
    String initialLocation = '/me',
    _AuthRepository? auth,
    int Function()? epoch,
    WorkspaceNavigationMode mode = WorkspaceNavigationMode.dualTabs,
    DynamicRepositoryFake? dynamics,
    CommentsRepository? dynamicComments,
    Future<bool> Function(Uri)? externalOpener,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 820);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final router = createBiliRouter(
      initialLocation: initialLocation,
      playerBuilder: (_, _, _) => const SizedBox(),
      accountBuilder: (context) => showAccountMenu
          ? AccountButton(onNavigate: context.go)
          : const SizedBox(width: 40, height: 40),
    );
    addTearDown(router.dispose);
    final repository = auth ?? _AuthRepository(signedIn);
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(
            _SettingsRepository(mode),
          ),
          authRepositoryProvider.overrideWithValue(repository),
          if (epoch != null) sessionEpochProvider.overrideWithValue(epoch),
          accountOverviewProvider.overrideWith((_) async => null),
          accountMessageIndicatorProvider.overrideWithValue(
            const AccountMessageIndicator(),
          ),
          libraryRepositoryProvider.overrideWithValue(history),
          homeRepositoryProvider.overrideWithValue(home),
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          downloadRepositoryProvider.overrideWithValue(downloads),
          messageRepositoryProvider.overrideWithValue(messages),
          if (dynamics != null)
            dynamicRepositoryProvider.overrideWithValue(dynamics),
          if (dynamicComments != null)
            commentsRepositoryProvider(_dynamicTarget.type)
                .overrideWithValue(dynamicComments),
          if (externalOpener != null)
            externalLinkOpenerProvider.overrideWithValue(externalOpener),
        ],
        child: InputTestApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  for (final (section, mode, width, targetPath) in [
    (
      InboxSection.replies,
      WorkspaceNavigationMode.singlePage,
      390.0,
      '/100?comment_root_id=200&comment_secondary_id=202',
    ),
    (InboxSection.likes, WorkspaceNavigationMode.dualTabs, 1200.0, '/100'),
    (
      InboxSection.mentions,
      WorkspaceNavigationMode.multipleTabs,
      1200.0,
      '/456?type=2&comment_root_id=200&comment_secondary_id=202',
    ),
  ]) {
    testWidgets(
      '$section opens dynamic detail and returns to the retained inbox',
      (tester) async {
        messages.entries = [
          InboxEntry(
            id: '999',
            title: '动态通知',
            text: '通知正文',
            targetUrl: Uri.parse('https://t.bilibili.com$targetPath'),
          ),
        ];
        final dynamicRepository = _NotificationDynamics();
        final comments = _NotificationComments();
        final external = <Uri>[];
        final router = await mount(
          tester,
          width: width,
          mode: mode,
          initialLocation: '/messages',
          dynamics: dynamicRepository,
          dynamicComments: comments,
          externalOpener: (uri) async {
            external.add(uri);
            return true;
          },
        );
        if (mode == WorkspaceNavigationMode.multipleTabs) {
          router.go('/history');
          await tester.pumpAndSettle();
          router.go('/messages');
          await tester.pumpAndSettle();
        }
        await tester.tap(
          find.byKey(ValueKey('message-section-${section.name}')),
        );
        await tester.pumpAndSettle();
        final inbox = tester.state(find.byType(MessagesScreen));
        final reads = messages.reads;
        await tester.tap(
          find.text(section == InboxSection.replies ? '查看原内容' : '通知正文'),
        );
        await tester.pumpAndSettle();
        final byResourceId = section == InboxSection.mentions;
        final location = router.routeInformationProvider.value.uri;
        expect(
          location.path,
          byResourceId ? '/dynamic/resource/456' : '/dynamic/100',
        );
        expect(dynamicRepository.reads, [
          byResourceId ? ('456', true) : ('100', false),
        ]);
        expect(external, isEmpty);
        if (section == InboxSection.likes) {
          expect(find.text('原动态正文').hitTestable(), findsOneWidget);
          expect(comments.locations, isEmpty);
        } else {
          expect(comments.locations, [
            ('456', const CommentLocation('200', replyId: '202')),
          ]);
          expect(find.text('被定位的回复').hitTestable(), findsOneWidget);
          await tester.tap(findMaterialTooltip('返回评论'));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.byKey(const ValueKey('dynamic-detail-back')));
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/messages');
        expect(tester.state(find.byType(MessagesScreen)), same(inbox));
        expect(find.text('通知正文').hitTestable(), findsOneWidget);
        expect(messages.reads, reads);
        expect(tester.takeException(), isNull);
      },
    );
  }

  Future<void> select(WidgetTester tester, String label) async {
    final target = find
        .descendant(of: find.byType(AccountScreen), matching: find.text(label))
        .first;
    await tester.ensureVisible(target);
    await tester.tap(target);
    await tester.pumpAndSettle();
  }

  Future<void> openAccountTab(
    WidgetTester tester,
    AccountContentTab tab,
  ) async {
    if (findMaterialTooltip('我的账号').evaluate().isEmpty) {
      await tester.tap(
        find.byKey(const ValueKey('workspace-nav-home')).evaluate().isNotEmpty
            ? find.byKey(const ValueKey('workspace-nav-home'))
            : find.byKey(const ValueKey('workspace-bottom-home')),
      );
      await tester.pumpAndSettle();
    }
    await tester.tap(findMaterialTooltip('我的账号'));
    await tester.pumpAndSettle();
    final item = find.descendant(
      of: find.byType(AccountMenu),
      matching: find.text(tab.label),
    );
    await tester.ensureVisible(item);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(find.byType(AccountMenu), findsNothing);
  }

  for (final mode in WorkspaceNavigationMode.values) {
    for (final width in [390.0, 1200.0]) {
      testWidgets('account menu opens retained My tabs at $width in $mode', (
        tester,
      ) async {
        final router = await mount(
          tester,
          width: width,
          mode: mode,
          initialLocation: '/',
          showAccountMenu: true,
        );
        State? account;
        var watchLaterVisited = false;
        for (final tab in [
          AccountContentTab.watchLater,
          AccountContentTab.favorites,
          AccountContentTab.history,
          AccountContentTab.watchLater,
        ]) {
          await openAccountTab(tester, tab);
          final uri = router.routeInformationProvider.value.uri;
          expect(uri.path, '/me');
          expect(uri.queryParameters['section'], tab.name);
          final state = tester.state(find.byType(AccountScreen));
          if (account == null) {
            account = state;
          } else {
            expect(state, same(account));
          }
          expect(
            tester
                .widget<PagingTabStrip<AccountContentTab>>(
                  find.byType(PagingTabStrip<AccountContentTab>),
                )
                .value,
            tab,
          );
          if (tab == AccountContentTab.watchLater) {
            if (!watchLaterVisited) {
              await tester.tap(find.text('未看完'));
              await tester.pumpAndSettle();
              watchLaterVisited = true;
            }
            expect(find.text('稍后再看·未看完'), findsOneWidget);
          }
        }
        expect(history.loads, 1);
        expect(
          home.queries.where(
            (query) => query.channel == HomeChannel.watchLater,
          ),
          hasLength(2),
        );

        // A route can also change the selected tab while My stays visible.
        await select(tester, '我的收藏');
        expect(
          router.routeInformationProvider.value.uri.queryParameters['section'],
          'favorites',
        );
        router.go('/me?section=watchLater');
        await tester.pumpAndSettle();
        expect(find.text('稍后再看·未看完'), findsOneWidget);
        await openAccountTab(tester, AccountContentTab.watchLater);
        expect(tester.state(find.byType(AccountScreen)), same(account));
        expect(find.text('稍后再看·未看完'), findsOneWidget);
        if (mode == WorkspaceNavigationMode.multipleTabs) {
          expect(
            find.byKey(const ValueKey('workspace-tab-home')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('workspace-tab-tab-1')),
            findsNothing,
          );
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  for (final tab in AccountContentTab.values) {
    testWidgets('My deep link lazily opens ${tab.name}', (tester) async {
      await mount(tester, initialLocation: '/me?section=${tab.name}');
      expect(
        tester
            .widget<PagingTabStrip<AccountContentTab>>(
              find.byType(PagingTabStrip<AccountContentTab>),
            )
            .value,
        tab,
      );
      expect(history.loads, tab == AccountContentTab.history ? 1 : 0);
      expect(
        downloads.initializations,
        tab == AccountContentTab.downloads ? 1 : 0,
      );
      expect(
        home.queries,
        hasLength(
          tab == AccountContentTab.watchLater ||
                  tab == AccountContentTab.favorites
              ? 1
              : 0,
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('account content stays inline and retained at $width', (
      tester,
    ) async {
      final router = await mount(tester, width: width);
      final accountState = tester.state(find.byType(AccountScreen));
      expect(history.loads, 1);
      expect(home.queries, isEmpty);
      expect(downloads.initializations, 0);
      final historyView = tester.widget<CustomScrollView>(
        find.descendant(
          of: find.byType(HistoryScreen),
          matching: find.byType(CustomScrollView),
        ),
      );
      historyView.controller!.jumpTo(240);
      await tester.pump();

      await select(tester, '稍后再看');
      expect(home.queries.last.channel, HomeChannel.watchLater);
      await tester.tap(find.text('未看完'));
      await tester.pumpAndSettle();
      expect(home.queries.last.section, '未看完');

      await select(tester, '我的收藏');
      expect(home.queries.last.channel, HomeChannel.favorites);
      await tester.tap(find.text('我创建的收藏夹'));
      await tester.pumpAndSettle();
      expect(home.queries.last.section, '我创建的收藏夹');

      await select(tester, '下载');
      expect(find.byType(DownloadsScreen), findsOneWidget);
      expect(downloads.initializations, 1);
      await tester.tap(find.text('已完成'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.descendant(
          of: find.byType(DownloadsScreen),
          matching: find.byType(TextField),
        ),
        '保留下载筛选',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final loaded = home.queries.length;
      // Starting at My exercises insertion of the feed before the retained
      // account branch, where keys must belong to the outer retained wrapper.
      router.go('/?channel=bangumi&section=时间表');
      await tester.pumpAndSettle();
      final feedState = tester.state(find.byType(FeedScreen));
      final feedLoads = home.queries.length;
      final historyLoads = history.loads;
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(home.queries.length, feedLoads + 1);
      expect(home.queries.last.channel, HomeChannel.bangumi);
      expect(history.loads, historyLoads);
      expect(downloads.refreshes, 0);
      final feedScroll = tester
          .widget<CustomScrollView>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is CustomScrollView &&
                  widget.key is PageStorageKey<String> &&
                  (widget.key as PageStorageKey<String>).value.startsWith(
                    'home-bangumi-时间表-',
                  ),
            ),
          )
          .controller!;
      expect(feedScroll.position.maxScrollExtent, greaterThan(360));
      feedScroll.jumpTo(360);
      await tester.pumpAndSettle();
      expect(feedScroll.offset, 360);
      router.go('/me');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AccountScreen)), same(accountState));
      expect(find.text('保留下载筛选'), findsOneWidget);
      final beforeAccountRefresh = home.queries.length;
      await tester.sendKeyEvent(LogicalKeyboardKey.f5);
      await tester.pumpAndSettle();
      expect(downloads.refreshes, 1);
      expect(home.queries.length, beforeAccountRefresh);

      await select(tester, '历史记录');
      expect(historyView.controller!.offset, 240);
      expect(history.loads, 1);
      await select(tester, '稍后再看');
      expect(find.text('稍后再看·未看完'), findsOneWidget);
      await select(tester, '我的收藏');
      expect(find.text('我的收藏·我创建的收藏夹'), findsOneWidget);
      await select(tester, '下载');
      expect(find.text('保留下载筛选'), findsOneWidget);
      expect(home.queries.length, greaterThan(loaded));
      router.go('/?channel=bangumi&section=时间表');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(FeedScreen)), same(feedState));
      expect(feedScroll.offset, 360);
      expect(home.queries.length, beforeAccountRefresh);
      router.go('/me');
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AccountScreen)), same(accountState));
      expect(find.text('保留下载筛选'), findsOneWidget);
      expect(router.routeInformationProvider.value.uri.path, '/me');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('refresh targets only the selected inline account tab', (
    tester,
  ) async {
    await mount(tester);
    await select(tester, '稍后再看');
    await tester.tap(find.text('未看完'));
    await tester.pumpAndSettle();
    final initialHome = home.queries.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(home.queries.length, initialHome + 1);
    expect(home.queries.last.section, '未看完');
    expect(home.queries.where((query) => query.section == '全部'), hasLength(1));
    expect(history.loads, 1);
    await select(tester, '下载');
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(downloads.refreshes, 1);
    expect(history.loads, 1);
    expect(home.queries.length, initialHome + 1);
    await select(tester, '历史记录');
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(history.loads, 2);
    expect(downloads.refreshes, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('desktop primary My uses the pinned home tab in multiple mode', (
    tester,
  ) async {
    await mount(tester, mode: WorkspaceNavigationMode.multipleTabs);
    final account = tester.state(find.byType(AccountScreen));
    await select(tester, '稍后再看');
    await tester.tap(find.text('未看完'));
    await tester.pumpAndSettle();
    for (var visit = 0; visit < 2; visit++) {
      await tester.tap(find.byKey(const ValueKey('workspace-nav-home')));
      await tester.pumpAndSettle();
      expect(find.byType(FeedScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('workspace-nav-mine')));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(AccountScreen)), same(account));
      expect(find.text('稍后再看·未看完'), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-home')), findsOneWidget);
      expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
      expect(
        find.byKey(const ValueKey('close-workspace-tab-home')),
        findsNothing,
      );
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('legacy root routes normalize ranking and live sections', (
    tester,
  ) async {
    final router = await mount(
      tester,
      initialLocation: '/?channel=ranking&category=17&tab=home',
    );
    var uri = router.routeInformationProvider.value.uri;
    expect(uri.queryParameters['channel'], 'popular');
    expect(uri.queryParameters['section'], '排行榜');
    expect(uri.queryParameters['category'], '17');
    expect(uri.queryParameters['tab'], 'home');
    var feed = tester.widget<FeedScreen>(find.byType(FeedScreen));
    expect(feed.channel, HomeChannel.popular);
    expect(feed.initialSection, '排行榜');
    router.go('/?channel=live&section=全部分区&tab=home');
    await tester.pumpAndSettle();
    uri = router.routeInformationProvider.value.uri;
    expect(uri.queryParameters['section'], '推荐直播');
    feed = tester.widget<FeedScreen>(find.byType(FeedScreen));
    expect(feed.initialSection, '推荐直播');
    expect(feed.showLiveSectionTabs, isFalse);
    tester.view.physicalSize = const Size(390, 820);
    await tester.pumpAndSettle();
    feed = tester.widget<FeedScreen>(find.byType(FeedScreen));
    expect(feed.showLiveSectionTabs, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('messages downloads and settings retain one primary workspace', (
    tester,
  ) async {
    final router = await mount(
      tester,
      mode: WorkspaceNavigationMode.multipleTabs,
      initialLocation: '/messages?talker=2',
    );
    final inboxState = tester.state(find.byType(MessagesScreen));
    final inboxScope = ProviderScope.containerOf(
      tester.element(find.byType(MessagesScreen)),
    );
    expect(
      inboxScope.read(messagesControllerProvider).selected?.userId?.value,
      '2',
    );
    expect(
      router.routeInformationProvider.value.uri.queryParameters['talker'],
      isNull,
    );
    await tester.enterText(find.widgetWithText(TextField, '输入私信消息'), '保留根消息草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    router.go('/downloads');
    await tester.pumpAndSettle();
    final downloadsState = tester.state(find.byType(DownloadsScreen));
    await tester.enterText(
      find.descendant(
        of: find.byType(DownloadsScreen),
        matching: find.byType(TextField),
      ),
      '保留根下载筛选',
    );
    FocusManager.instance.primaryFocus?.unfocus();
    router.go('/settings?section=shortcuts');
    await tester.pumpAndSettle();
    final settingsState = tester.state(find.byType(SettingsScreen));
    await tester.tap(find.byKey(const ValueKey('settings-category-playback')));
    await tester.pumpAndSettle();
    final messageReads = messages.reads;
    final downloadRefreshes = downloads.refreshes;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(messages.reads, messageReads);
    expect(downloads.refreshes, downloadRefreshes);
    router.go('/?channel=bangumi');
    await tester.pumpAndSettle();
    final feedLoads = home.queries.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(home.queries.length, feedLoads + 1);
    expect(messages.reads, messageReads);
    expect(downloads.refreshes, downloadRefreshes);
    router.go('/messages');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(MessagesScreen)), same(inboxState));
    expect(
      ProviderScope.containerOf(tester.element(find.byType(MessagesScreen))),
      same(inboxScope),
    );
    expect(find.text('保留根消息草稿'), findsOneWidget);
    final beforeMessagesRefresh = home.queries.length;
    final beforeMessageMarks = messages.marks;
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    // The fake still reports unread messages, so reloading the thread also
    // acknowledges it and reconciles the inbox once more.
    expect(messages.marks, beforeMessageMarks + 1);
    expect(messages.reads, messageReads + 2);
    expect(home.queries.length, beforeMessagesRefresh);
    expect(downloads.refreshes, downloadRefreshes);
    router.go('/downloads');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(DownloadsScreen)), same(downloadsState));
    expect(find.text('保留根下载筛选'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await tester.pumpAndSettle();
    expect(downloads.refreshes, downloadRefreshes + 1);
    expect(messages.reads, messageReads + 2);
    await tester.tap(find.byKey(const ValueKey('workspace-nav-settings')));
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(SettingsScreen)), same(settingsState));
    expect(
      tester.widget<SettingsScreen>(find.byType(SettingsScreen)).category.name,
      'playback',
    );
    expect(find.byKey(const ValueKey('workspace-tab-home')), findsOneWidget);
    expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
    expect(downloads.initializations, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an account epoch resets all visited private root branches', (
    tester,
  ) async {
    final auth = _AuthRepository(true);
    var epoch = 1;
    final router = await mount(tester, auth: auth, epoch: () => epoch);
    final oldAccount = tester.state(find.byType(AccountScreen));
    await select(tester, '稍后再看');
    await tester.tap(find.text('未看完'));
    await tester.pumpAndSettle();
    router.go('/?channel=bangumi');
    await tester.pumpAndSettle();
    final oldFeed = tester.state(find.byType(FeedScreen));
    router.go('/messages?talker=2');
    await tester.pumpAndSettle();
    final messageRead = messages.threadRead;
    expect(messageRead, isNotNull);
    router.go('/me');
    await tester.pumpAndSettle();
    epoch++;
    auth.notifySession();
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(AccountScreen)), isNot(same(oldAccount)));
    expect(find.byType(HistoryScreen), findsOneWidget);
    expect(history.loads, 2);
    expect(find.byType(FeedScreen, skipOffstage: false), findsNothing);
    expect(find.byType(MessagesScreen, skipOffstage: false), findsNothing);
    expect(messageRead!.isCancelled, isTrue);
    router.go('/?channel=bangumi');
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(FeedScreen)), isNot(same(oldFeed)));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'guest account tabs keep downloads accessible without cloud reads',
    (tester) async {
      final router = await mount(tester, width: 390, signedIn: false);
      expect(find.text('登录后可查看历史记录'), findsOneWidget);
      await select(tester, '稍后再看');
      expect(find.text('登录后可查看稍后再看'), findsOneWidget);
      await select(tester, '我的收藏');
      expect(find.text('登录后可查看我的收藏'), findsOneWidget);
      await select(tester, '下载');
      expect(find.text('还没有下载任务'), findsOneWidget);
      expect(history.loads, 0);
      expect(home.queries, isEmpty);
      expect(downloads.initializations, 1);
      expect(router.routeInformationProvider.value.uri.path, '/me');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _SettingsRepository implements SettingsRepository {
  const _SettingsRepository(this.mode);
  final WorkspaceNavigationMode mode;
  @override
  Future<AppSettings> load() async =>
      AppSettings.defaults(navigationMode: mode);
  @override
  Future<void> save(AppSettings settings) async {}
}

final class _AuthRepository extends Fake implements AuthRepository {
  _AuthRepository(this.signedIn);
  final bool signedIn;
  final _changes = StreamController<AuthState>.broadcast(sync: true);
  @override
  AuthState get current => signedIn
      ? AuthState(status: AuthStatus.signedIn, mid: '1', userName: '测试账号')
      : const AuthState();
  @override
  Stream<AuthState> get changes => _changes.stream;

  void notifySession() => _changes.add(current);
  Future<void> dispose() => _changes.close();
}

final class _NotificationDynamics extends DynamicRepositoryFake {
  final reads = <(String, bool)>[];

  @override
  Future<DynamicPost> detail(
    String id,
    RequestCancellation cancellation, {
    bool byResourceId = false,
  }) async {
    reads.add((id, byResourceId));
    return DynamicPost(id: '100', text: '原动态正文', commentTarget: _dynamicTarget);
  }
}

final class _NotificationComments extends Fake
    implements CommentsRepository, CommentLocationRepository {
  final locations = <(String, CommentLocation)>[];

  @override
  String get accountScope => 'user:7';
  @override
  int get sessionEpoch => 1;

  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => const CommentPage(items: [], hasMore: false);

  @override
  Future<LocatedCommentThread> locate(
    String oid,
    CommentLocation location,
    RequestCancellation cancellation,
  ) async {
    locations.add((oid, location));
    return const LocatedCommentThread(
      root: CommentEntry(id: '200', author: '评论作者', message: '原评论'),
      page: CommentPage(
        items: [
          CommentEntry(
            id: '202',
            author: '回复作者',
            message: '被定位的回复',
            rootId: '200',
          ),
        ],
        hasMore: false,
      ),
      pageNumber: 1,
    );
  }
}

final class _HistoryRepository implements LibraryRepository {
  int loads = 0;
  @override
  String get accountScope => 'user:1';
  @override
  Future<WatchHistoryPage> loadHistory({
    String keyword = '',
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    loads++;
    return WatchHistoryPage([
      for (var index = 0; index < 24; index++)
        WatchHistoryEntry(
          video: VideoSummary(
            id: VideoId('BV12345678${index.toString().padLeft(2, '0')}'),
            title: '历史第 $index 条',
            coverUrl: '',
            author: '作者',
            duration: const Duration(minutes: 2),
          ),
          part: VideoPart(
            cid: '$index',
            page: 1,
            title: '视频',
            duration: const Duration(minutes: 2),
          ),
          position: const Duration(seconds: 30),
          watchedAt: DateTime(2026, 10, 25),
        ),
    ], hasMore: false);
  }
}

final class _HomeRepository implements HomeRepository {
  final queries = <HomeQuery>[];
  @override
  String get accountScope => 'user:1';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    queries.add(query);
    return HomePage([
      for (
        var index = 0;
        index < (query.channel == HomeChannel.bangumi ? 24 : 1);
        index++
      )
        HomeEntry(
          id: '${query.section}-$index',
          title: '${query.channel.label}·${query.section}',
          kind: HomeEntryKind.video,
          coverUrl: query.channel == HomeChannel.bangumi ? Uri() : null,
          bvid: 'BV12345678${index.toString().padLeft(2, '0')}',
        ),
    ], hasMore: false);
  }
}

final class _FeedRepository extends Fake implements FeedRepository {
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
}

final class _DownloadRepository extends Fake implements DownloadRepository {
  int initializations = 0;
  int refreshes = 0;
  @override
  DownloadQueueState get current => DownloadQueueState(initialized: true);
  @override
  Stream<DownloadQueueState> get changes => const Stream.empty();
  @override
  Future<void> initialize() async => initializations++;
  @override
  Future<void> refresh() async => refreshes++;
}
