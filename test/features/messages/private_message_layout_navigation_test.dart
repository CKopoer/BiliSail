import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/message_center_controller.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_center_repository.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/message_content_view.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

const _assistants = [
  InboxEntry(
    id: '1:844424930131966',
    title: '创作助手',
    text: '系统助手会话',
    userId: UserId('844424930131966'),
    sessionType: 1,
    system: true,
  ),
  InboxEntry(
    id: '1:844424930131964',
    title: '创作助手',
    text: '系统助手会话',
    userId: UserId('844424930131964'),
    sessionType: 1,
    system: true,
  ),
  InboxEntry(
    id: '1:900000000000003',
    title: '社区会话',
    text: '系统助手会话',
    userId: UserId('900000000000003'),
    sessionType: 1,
    system: true,
  ),
];

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester,
    MessageRepositoryFake messages, {
    required double width,
    MessageCenterRepository? center,
    ValueNotifier<bool>? pageVisible,
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
          messageRepositoryProvider.overrideWithValue(messages),
          messageCenterRepositoryProvider.overrideWithValue(center),
        ],
        child: MaterialApp(
          home: Scaffold(
            // Match the workspace: the page owns its controller below the root
            // Navigator, while account repositories live above that Navigator.
            body: ValueListenableBuilder<bool>(
              valueListenable:
                  pageVisible ?? const AlwaysStoppedAnimation(true),
              builder: (_, visible, child) =>
                  visible ? child! : const SizedBox.shrink(),
              child: ProviderScope(
                overrides: [
                  messagesControllerProvider.overrideWith(
                    MessagesController.new,
                  ),
                ],
                child: const MessagesScreen(),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MessagesScreen)),
    );
  }

  for (final width in [390.0, 1280.0, 1800.0]) {
    testWidgets('chat avatars follow both viewport edges at $width', (
      tester,
    ) async {
      final messages = MessageRepositoryFake()
        ..messages = const [
          privateMessage,
          PrivateMessage(
            id: 'own-message',
            sequence: '2',
            senderId: UserId('1'),
            text:
                '自己的长消息保持阅读宽度，头像则跟随聊天区域边界。'
                '窗口足够宽时，正文气泡依然限制宽度，不随整个聊天区域无限拉伸。'
                '窄屏时正文自然换行，头像与消息之间保持间距，左右气泡不会越过窗口。',
            type: 1,
          ),
        ];
      await mount(tester, messages, width: width);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      final chat = tester.getRect(
        find
            .ancestor(of: find.byTooltip('聊天设置'), matching: find.byType(Column))
            .first,
      );
      final received = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('1')),
          matching: find.byType(NetworkAvatar),
        ),
      );
      final sent = tester.getRect(
        find.descendant(
          of: find.byKey(const ValueKey('own-message')),
          matching: find.byType(NetworkAvatar),
        ),
      );
      expect(received.left, closeTo(chat.left + 16, 1));
      expect(sent.right, closeTo(chat.right - 16, 1));
      for (final content in tester.widgetList<MessageContentView>(
        find.byType(MessageContentView),
      )) {
        expect(
          tester.getSize(find.byWidget(content)).width,
          lessThanOrEqualTo(460),
        );
      }
      final ownBubble = tester.getSize(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (widget) =>
                    widget is MessageContentView &&
                    widget.message.id == 'own-message',
              ),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(ownBubble.width, lessThanOrEqualTo(460));
      if (width >= 1280) expect(ownBubble.width, 460);
      expect(tester.takeException(), isNull);
    });
  }

  for (final width in [390.0, 1440.0]) {
    for (var index = 0; index < _assistants.length; index++) {
      final assistant = _assistants[index];
      final titleIndex = index == 1 ? 1 : 0;
      testWidgets('assistant ${assistant.id} opens the page chat at $width', (
        tester,
      ) async {
        final messages = MessageRepositoryFake();
        final page = await mount(
          tester,
          messages,
          width: width,
          center: _AssistantRepository(),
        );
        await tester.tap(find.byTooltip('更多消息操作'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('UP 助手'));
        await tester.pumpAndSettle();
        await tester.tap(
          find.widgetWithText(ListTile, assistant.title).at(titleIndex),
        );
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          page.read(messagesControllerProvider).section,
          InboxSection.private,
        );
        expect(
          page.read(messagesControllerProvider).selected?.id,
          assistant.id,
        );
        expect(messages.lastThread?.userId, assistant.userId);
        expect(find.text('测试私信正文'), findsOneWidget);
        expect(find.text('此会话仅支持查看'), findsOneWidget);
        expect(messages.sends, 0);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'account switch closes assistant dialog and ignores its late list',
    (tester) async {
      final messages = MessageRepositoryFake();
      final center = _AssistantRepository()
        ..pending = Completer<MessagePage<InboxEntry>>();
      final page = await mount(tester, messages, width: 390, center: center);
      await tester.tap(find.byTooltip('更多消息操作'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('UP 助手'));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(AlertDialog), findsOneWidget);
      messages.accountScope = center.accountScope = 'user:9';
      messages.sessionEpoch = center.sessionEpoch = 2;
      (page.read(authRepositoryProvider) as AuthFake).emit(
        const AuthState(status: AuthStatus.signedIn, userName: '新账号', mid: '9'),
      );
      await tester.pump();
      center.pending!.complete(const MessagePage(_assistants, hasMore: false));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(page.read(messagesControllerProvider).selected, isNull);
      expect(page.read(messageCenterControllerProvider).assistants, isEmpty);
      expect(messages.lastThread, isNull);
      expect(messages.sends + messages.marks, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('assistant from an earlier session epoch cannot open a chat', (
    tester,
  ) async {
    final messages = MessageRepositoryFake();
    final page = await mount(
      tester,
      messages,
      width: 390,
      center: _AssistantRepository(),
    );
    await tester.tap(find.byTooltip('更多消息操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UP 助手'));
    await tester.pumpAndSettle();
    messages.sessionEpoch++;
    await tester.tap(find.widgetWithText(ListTile, '创作助手').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(page.read(messagesControllerProvider).selected, isNull);
    expect(messages.lastThread, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('closing the source page invalidates assistant navigation', (
    tester,
  ) async {
    final messages = MessageRepositoryFake();
    final pageVisible = ValueNotifier(true);
    addTearDown(pageVisible.dispose);
    await mount(
      tester,
      messages,
      width: 390,
      center: _AssistantRepository(),
      pageVisible: pageVisible,
    );
    await tester.tap(find.byTooltip('更多消息操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UP 助手'));
    await tester.pumpAndSettle();
    pageVisible.value = false;
    await tester.pumpAndSettle();
    expect(find.byType(MessagesScreen), findsNothing);
    await tester.tap(find.widgetWithText(ListTile, '创作助手').first);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(messages.lastThread, isNull);
    expect(tester.takeException(), isNull);
  });
}

class _AssistantRepository extends Fake implements MessageCenterRepository {
  @override
  String accountScope = 'user:1';
  @override
  int sessionEpoch = 1;
  Completer<MessagePage<InboxEntry>>? pending;
  @override
  Future<MessagePage<InboxEntry>> assistantSessions(
    MessageAssistantKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async => pending?.future ?? const MessagePage(_assistants, hasMore: false);
}
