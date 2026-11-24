import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/message_content_view.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/text_selection.dart';
import 'message_fakes.dart';

void main() {
  testWidgets('private chat paints static text during rapid scrolling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final auth = AuthFake();
    addTearDown(auth.stream.close);
    final repository = MessageRepositoryFake()
      ..more = false
      ..messages = [
        for (var index = 1; index <= 80; index++)
          PrivateMessage(
            id: '$index',
            sequence: '$index',
            senderId: const UserId('2'),
            title: '登录操作通知 $index',
            text: '消息 $index：你的账号在新设备登录成功。\n如非本人操作，请及时修改密码。',
            kind: MessageContentKind.notification,
            type: 10,
            details: const [MessageDetail(label: '设备/平台', value: 'Android')],
          ),
      ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          messageRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.android),
          scrollBehavior: const SmoothScrollBehavior(),
          home: const Scaffold(body: MessagesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试会话'));
    await tester.pumpAndSettle();
    final list = find.byType(ListView);
    final scrollable = find
        .descendant(of: list, matching: find.byType(Scrollable))
        .first;
    final position = tester.state<ScrollableState>(scrollable).position;
    final listBox = tester.renderObject<RenderBox>(list);
    void expectStaticMessage(String stage) {
      final rowFinder = find.byType(MessageContentView).first;
      final message = tester.widget<MessageContentView>(rowFinder).message;
      final row = tester.renderObject<RenderBox>(rowFinder);
      final transform = row.getTransformTo(listBox);
      expect(transform.entry(1, 1), closeTo(1, 0.000001), reason: stage);
      for (final caption in [message.title, message.text, 'Android']) {
        final text = find.descendant(
          of: rowFinder,
          matching: find.text(caption),
        );
        final paragraph = tester.renderObject<RenderParagraph>(
          find.descendant(of: text, matching: find.byType(RichText)),
        );
        expect(paragraph.text.toPlainText(), caption, reason: stage);
      }
    }

    expectStaticMessage('initial');
    await tester.fling(list, const Offset(0, -350), 4000);
    await tester.pump(const Duration(milliseconds: 16));
    expectStaticMessage('after edge fling');
    position.jumpTo(500);
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, 500);
    expectStaticMessage('middle');
    await tester.pump(const Duration(milliseconds: 100));
    expectStaticMessage('middle after 100ms');
    await tester.pumpAndSettle();
    expectStaticMessage('settled');

    await tester.fling(list, const Offset(0, 180), 2000);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(500));
    expectStaticMessage('scrolling to older messages');
    final olderOffset = position.pixels;
    await tester.fling(list, const Offset(0, -180), 2000);
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(olderOffset));
    expectStaticMessage('scrolling to newer messages');

    final detail = find.text('Android').hitTestable().first;
    expect(await selectAndCopyText(tester, detail, touch: true), 'Android');
    expect(tester.takeException(), isNull);
  });
}
