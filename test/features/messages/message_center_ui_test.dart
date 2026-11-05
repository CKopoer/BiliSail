import 'dart:async';
import 'dart:convert';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/messages/application/message_center_controller.dart';
import 'package:bilisail/features/messages/application/message_image_picker.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_center_repository.dart';
import 'package:bilisail/features/messages/domain/message_composer.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/message_rich_text.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/features/messages/presentation/private_message_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester,
    _RichMessages messages,
    _CenterFake center, {
    double width = 390,
    Future<MessageLocalImage?> Function()? picker,
    bool workspaceScope = false,
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
          messageImagePickerProvider.overrideWithValue(
            picker ?? () async => null,
          ),
        ],
        child: MaterialApp(
          builder: AppNoticeHost.builder,
          home: Scaffold(
            body: ValueListenableBuilder<bool>(
              valueListenable:
                  pageVisible ?? const AlwaysStoppedAnimation(true),
              builder: (_, visible, _) => !visible
                  ? const SizedBox.shrink()
                  : workspaceScope
                  ? ProviderScope(
                      // Match the controller scope used by workspace pages.
                      overrides: [
                        messagesControllerProvider.overrideWith(
                          MessagesController.new,
                        ),
                      ],
                      child: const MessagesScreen(),
                    )
                  : const MessagesScreen(),
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

  testWidgets('outer actions expose native message settings and contacts', (
    tester,
  ) async {
    final center = _CenterFake();
    await mount(tester, _RichMessages(), center);
    expect(find.byTooltip('刷新消息'), findsNothing);
    expect(find.byTooltip('官方消息页'), findsNothing);
    await tester.tap(find.byTooltip('更多消息操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('消息设置'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButton<int>), findsNWidgets(2));
    expect(find.text('消息提醒'), findsOneWidget);
    await tester.tap(find.text('关闭').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('更多消息操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('通讯录'));
    await tester.pumpAndSettle();
    expect(find.text('暂无记录'), findsOneWidget);
    expect(center.peopleKind, MessagePeopleKind.contacts);
  });

  for (final other in [false, true]) {
    testWidgets('chat report validates description only for other=$other', (
      tester,
    ) async {
      final center = _CenterFake();
      await mount(tester, _RichMessages(), center, workspaceScope: true);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('举报会话'));
      await tester.tap(find.text('举报会话'));
      await tester.pumpAndSettle();
      if (other) {
        await tester.tap(find.byType(DropdownButton<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('其他').last);
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('提交举报'));
      await tester.pumpAndSettle();
      if (other) {
        expect(center.reports, isEmpty);
        expect(find.text('选择“其他”时请补充说明'), findsOneWidget);
        await tester.enterText(
          find.descendant(
            of: find.byType(AlertDialog).last,
            matching: find.byType(TextField),
          ),
          '补充具体情况',
        );
        await tester.tap(find.text('提交举报'));
        await tester.pumpAndSettle();
        expect(center.reports, [(0, '补充具体情况')]);
      } else {
        expect(center.reports, [(4, '广告骚扰')]);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'batch read confirms the precise loaded range before submitting',
    (tester) async {
      final center = _CenterFake();
      await mount(tester, _RichMessages(), center);
      await tester.tap(find.byTooltip('已加载私信一键已读'));
      await tester.pumpAndSettle();
      expect(center.acknowledgements, isEmpty);
      expect(find.textContaining('1 个已加载会话'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(center.acknowledgements.map((entry) => entry.id), [
        conversation.id,
      ]);
      expect(find.text('已将 1 个已加载私信会话标为已读'), findsOneWidget);
    },
  );

  testWidgets(
    'chat uses one narrow header and settings continue working after pinning',
    (tester) async {
      final center = _CenterFake();
      final messages = _RichMessages();
      final container = await mount(
        tester,
        messages,
        center,
        workspaceScope: true,
      );
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(find.text('我的消息'), findsNothing);
      expect(find.byTooltip('新增粉丝'), findsNothing);
      expect(find.byTooltip('刷新会话'), findsNothing);
      expect(find.byTooltip('标为已读'), findsNothing);
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();
      expect(find.text('UID 2'), findsOneWidget);
      await tester.tap(find.widgetWithText(SwitchListTile, '置顶会话'));
      await tester.pumpAndSettle();
      expect(messages.pins, 1);
      expect(
        container.read(messagesControllerProvider).selected?.pinned,
        isTrue,
      );
      expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '置顶会话'))
            .value,
        isTrue,
      );
      await tester.tap(find.widgetWithText(SwitchListTile, '接收内容推送'));
      await tester.pumpAndSettle();
      expect(center.pushWrites, 1);
      await tester.tap(find.widgetWithText(SwitchListTile, '加入黑名单'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(center.blockWrites, 1);
    },
  );

  testWidgets(
    'manual read in chat settings disables during thread pagination',
    (tester) async {
      final messages = _RichMessages();
      final container = await mount(
        tester,
        messages,
        _CenterFake(),
        workspaceScope: true,
      );
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      messages.threadPending = Completer<MessagePage<PrivateMessage>>();
      final pending = container
          .read(messagesControllerProvider.notifier)
          .loadThread();
      await tester.pump();
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();
      final tile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, '标为已读'),
      );
      expect(tile.onTap, isNull);
      messages.threadPending!.complete(
        const MessagePage([privateMessage], hasMore: false),
      );
      await pending;
      await tester.pumpAndSettle();
    },
  );

  for (final width in [390.0, 1440.0]) {
    testWidgets('chat settings manage the owning workspace page at $width', (
      tester,
    ) async {
      final messages = _RichMessages();
      final center = _CenterFake();
      final container = await mount(
        tester,
        messages,
        center,
        width: width,
        workspaceScope: true,
      );
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('聊天设置'));
      await tester.pumpAndSettle();

      for (final value in [true, false]) {
        await tester.tap(find.widgetWithText(SwitchListTile, '置顶会话'));
        await tester.pumpAndSettle();
        expect(messages.pinnedValue, value);
        expect(
          container.read(messagesControllerProvider).selected?.pinned,
          value,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '置顶会话'),
              )
              .value,
          value,
        );
        await tester.tap(find.widgetWithText(SwitchListTile, '消息免打扰'));
        await tester.pumpAndSettle();
        expect(messages.mutedValue, value);
        expect(
          container.read(messagesControllerProvider).selected?.muted,
          value,
        );
        expect(
          tester
              .widget<SwitchListTile>(
                find.widgetWithText(SwitchListTile, '消息免打扰'),
              )
              .value,
          value,
        );
      }
      expect(messages.pins, 2);
      expect(messages.mutes, 2);

      final marks = messages.marks;
      await tester.tap(find.widgetWithText(ListTile, '标为已读'));
      await tester.pumpAndSettle();
      expect(messages.marks, marks + 1);
      messages.messages = const [];
      await tester.tap(find.widgetWithText(ListTile, '重新加载会话'));
      await tester.pumpAndSettle();
      expect(container.read(messagesControllerProvider).thread.items, isEmpty);

      await tester.ensureVisible(find.text('移除当前会话'));
      await tester.tap(find.text('移除当前会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(messages.removals, 0);
      await tester.tap(find.text('移除当前会话'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确认'));
      await tester.pumpAndSettle();
      expect(messages.removals, 1);
      expect(container.read(messagesControllerProvider).selected, isNull);
      expect(
        container.read(messagesControllerProvider).inbox.items.map((e) => e.id),
        [otherConversation.id],
      );
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('chat settings show failures and disable pending management', (
    tester,
  ) async {
    final messages = _RichMessages()
      ..managementFailure = const AppFailure(AppFailureKind.timeout, 'timeout');
    final container = await mount(
      tester,
      messages,
      _CenterFake(),
      workspaceScope: true,
    );
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('聊天设置'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SwitchListTile, '置顶会话'));
    await tester.pumpAndSettle();
    expect(messages.pins, 1);
    expect(
      container.read(messagesControllerProvider).selected?.pinned,
      isFalse,
    );
    final scrollable = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(Scrollable),
    );
    final errorMessage = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining('尚未确认'),
    );
    await tester.scrollUntilVisible(errorMessage, 250, scrollable: scrollable);
    expect(errorMessage, findsOneWidget);
    final pending = messages.managementPending = Completer<void>();
    messages.managementFailure = null;
    await tester.scrollUntilVisible(
      find.widgetWithText(SwitchListTile, '消息免打扰'),
      -250,
      scrollable: scrollable,
    );
    await tester.tap(find.widgetWithText(SwitchListTile, '消息免打扰'));
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, '置顶会话'))
          .onChanged,
      isNull,
    );
    expect(
      tester.widget<ListTile>(find.widgetWithText(ListTile, '重新加载会话')).onTap,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(messages.mutes, 1);
    expect(container.read(messagesControllerProvider).selected?.muted, isTrue);
  });

  for (final removePage in [false, true]) {
    for (final block in [false, true]) {
      testWidgets(
        'chat confirmation rejects stale origin: removed=$removePage block=$block',
        (tester) async {
          final messages = _RichMessages();
          final center = _CenterFake();
          final visible = ValueNotifier(true);
          addTearDown(visible.dispose);
          await mount(
            tester,
            messages,
            center,
            workspaceScope: true,
            pageVisible: visible,
          );
          await tester.tap(find.text('测试会话'));
          await tester.pumpAndSettle();
          await tester.tap(find.byTooltip('聊天设置'));
          await tester.pumpAndSettle();
          final target = block ? '加入黑名单' : '移除当前会话';
          await tester.ensureVisible(find.text(target));
          await tester.tap(find.text(target));
          await tester.pumpAndSettle();
          if (removePage) {
            visible.value = false;
            await tester.pump();
          } else {
            messages.sessionEpoch++;
          }
          await tester.tap(find.widgetWithText(FilledButton, '确认'));
          await tester.pumpAndSettle();
          expect(messages.removals, 0);
          expect(center.blockWrites, 0);
          expect(tester.takeException(), isNull);
          await tester.tap(find.widgetWithText(TextButton, '关闭'));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets('emote selection inserts the token at the draft cursor', (
    tester,
  ) async {
    final messages = _RichMessages();
    await mount(tester, messages, _CenterFake());
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.byTooltip('私信表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('[微笑]'));
    await tester.pumpAndSettle();
    expect(find.text('你好[微笑]'), findsOneWidget);
    expect(messages.sends, 0);
  });

  testWidgets(
    'selecting an image previews it and sends only after explicit action',
    (tester) async {
      final messages = _RichMessages();
      final image = MessageLocalImage(
        bytes: base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=',
        ),
        mimeType: 'image/png',
      );
      await mount(tester, messages, _CenterFake(), picker: () async => image);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '仍保留的文字草稿');
      await tester.tap(find.byTooltip('选择私信图片'));
      await tester.pumpAndSettle();
      expect(messages.imageSends, 0);
      expect(find.text('图片将单独发送'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '发送图片'));
      await tester.pumpAndSettle();
      expect(messages.imageSends, 1);
      expect(messages.sends, 0);
      expect(find.text('仍保留的文字草稿'), findsOneWidget);
      expect(find.text('图片将单独发送'), findsNothing);
    },
  );

  testWidgets(
    'inline emotes are private images and only trusted links become actions',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MessageRichText(
              text: '[微笑] [未知] https://www.bilibili.com/video/BV1xx411c7mD https://example.test/other',
              emotes: {'[微笑]': Uri.https('example.test', '/emote.png')},
              onOpenTarget: (_) {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(PrivateMessageImage), findsOneWidget);
      final text = tester.widget<SelectableText>(find.byType(SelectableText));
      final spans = text.textSpan!.children!;
      expect(
        spans.whereType<TextSpan>().where(
          (span) => span.recognizer is TapGestureRecognizer,
        ),
        hasLength(1),
      );
      expect(
        spans.whereType<TextSpan>().map((span) => span.text).join(),
        contains('[未知]'),
      );
    },
  );
}

class _RichMessages extends ManagementMessageRepositoryFake
    implements MessageComposeRepository {
  int imageSends = 0;
  @override
  Future<List<MessageEmotePackage>> emotes({
    required RequestCancellation cancellation,
  }) async => const [
    MessageEmotePackage('基础表情', [MessageEmote('[微笑]', null)]),
  ];
  @override
  Future<void> sendImage(
    InboxEntry entry,
    MessageLocalImage image, {
    required RequestCancellation cancellation,
  }) async {
    imageSends++;
  }
}

class _CenterFake extends Fake implements MessageCenterRepository {
  final reports = <(int, String)>[];
  @override
  Future<void> reportConversation(
    InboxEntry entry,
    int reason,
    String text, {
    required RequestCancellation cancellation,
  }) async {
    reports.add((reason, text));
  }

  @override
  String get accountScope => 'user:1';
  @override
  int get sessionEpoch => 1;
  int pushWrites = 0, blockWrites = 0;
  MessagePeopleKind? peopleKind;
  List<InboxEntry> acknowledgements = [];
  @override
  Future<MessageCenterSettings> settings({
    required RequestCancellation cancellation,
  }) async => const MessageCenterSettings({
    MessageSetting.notification: 1,
    MessageSetting.reply: 0,
  });
  @override
  Future<ChatMessageSettings> chatSettings(
    InboxEntry entry, {
    required RequestCancellation cancellation,
  }) async => ChatMessageSettings(
    entryId: entry.id,
    contentPush: true,
    showContentPush: true,
    blocked: false,
  );
  @override
  Future<void> setContentPush(
    InboxEntry entry,
    bool enabled, {
    required RequestCancellation cancellation,
  }) async {
    pushWrites++;
  }

  @override
  Future<void> setBlocked(
    InboxEntry entry,
    bool blocked, {
    required RequestCancellation cancellation,
  }) async {
    blockWrites++;
  }

  @override
  Future<MessagePage<MessagePerson>> people(
    MessagePeopleKind kind, {
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    peopleKind = kind;
    return const MessagePage([], hasMore: false);
  }

  @override
  Future<MarkPrivateReadResult> markAllPrivateRead(
    List<InboxEntry> entries, {
    required RequestCancellation cancellation,
  }) async {
    acknowledgements = entries;
    return MarkPrivateReadResult(
      requested: entries.length,
      acknowledged: entries.length,
    );
  }
}
