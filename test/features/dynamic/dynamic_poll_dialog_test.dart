import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_poll_controller.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/dynamic_poll_dialog.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_poll_fakes.dart';

void main() {
  late DynamicAuthFake auth;
  late DynamicPollRepositoryFake repository;
  final url = Uri.https('t.bilibili.com', '/vote/h5/index/', {'vote_id': '42'});
  setUp(() {
    auth = DynamicAuthFake();
    repository = DynamicPollRepositoryFake();
  });
  tearDown(() => auth.stream.close());

  Future<void> show(
    WidgetTester tester, {
    DynamicPost? post,
    double width = 800,
    double height = 900,
    double scale = 1,
    VoidCallback? onLogin,
    DateTime Function()? clock,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          dynamicRepositoryProvider.overrideWithValue(DynamicRepositoryFake()),
          dynamicPollRepositoryProvider.overrideWithValue(repository),
          dynamicPollClockProvider.overrideWithValue(clock ?? () => pollNow),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => post == null
                  ? TextButton(
                      onPressed: () => showDynamicPollDialog(
                        context,
                        '42',
                        onLogin: onLogin,
                      ),
                      child: const Text('打开投票'),
                    )
                  : SingleChildScrollView(
                      child: InteractiveDynamicPostCard(
                        post: post,
                        onLogin: onLogin,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final forwarded in [false, true]) {
    testWidgets(
      '${forwarded ? "forwarded" : "direct"} poll card opens native details and submits with its own dynamic ID',
      (tester) async {
        final original = DynamicPost(
          id: '88',
          contentCards: [
            DynamicContentCard(
              kind: DynamicCardKind.vote,
              title: '附加投票',
              url: url,
              actionUrl: url,
              actionLabel: '查看投票',
            ),
          ],
        );
        await show(
          tester,
          post: forwarded
              ? DynamicPost(id: '100', original: original)
              : original,
        );
        await tester.tap(find.text('查看投票'));
        await tester.pumpAndSettle();
        expect(find.text('测试投票标题'), findsOneWidget);
        expect(find.text('投票说明'), findsOneWidget);
        expect(find.text('3人参与'), findsOneWidget);
        expect(repository.votes, isEmpty);
        await tester.tap(find.byKey(const ValueKey('poll-option-9')));
        await tester.tap(find.widgetWithText(FilterChip, '匿名投票'));
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, '投票'));
        await tester.pumpAndSettle();
        expect(repository.votes.single.dynamicId, '88');
        expect(repository.votes.single.choices, [9]);
        expect(repository.votes.single.anonymous, true);
        expect(find.text('已投票'), findsOneWidget);
        expect(find.text('2票 · 66.7%'), findsOneWidget);
        expect(find.widgetWithText(FilledButton, '投票'), findsNothing);
        await tester.tap(find.byTooltip('关闭投票'));
        await tester.pumpAndSettle();
      },
    );
  }

  testWidgets(
    'body poll link opens native details without an external navigator',
    (tester) async {
      await show(
        tester,
        post: DynamicPost(
          id: '88',
          spans: [
            DynamicTextSpan(
              kind: DynamicTextKind.link,
              text: '正文投票',
              linkUrl: url,
            ),
          ],
          text: '正文投票',
        ),
      );
      await tester.tap(find.text('正文投票', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byType(DynamicPollDialog), findsOneWidget);
      expect(repository.reads, 1);
      await tester.tap(find.byTooltip('关闭投票'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('guest can inspect image options and results, then use login', (
    tester,
  ) async {
    await auth.stream.close();
    auth = DynamicAuthFake(signedIn: false);
    repository.loaded = pollFixture(images: true);
    var logins = 0;
    await show(tester, onLogin: () => logins++);
    await tester.tap(find.text('打开投票'));
    await tester.pumpAndSettle();
    expect(find.byType(AppNetworkImage), findsOneWidget);
    await tester.tap(find.widgetWithText(FilterChip, '显示比例'));
    await tester.pump();
    expect(find.text('0票 · 0.0%'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, '登录后投票'));
    await tester.tap(find.widgetWithText(FilledButton, '登录后投票'));
    await tester.pumpAndSettle();
    expect(logins, 1);
    expect(repository.votes, isEmpty);
    expect(find.byType(DynamicPollDialog), findsNothing);
  });

  testWidgets(
    'expired poll fits narrow screens with large text and exposes results',
    (tester) async {
      repository.loaded = pollFixture(ended: true);
      await show(tester, width: 320, height: 440, scale: 2);
      await tester.tap(find.text('打开投票'));
      await tester.pumpAndSettle();
      expect(find.text('已结束'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '投票'), findsNothing);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭投票'));
      await tester.pumpAndSettle();
    },
  );

  testWidgets('deadline updates an open poll and clears unsubmitted choices', (
    tester,
  ) async {
    var now = pollNow;
    await show(tester, clock: () => now);
    await tester.tap(find.text('打开投票'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('poll-option-4')));
    await tester.pump();
    expect(find.widgetWithText(FilledButton, '投票'), findsOneWidget);
    now = now.add(const Duration(days: 1));
    await tester.pump(const Duration(days: 1));
    expect(find.text('已结束'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '投票'), findsNothing);
    expect(find.text('0票 · 0.0%'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    expect(repository.votes, isEmpty);
    await tester.tap(find.byTooltip('关闭投票'));
    await tester.pumpAndSettle();
  });

  testWidgets('read error offers retry and closing cancels a pending read', (
    tester,
  ) async {
    repository.readError = const AppFailure(AppFailureKind.network, '读取失败');
    await show(tester);
    await tester.tap(find.text('打开投票'));
    await tester.pumpAndSettle();
    expect(find.text('读取失败'), findsOneWidget);
    repository.readError = null;
    repository.pendingRead = Completer();
    await tester.tap(find.text('重试'));
    await tester.pump();
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    final cancellation = repository.lastCancellation!;
    await tester.tap(find.byTooltip('关闭投票'));
    await tester.pumpAndSettle();
    expect(cancellation.isCancelled, true);
    repository.pendingRead!.complete(pollFixture());
    await tester.pumpAndSettle();
  });
}
