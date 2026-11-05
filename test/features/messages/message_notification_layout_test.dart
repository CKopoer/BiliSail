import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/shared/ui/network_avatar.dart';
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
    ValueChanged<Uri>? onOpenTarget,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 900);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
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
          home: Scaffold(body: MessagesScreen(onOpenTarget: onOpenTarget)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return ProviderScope.containerOf(
      tester.element(find.byType(MessagesScreen)),
    );
  }

  void expectHomeToolbar(bool visible) {
    final matcher = visible ? findsOneWidget : findsNothing;
    expect(find.text('我的消息'), matcher);
    expect(find.byTooltip('新增粉丝'), matcher);
    expect(find.byTooltip('已加载私信一键已读'), matcher);
    expect(find.byTooltip('更多消息操作'), matcher);
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
      'narrow notification pages replace the home toolbar at $width',
      (tester) async {
        final container = await mount(tester, width: width, scale: 2);
        for (final section in InboxSection.values.skip(1)) {
          expectHomeToolbar(true);
          await tester.tap(
            find.byKey(ValueKey('message-section-${section.name}')),
          );
          await tester.pumpAndSettle();
          expectHomeToolbar(false);
          final back = find.byTooltip('返回消息首页');
          expect(back.hitTestable(), findsOneWidget);
          expect(tester.getTopLeft(back).dy, lessThan(12));
          expect(find.text(section.label), findsOneWidget);

          // The same retained category regains the desktop toolbar on resize.
          tester.view.physicalSize = const Size(1200, 900);
          await tester.pumpAndSettle();
          expectHomeToolbar(true);
          expect(back, findsNothing);
          expect(container.read(messagesControllerProvider).section, section);
          tester.view.physicalSize = Size(width, 900);
          await tester.pumpAndSettle();
          expectHomeToolbar(false);
          expect(back.hitTestable(), findsOneWidget);
          await tester.tap(back);
          await tester.pumpAndSettle();
          expectHomeToolbar(true);
          expect(
            container.read(messagesControllerProvider).section,
            InboxSection.private,
          );
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  for (final width in [390.0, 1200.0]) {
    testWidgets('system notices use the full text column at $width', (
      tester,
    ) async {
      final target = Uri.parse('https://www.bilibili.com/video/BV1234567890');
      final repo = MessageRepositoryFake()
        ..entries = [
          InboxEntry(
            id: 'system-layout',
            title: '系统通知标题',
            text: '系统通知正文',
            system: true,
            userId: const UserId('2'),
            avatarUrl: Uri.parse('https://i0.hdslb.com/bfs/face/example.jpg'),
            targetUrl: target,
          ),
        ];
      Uri? opened;
      final container = await mount(
        tester,
        width: width,
        repository: repo,
        onOpenTarget: (uri) => opened = uri,
      );
      container
          .read(messagesControllerProvider.notifier)
          .selectSection(InboxSection.system);
      await tester.pumpAndSettle();
      final list = find.byKey(const PageStorageKey('inbox-system'));
      expect(
        find.descendant(of: list, matching: find.byType(NetworkAvatar)),
        findsNothing,
      );
      final titleLeft = tester.getTopLeft(find.text('系统通知标题')).dx;
      expect(titleLeft - tester.getTopLeft(list).dx, closeTo(20, .1));
      final divider = tester.widget<Divider>(
        find.descendant(of: list, matching: find.byType(Divider)).first,
      );
      expect(divider.indent, 0);
      expect(find.text('系统通知正文'), findsOneWidget);
      await tester.tap(find.text('查看原内容'));
      expect(opened, target);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('interactive notices retain their author avatar and alignment', (
    tester,
  ) async {
    final repo = MessageRepositoryFake()
      ..entries = const [
        InboxEntry(
          id: 'reply-layout',
          title: '通知作者',
          text: '互动通知正文',
          userId: UserId('2'),
        ),
      ];
    final container = await mount(tester, width: 390, repository: repo);
    container
        .read(messagesControllerProvider.notifier)
        .selectSection(InboxSection.replies);
    await tester.pumpAndSettle();
    final list = find.byKey(const PageStorageKey('inbox-replies'));
    final avatar = find.descendant(
      of: list,
      matching: find.byType(NetworkAvatar),
    );
    expect(avatar, findsOneWidget);
    expect(
      tester.getTopLeft(find.text('通知作者')).dx - tester.getTopLeft(avatar).dx,
      closeTo(54, .1),
    );
    final divider = tester.widget<Divider>(
      find.descendant(of: list, matching: find.byType(Divider)).first,
    );
    expect(divider.indent, 54);
    expect(tester.takeException(), isNull);
  });
}
