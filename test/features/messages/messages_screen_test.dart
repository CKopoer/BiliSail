import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/messages/application/messages_controller.dart';
import 'package:bilisail/features/messages/domain/message_repository.dart';
import 'package:bilisail/features/messages/presentation/messages_screen.dart';
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
  }) async {
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
          home: const Scaffold(body: MessagesScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

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
    'wide inbox shows categories and conversation; reading does not acknowledge',
    (tester) async {
      tester.view.physicalSize = const Size(1100, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await mount(tester);
      expect(find.text('系统通知'), findsOneWidget);
      await tester.tap(find.text('测试会话'));
      await tester.pumpAndSettle();
      expect(find.text('测试私信正文'), findsOneWidget);
      expect(find.text('另一会话'), findsOneWidget);
      expect(repo.marks, 0);
      await tester.tap(find.byTooltip('标为已读'));
      await tester.pumpAndSettle();
      expect(repo.marks, 1);
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
