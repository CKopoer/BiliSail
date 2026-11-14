import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/message_content_view.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
import 'package:bilisail/shared/ui/smooth_scroll_behavior.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'message_fakes.dart';

void main() {
  testWidgets('private chat stays unstretched after rapid scrolling', (
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
            text: '消息 $index：快速上下滚动后应直接显示正文。',
            type: 1,
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
    void expectUnstretched(String stage) {
      final row = tester.renderObject<RenderBox>(
        find.byType(MessageContentView).first,
      );
      final transform = row.getTransformTo(listBox);
      expect(transform.entry(1, 1), closeTo(1, 0.000001), reason: stage);
    }

    expectUnstretched('initial');
    await tester.fling(list, const Offset(0, -350), 4000);
    await tester.pump(const Duration(milliseconds: 16));
    expectUnstretched('after edge fling');
    position.jumpTo(500);
    await tester.pump(const Duration(milliseconds: 16));
    expect(position.pixels, 500);
    expectUnstretched('middle');
    await tester.pump(const Duration(milliseconds: 100));
    expectUnstretched('middle after 100ms');
    await tester.pumpAndSettle();
    expectUnstretched('settled');

    await tester.fling(list, const Offset(0, 180), 2000);
    await tester.pumpAndSettle();
    expect(position.pixels, greaterThan(500));
    expectUnstretched('scrolling to older messages');
    final olderOffset = position.pixels;
    await tester.fling(list, const Offset(0, -180), 2000);
    await tester.pumpAndSettle();
    expect(position.pixels, lessThan(olderOffset));
    expectUnstretched('scrolling to newer messages');

    final text = find
        .byType(SelectableText)
        .hitTestable(at: Alignment.topLeft)
        .first;
    await tester.longPressAt(tester.getTopLeft(text) + const Offset(5, 5));
    await tester.pumpAndSettle();
    final editable = tester.widget<EditableText>(
      find.descendant(of: text, matching: find.byType(EditableText)),
    );
    expect(editable.controller.selection.isCollapsed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
