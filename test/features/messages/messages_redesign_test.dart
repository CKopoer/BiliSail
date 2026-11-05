import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_management.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/message_content_view.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester, {
    required double width,
    double scale = 1,
    MessageRepositoryFake? repository,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthFake();
    addTearDown(auth.stream.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(
            repository ?? MessageRepositoryFake(),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: const Scaffold(body: MessagesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MessagesScreen)),
    );
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'narrow inbox exposes four shortcuts and category Back at $width',
      (tester) async {
        final container = await mount(tester, width: width, scale: 2);
        expect(find.byKey(const ValueKey('message-shortcuts')), findsOneWidget);
        expect(find.text('测试会话'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('message-section-replies')));
        await tester.pumpAndSettle();
        expect(find.byTooltip('返回消息首页'), findsOneWidget);
        expect(
          container.read(messagesControllerProvider).section,
          InboxSection.replies,
        );
        await tester.tap(find.byTooltip('返回消息首页'));
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('message-shortcuts')), findsOneWidget);
        expect(
          container.read(messagesControllerProvider).section,
          InboxSection.private,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'wide inbox has category rail, conversation list and readable body',
    (tester) async {
      await mount(tester, width: 1200);
      expect(find.byKey(const ValueKey('message-sidebar')), findsOneWidget);
      expect(find.text('选择一个会话查看消息'), findsOneWidget);
      final railTop = tester
          .getTopLeft(find.byKey(const ValueKey('message-sidebar')))
          .dy;
      final firstCategoryTop = tester
          .getTopLeft(find.byKey(const ValueKey('message-section-private')))
          .dy;
      expect(firstCategoryTop - railTop, inInclusiveRange(0, 20));
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(find.text('另一会话'), findsOneWidget);
      expect(find.text('测试私信正文'), findsOneWidget);
      final listRect = tester.getRect(find.byKey(const ValueKey('1:3')));
      final bodyRect = tester.getRect(find.text('测试私信正文'));
      expect(bodyRect.left, greaterThan(listRect.right));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('search and unread filter affect only loaded conversations', (
    tester,
  ) async {
    await mount(tester, width: 390);
    await tester.tap(find.byKey(const ValueKey('message-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      '另一',
    );
    await tester.pumpAndSettle();
    expect(find.text('另一会话'), findsOneWidget);
    expect(find.text('测试会话'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('message-unread-filter')));
    await tester.pumpAndSettle();
    expect(find.text('已加载的会话中没有匹配结果'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('message-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('测试会话'), findsOneWidget);
    expect(find.text('另一会话'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation filters survive category switches and resize', (
    tester,
  ) async {
    await mount(tester, width: 390);
    await tester.tap(find.byKey(const ValueKey('message-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('message-search-field')),
      '另一',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('message-section-system')));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回消息首页'));
    await tester.pumpAndSettle();
    expect(find.text('另一会话'), findsOneWidget);
    expect(find.text('测试会话'), findsNothing);
    tester.view.physicalSize = const Size(1200, 900);
    await tester.pumpAndSettle();
    expect(find.text('另一会话'), findsOneWidget);
    expect(find.text('测试会话'), findsNothing);
    expect(find.text('另一'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('conversation draft survives wide to narrow and back', (
    tester,
  ) async {
    await mount(tester, width: 1200);
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '缩放窗口后继续输入');
    for (final width in [390.0, 1200.0, 320.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpAndSettle();
      expect(find.text('缩放窗口后继续输入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'management menu requires confirmation before removing conversation',
    (tester) async {
      final repository = _ManagedRepository();
      final container = await mount(tester, width: 390, repository: repository);
      await tester.tap(find.byKey(const ValueKey('message-menu-1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('置顶会话'));
      await tester.pumpAndSettle();
      expect(
        container.read(messagesControllerProvider).inbox.items.first.pinned,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('message-menu-1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('消息免打扰'));
      await tester.pumpAndSettle();
      expect(
        container.read(messagesControllerProvider).inbox.items.first.muted,
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('message-menu-1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除会话'));
      await tester.pumpAndSettle();
      expect(repository.removals, 0);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('测试会话'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('message-menu-1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pumpAndSettle();
      expect(repository.removals, 1);
      expect(find.text('测试会话'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remove confirmation resolves refreshed row only within the same account',
    (tester) async {
      final repository = _ManagedRepository();
      final container = await mount(tester, width: 390, repository: repository);
      await tester.tap(find.byKey(const ValueKey('message-menu-1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除会话'));
      await tester.pumpAndSettle();
      repository.entries = const [
        InboxEntry(
          id: '1:2',
          title: '更新后的会话',
          text: '新摘要',
          userId: UserId('2'),
          sessionType: 1,
        ),
        otherConversation,
      ];
      await container
          .read(messagesControllerProvider.notifier)
          .loadInbox(refresh: true);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pumpAndSettle();
      expect(repository.removals, 1);
      expect(find.text('更新后的会话'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'remove confirmation cannot target a replacement account with the same talker',
    (tester) async {
      final repository = _ManagedRepository();
      final container = await mount(tester, width: 390, repository: repository);
      await tester.tap(find.byKey(const ValueKey('message-menu-1:2')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('移除会话'));
      await tester.pumpAndSettle();
      repository.accountScope = 'user:9';
      repository.sessionEpoch++;
      (container.read(authRepositoryProvider) as AuthFake).emit(
        const AuthState(
          status: AuthStatus.signedIn,
          mid: '9',
          userName: '另一个账号',
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '移除'));
      await tester.pumpAndSettle();
      expect(repository.removals, 0);
      expect(find.text('测试会话'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'malformed image shows fallback and covered shares retain target action',
    (tester) async {
      final target = Uri.https('www.bilibili.com', '/video/BV1xx411c7mD');
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Column(
                children: [
                  const MessageContentView(
                    message: PrivateMessage(
                      id: '1',
                      sequence: '1',
                      senderId: UserId('2'),
                      type: 2,
                      kind: MessageContentKind.unsupported,
                      text: '图片内容无法解析',
                    ),
                  ),
                  MessageContentView(
                    message: PrivateMessage(
                      id: '2',
                      sequence: '2',
                      senderId: const UserId('2'),
                      type: 11,
                      kind: MessageContentKind.video,
                      text: '视频介绍',
                      title: '分享的视频',
                      imageUrl: Uri.https('example.test', '/cover.jpg'),
                      targetUrl: target,
                    ),
                    onOpenTarget: opened.add,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('图片内容无法解析'), findsOneWidget);
      await tester.tap(find.text('查看分享内容'));
      expect(opened, [target]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'normalized content renders details, cards and independent actions',
    (tester) async {
      final target = Uri.https('www.bilibili.com', '/video/BV1xx411c7mD');
      final opened = <Uri>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 320,
                child: MessageContentView(
                  message: PrivateMessage(
                    id: '1',
                    sequence: '1',
                    senderId: const UserId('2'),
                    type: 10,
                    kind: MessageContentKind.notification,
                    title: '业务通知',
                    text: '这是一条业务通知',
                    subtitle: '通知摘要',
                    details: const [MessageDetail(label: '状态', value: '已完成')],
                    cards: [
                      MessageCard(
                        title: '分享视频',
                        description: '补充说明',
                        targetUrl: target,
                      ),
                    ],
                    links: [MessageLink(label: '查看结果', url: target)],
                  ),
                  onOpenTarget: opened.add,
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('业务通知'), findsOneWidget);
      expect(find.text('已完成'), findsOneWidget);
      await tester.tap(find.text('分享视频'));
      await tester.tap(find.text('查看结果'));
      expect(opened, [target, target]);
      expect(tester.takeException(), isNull);
    },
  );
}

class _ManagedRepository extends MessageRepositoryFake
    implements MessageManagementRepository {
  int removals = 0;
  @override
  Future<void> setPinned(
    InboxEntry entry,
    bool pinned, {
    required RequestCancellation cancellation,
  }) async {}
  @override
  Future<void> setMuted(
    InboxEntry entry,
    bool muted, {
    required RequestCancellation cancellation,
  }) async {}
  @override
  Future<void> removeConversation(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  }) async {
    removals++;
  }
}
