import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/core/presentation/page_back_scope.dart';
import 'package:bilisail/features/auth/application/account_overview_controller.dart';
import 'package:bilisail/features/auth/presentation/account_button.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/shared/ui/paging_tab_strip.dart';
import 'package:bilisail/shared/ui/retained_tab_view.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  late AuthFake auth;
  late MessageRepositoryFake repo;
  setUp(() {
    auth = AuthFake();
    repo = MessageRepositoryFake();
  });
  tearDown(() async => auth.stream.close());
  Future<void> mount(
    WidgetTester tester, {
    double scale = 1,
    TargetPlatform? platform,
    ValueNotifier<bool>? active,
    TabPagingProgress? outerProgress,
  }) async {
    final progress = outerProgress ?? TabPagingProgress(0);
    if (outerProgress == null) addTearDown(progress.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: platform),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child ?? const SizedBox(),
          ),
          home: Scaffold(
            body: TabPagingScope(
              progress: progress,
              child: active == null
                  ? const MessagesScreen()
                  : ValueListenableBuilder<bool>(
                      valueListenable: active,
                      child: const MessagesScreen(),
                      builder: (_, value, child) =>
                          WorkspaceActivity(active: value, child: child!),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('message sections swipe in both directions at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MessagesScreen)),
      );
      final pager = find.byKey(const ValueKey('message-section-pager'));
      for (final section in InboxSection.values.skip(1)) {
        await tester.drag(pager, Offset(-width * .8, 0));
        await tester.pumpAndSettle();
        expect(container.read(messagesControllerProvider).section, section);
      }
      for (final section in InboxSection.values.reversed.skip(1)) {
        await tester.drag(pager, Offset(width * .8, 0));
        await tester.pumpAndSettle();
        expect(container.read(messagesControllerProvider).section, section);
      }
      await tester.drag(pager, Offset(width * .8, 0));
      await tester.pumpAndSettle();
      expect(
        container.read(messagesControllerProvider).section,
        InboxSection.private,
      );
      expect(repo.reads, 9);
      expect(repo.sends + repo.marks + repo.systemMarks, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final cancel in [false, true]) {
    testWidgets(
      'partial message swipe follows local progress: cancel=$cancel',
      (tester) async {
        final outer = TabPagingProgress(7);
        addTearDown(outer.dispose);
        await mount(tester, outerProgress: outer);
        final container = ProviderScope.containerOf(
          tester.element(find.byType(MessagesScreen)),
        );
        final progress = tester
            .widget<RetainedTabView<InboxSection>>(
              find.byType(RetainedTabView<InboxSection>),
            )
            .progress!;
        expect(
          tester
              .widget<PagingTabStrip<InboxSection>>(
                find.byType(PagingTabStrip<InboxSection>),
              )
              .progress,
          same(progress),
        );
        expect(progress, isNot(same(outer)));
        final pager = find.byKey(const ValueKey('message-section-pager'));
        final gesture = await tester.startGesture(tester.getCenter(pager));
        await gesture.moveBy(Offset(-tester.getSize(pager).width * .25, 0));
        await tester.pump();
        await tester.pump();
        expect(progress.value, inExclusiveRange(0, .5));
        expect(
          container.read(messagesControllerProvider).section,
          InboxSection.private,
        );
        expect(repo.reads, 1);
        expect(outer.value, 7);
        await tester.pump(const Duration(milliseconds: 300));
        if (cancel) {
          await gesture.cancel();
        } else {
          await gesture.up();
        }
        await tester.pumpAndSettle();
        expect(progress.value, 0);
        expect(repo.reads, 1);
        expect(
          container.read(messagesControllerProvider).section,
          InboxSection.private,
        );
      },
    );
  }

  testWidgets('retained message neighbors display their own category rows', (
    tester,
  ) async {
    await mount(tester);
    final replies = const InboxEntry(id: 'reply', title: '回复标题', text: '回复正文');
    final mentions = const InboxEntry(
      id: 'mention',
      title: '提及标题',
      text: '提及正文',
    );
    repo.entries = [replies];
    await tester.tap(find.byKey(const ValueKey('message-section-replies')));
    await tester.pumpAndSettle();
    repo.entries = [mentions];
    await tester.tap(find.byKey(const ValueKey('message-section-mentions')));
    await tester.pumpAndSettle();
    final pager = find.byKey(const ValueKey('message-section-pager'));
    final gesture = await tester.startGesture(tester.getCenter(pager));
    await gesture.moveBy(Offset(tester.getSize(pager).width * .4, 0));
    await tester.pump();
    expect(find.text('回复正文'), findsOneWidget);
    expect(find.text('提及正文'), findsOneWidget);
    expect(repo.reads, 3);
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(find.text('提及正文'), findsOneWidget);
    expect(repo.reads, 3);
  });

  testWidgets('hiding messages interrupts a swipe without loading a section', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await mount(tester, active: active);
    final pager = find.byKey(const ValueKey('message-section-pager'));
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MessagesScreen)),
    );
    final gesture = await tester.startGesture(tester.getCenter(pager));
    await gesture.moveBy(Offset(-tester.getSize(pager).width * .7, 0));
    await tester.pump();
    active.value = false;
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(
      container.read(messagesControllerProvider).section,
      InboxSection.private,
    );
    expect(repo.reads, 1);
    active.value = true;
    await tester.pumpAndSettle();
    await tester.drag(pager, Offset(-tester.getSize(pager).width * .8, 0));
    await tester.pumpAndSettle();
    expect(
      container.read(messagesControllerProvider).section,
      InboxSection.replies,
    );
    expect(repo.reads, 2);
  });

  testWidgets('swiping from a private conversation preserves its draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester);
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '滑动后保留的草稿');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final pager = find.byKey(const ValueKey('message-section-pager'));
    await tester.drag(pager, const Offset(-310, 0));
    await tester.pumpAndSettle();
    await tester.drag(pager, const Offset(310, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    expect(find.text('滑动后保留的草稿'), findsOneWidget);
    expect(repo.sends, 0);
    expect(tester.takeException(), isNull);
  });

  Future<void> mountWithAccount(
    WidgetTester tester, {
    ValueNotifier<bool>? active,
  }) async {
    Widget messages() => ProviderScope(
      overrides: [
        messagesControllerProvider.overrideWith(MessagesController.new),
      ],
      child: const MessagesScreen(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(repo),
          accountMessageIndicatorProvider.overrideWith((ref) {
            final unread = ref.watch(unreadMessagesProvider);
            return AccountMessageIndicator(
              count: unread.value?.values.fold<int>(0, (a, b) => a + b) ?? 0,
            );
          }),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const AccountButton(),
                Expanded(
                  child: active == null
                      ? messages()
                      : ValueListenableBuilder<bool>(
                          valueListenable: active,
                          child: messages(),
                          builder: (_, value, child) =>
                              WorkspaceActivity(active: value, child: child!),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final width in [390.0, 1280.0]) {
    testWidgets('system Back clears conversation and keeps draft at $width', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '返回后保留的草稿');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MessagesScreen)),
      );
      expect(container.read(messagesControllerProvider).selected, isNull);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('另一会话'), findsOneWidget);
      if (width >= 720) {
        expect(find.text('选择一个会话查看消息'), findsOneWidget);
      }
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(find.text('返回后保留的草稿'), findsOneWidget);
      expect(repo.sends, 0);
      expect(repo.marks, 2);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('page Back cancels pending conversation reads', (tester) async {
    final back = PageBackController();
    addTearDown(back.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: PageBackScope(
              controller: back,
              child: const MessagesScreen(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.threadPending = Completer<MessagePage<PrivateMessage>>();
    await tester.tap(find.text('测试会话'));
    await tester.pump();
    await tester.pump();
    expect(back.canGoBack, isTrue);
    expect(back.goBack(), isTrue);
    expect(repo.threadRead?.isCancelled, isTrue);
    repo.threadPending!.complete(
      const MessagePage([privateMessage], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(back.canGoBack, isFalse);
    expect(find.text('测试私信正文'), findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(repo.sends + repo.marks, 0);
  });

  Badge accountBadge(WidgetTester tester) => tester.widget<Badge>(
    find.descendant(
      of: find.byType(AccountButton),
      matching: find.byType(Badge),
    ),
  );

  testWidgets(
    'viewing system notifications updates the avatar without opening it',
    (tester) async {
      repo.counts = {InboxSection.private: 3, InboxSection.system: 2};
      await mountWithAccount(tester);
      expect((accountBadge(tester).label as Text).data, '5');
      repo.entries = const [systemNotification];
      await tester.tap(find.byKey(const ValueKey('message-section-system')));
      await tester.pumpAndSettle();
      expect(find.text('系统通知正文'), findsOneWidget);
      expect(repo.systemMarks, 1);
      expect((accountBadge(tester).label as Text).data, '3');
      expect(find.text('系统通知 · 2'), findsNothing);
      expect(repo.unreadReads, 2);
      await tester.pump();
      expect(repo.systemMarks, 1);
      await tester.tap(find.byKey(const ValueKey('message-section-private')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-section-system')));
      await tester.pumpAndSettle();
      expect(repo.unreadReads, 2);
      expect((accountBadge(tester).label as Text).data, '3');
    },
  );

  for (final section in [
    InboxSection.replies,
    InboxSection.mentions,
    InboxSection.likes,
  ]) {
    testWidgets('viewing ${section.name} refreshes the avatar count', (
      tester,
    ) async {
      repo.counts = {InboxSection.private: 3, section: 2};
      await mountWithAccount(tester);
      final tabLabel = switch (section) {
        InboxSection.replies => '回复',
        InboxSection.mentions => '我的',
        _ => section.label,
      };
      expect(find.text('$tabLabel · 2'), findsOneWidget);
      expect((accountBadge(tester).label as Text).data, '5');
      await tester.tap(find.byKey(ValueKey('message-section-${section.name}')));
      await tester.pumpAndSettle();
      expect(find.text(tabLabel), findsOneWidget);
      expect(find.text('$tabLabel · 2'), findsNothing);
      expect(
        ProviderScope.containerOf(tester.element(find.byType(MessagesScreen)))
            .read(messagesControllerProvider)
            .section,
        section,
      );
      expect((accountBadge(tester).label as Text).data, '3');
      final expectedReads = section == InboxSection.likes ? 1 : 2;
      expect(repo.unreadReads, expectedReads);
      await tester.tap(find.byKey(const ValueKey('message-section-private')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('message-section-${section.name}')));
      await tester.pumpAndSettle();
      expect(repo.unreadReads, expectedReads);
    });
  }

  testWidgets('an empty likes list clears the tab and avatar unread count', (
    tester,
  ) async {
    repo.counts = {InboxSection.private: 3, InboxSection.likes: 2};
    await mountWithAccount(tester);
    repo.entries = [];
    await tester.tap(find.byKey(const ValueKey('message-section-likes')));
    await tester.pumpAndSettle();
    expect(find.text('收到的赞 · 2'), findsNothing);
    expect((accountBadge(tester).label as Text).data, '3');
    expect(repo.unreadReads, 1);
    expect(repo.counts[InboxSection.likes], 2);
    expect(repo.sends + repo.marks + repo.systemMarks, 0);
  });

  testWidgets(
    'failed likes loading preserves the tab and avatar unread count',
    (tester) async {
      repo.counts = {InboxSection.private: 3, InboxSection.likes: 2};
      await mountWithAccount(tester);
      repo.inboxFailure = const AppFailure(AppFailureKind.network, 'offline');
      await tester.tap(find.byKey(const ValueKey('message-section-likes')));
      await tester.pumpAndSettle();
      expect(find.text('收到的赞 · 2'), findsOneWidget);
      expect((accountBadge(tester).label as Text).data, '5');
      expect(repo.unreadReads, 1);
    },
  );

  testWidgets('refreshing shared unread counts also updates the avatar', (
    tester,
  ) async {
    repo.counts = {InboxSection.private: 3, InboxSection.likes: 2};
    await mountWithAccount(tester);
    await tester.tap(find.byKey(const ValueKey('message-section-likes')));
    await tester.pumpAndSettle();
    expect((accountBadge(tester).label as Text).data, '3');
    repo.counts = {InboxSection.private: 1, InboxSection.likes: 0};
    await tester.tap(find.byTooltip('刷新消息'));
    await tester.pumpAndSettle();
    expect((accountBadge(tester).label as Text).data, '1');
    expect(repo.unreadReads, 2);
  });

  testWidgets('switching read categories never refreshes the avatar count', (
    tester,
  ) async {
    await mountWithAccount(tester);
    expect(repo.unreadReads, 1);
    repo.entries = const [systemNotification];
    for (var round = 0; round < 2; round++) {
      for (final section in [
        InboxSection.replies,
        InboxSection.mentions,
        InboxSection.likes,
        InboxSection.system,
        InboxSection.private,
      ]) {
        await tester.tap(
          find.byKey(ValueKey('message-section-${section.name}')),
        );
        await tester.pumpAndSettle();
        expect(repo.unreadReads, 1, reason: '$round: ${section.name}');
        expect((accountBadge(tester).label as Text).data, '3');
      }
    }
  });

  testWidgets(
    'opening a private conversation automatically updates the avatar from a page scope',
    (tester) async {
      await mountWithAccount(tester);
      expect(accountBadge(tester).isLabelVisible, isTrue);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(repo.marks, 1);
      expect(accountBadge(tester).isLabelVisible, isFalse);
      expect(find.text('私信 · 3'), findsNothing);
      expect(repo.lastAck, privateMessage.sequence);
      expect(find.text('已标为已读'), findsNothing);
      await tester.pump();
      expect(repo.marks, 1);
    },
  );

  testWidgets('a hidden private thread is acknowledged only when shown', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await mountWithAccount(tester, active: active);
    final pending = repo.threadPending =
        Completer<MessagePage<PrivateMessage>>();
    await tester.tap(find.text('测试会话'));
    await tester.pump();
    active.value = false;
    await tester.pump();
    pending.complete(const MessagePage([privateMessage], hasMore: false));
    await tester.pumpAndSettle();
    expect(repo.marks, 0);
    active.value = true;
    await tester.pumpAndSettle();
    expect(repo.marks, 1);
    active.value = false;
    await tester.pump();
    active.value = true;
    await tester.pumpAndSettle();
    expect(repo.marks, 1);
  });

  testWidgets(
    'private badges update only after the automatic receipt succeeds',
    (tester) async {
      repo.counts = {InboxSection.private: 3, InboxSection.replies: 2};
      final pending = repo.writePending = Completer<void>();
      await mountWithAccount(tester);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      Badge conversationBadge() => tester.widget<Badge>(
        find.descendant(
          of: find.byKey(const ValueKey('1:2')),
          matching: find.byType(Badge),
        ),
      );
      expect(repo.marks, 1);
      expect(conversationBadge().isLabelVisible, isTrue);
      expect((accountBadge(tester).label as Text).data, '5');
      repo.entries = const [
        InboxEntry(id: '1:2', title: '测试会话', text: '消息摘要', sessionType: 1),
        otherConversation,
      ];
      pending.complete();
      await tester.pumpAndSettle();
      expect(conversationBadge().isLabelVisible, isFalse);
      expect(find.text('私信 · 3'), findsNothing);
      expect(find.text('回复 · 2'), findsOneWidget);
      expect((accountBadge(tester).label as Text).data, '2');
      expect(repo.marks, 1);
    },
  );

  testWidgets(
    'a newly selected unread conversation waits for an in-flight receipt',
    (tester) async {
      repo.entries = const [
        conversation,
        InboxEntry(
          id: '1:3',
          title: '另一会话',
          text: '另一摘要',
          sessionType: 1,
          unread: 2,
        ),
      ];
      final pending = repo.writePending = Completer<void>();
      await mount(tester);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('另一会话'));
      await tester.pumpAndSettle();
      expect(repo.marks, 1);
      repo.writePending = null;
      pending.complete();
      await tester.pumpAndSettle();
      expect(repo.lastThread?.id, '1:3');
      expect(repo.marks, 2);
    },
  );

  testWidgets(
    'failed private acknowledgement preserves badges without replaying on rebuild',
    (tester) async {
      repo.writeFailure = const AppFailure(AppFailureKind.timeout, 'timeout');
      await mountWithAccount(tester);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(repo.marks, 1);
      expect(find.textContaining('尚未确认'), findsOneWidget);
      expect(find.text('私信 · 3'), findsOneWidget);
      expect((accountBadge(tester).label as Text).data, '3');
      final container = ProviderScope.containerOf(
        tester.element(find.byType(MessagesScreen)),
      );
      container.invalidate(unreadMessagesProvider);
      await tester.pumpAndSettle();
      expect(repo.marks, 1);
      repo.writeFailure = null;
      await tester.tap(find.byTooltip('刷新会话'));
      await tester.pumpAndSettle();
      expect(repo.marks, 2);
      expect(accountBadge(tester).isLabelVisible, isFalse);
    },
  );

  testWidgets(
    'switching conversations ignores a late thread before automatic read',
    (tester) async {
      final pending = repo.threadPending =
          Completer<MessagePage<PrivateMessage>>();
      await mount(tester);
      await tester.tap(find.text('测试会话'));
      await tester.pump();
      repo.threadPending = null;
      await tester.tap(find.text('另一会话'));
      await tester.pumpAndSettle();
      pending.complete(const MessagePage([privateMessage], hasMore: false));
      await tester.pumpAndSettle();
      expect(repo.lastThread?.id, otherConversation.id);
      expect(repo.marks, 0);
      expect(repo.counts[InboxSection.private], 3);
    },
  );

  testWidgets('hidden system list waits until visible before acknowledging', (
    tester,
  ) async {
    final active = ValueNotifier(true);
    addTearDown(active.dispose);
    await mountWithAccount(tester, active: active);
    final pending = repo.inboxPending = Completer<MessagePage<InboxEntry>>();
    await tester.tap(find.byKey(const ValueKey('message-section-system')));
    await tester.pump();
    active.value = false;
    await tester.pump();
    pending.complete(const MessagePage([systemNotification], hasMore: false));
    await tester.pumpAndSettle();
    expect(repo.systemMarks, 0);
    active.value = true;
    await tester.pumpAndSettle();
    expect(repo.systemMarks, 1);
    active.value = false;
    await tester.pump();
    active.value = true;
    await tester.pumpAndSettle();
    expect(repo.systemMarks, 1);
  });

  testWidgets(
    'failed automatic read keeps unread badge and offers refresh guidance',
    (tester) async {
      repo.counts = {InboxSection.system: 2};
      repo.writeFailure = const AppFailure(AppFailureKind.timeout, 'timeout');
      await mountWithAccount(tester);
      repo.entries = const [systemNotification];
      await tester.tap(find.byKey(const ValueKey('message-section-system')));
      await tester.pumpAndSettle();
      expect(repo.systemMarks, 1);
      expect(find.textContaining('尚未确认'), findsOneWidget);
      expect((accountBadge(tester).label as Text).data, '2');
      await tester.pump();
      expect(repo.systemMarks, 1);
    },
  );

  testWidgets(
    'narrow message tabs scroll by mouse wheel and switch without writes',
    (tester) async {
      tester.view.physicalSize = const Size(320, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, scale: 2, platform: TargetPlatform.windows);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(MessagesScreen)),
      );
      expect(find.text('私信 · 3'), findsOneWidget);
      final strip = find.byKey(const ValueKey('message-section-strip'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: strip, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(strip),
          scrollDelta: const Offset(0, 2000),
        ),
      );
      await tester.pumpAndSettle();
      final system = find.byKey(const ValueKey('message-section-system'));
      expect(system.hitTestable(), findsOneWidget);
      await tester.tap(system);
      await tester.pumpAndSettle();
      expect(
        scope.read(messagesControllerProvider).section,
        InboxSection.system,
      );
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(strip),
          scrollDelta: const Offset(0, -2000),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('message-section-private')));
      await tester.pumpAndSettle();
      expect(
        scope.read(messagesControllerProvider).section,
        InboxSection.private,
      );
      expect(repo.sends, 0);
      expect(repo.marks, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'wide inbox acknowledges a displayed conversation automatically',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await mount(tester);
      expect(find.text('回复'), findsOneWidget);
      expect(find.text('我的'), findsOneWidget);
      expect(find.text('回复我的'), findsNothing);
      expect(find.text('@我的'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('message-section-replies')),
          matching: find.byIcon(Icons.reply_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('message-section-mentions')),
          matching: find.byIcon(Icons.alternate_email_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('系统通知'), findsOneWidget);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(find.text('测试私信正文'), findsOneWidget);
      expect(find.text('另一会话'), findsOneWidget);
      expect(repo.marks, 1);
      await tester.tap(find.byTooltip('标为已读'));
      await tester.pumpAndSettle();
      expect(repo.marks, 2);
    },
  );
  testWidgets(
    'narrow high text scale switches back to inbox without overflow',
    (tester) async {
      tester.view.physicalSize = const Size(375, 700);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await mount(tester, scale: 2);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('返回会话列表'));
      await tester.pumpAndSettle();
      expect(find.text('另一会话'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('failed send retains draft and reports uncertain outcome', (
    tester,
  ) async {
    await mount(tester);
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    repo.writeFailure = const AppFailure(AppFailureKind.timeout, 'timeout');
    await tester.enterText(find.byType(TextField), '保留的草稿');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(find.text('保留的草稿'), findsOneWidget);
    expect(repo.sends, 1);
    expect(find.textContaining('尚未确认'), findsOneWidget);
  });
  testWidgets('logout removes private contents and drafts', (tester) async {
    await mount(tester);
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '私有草稿');
    repo.accountScope = 'guest';
    repo.sessionEpoch++;
    auth.emit(const AuthState());
    await tester.pumpAndSettle();
    expect(find.text('测试私信正文'), findsNothing);
    expect(find.text('私有草稿'), findsNothing);
    expect(find.text('登录后查看我的消息'), findsOneWidget);
  });
  testWidgets('successful send clears draft across a conversation switch', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1100, 760);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await mount(tester);
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    repo.writePending = Completer<void>();
    await tester.enterText(find.byType(TextField), '发送期间的草稿');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('另一会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    expect(find.text('发送期间的草稿'), findsOneWidget);
    repo.writePending?.complete();
    await tester.pumpAndSettle();
    expect(find.text('发送期间的草稿'), findsNothing);
    expect(repo.sends, 1);
  });
}
