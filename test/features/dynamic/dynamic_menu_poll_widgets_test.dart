import 'dart:typed_data';

import 'package:bilisail/app/theme.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/image_export_service.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_composer_controller.dart';
import 'package:bilisail/features/dynamic/application/dynamic_content_state.dart';
import 'package:bilisail/features/dynamic/application/dynamic_poll_controller.dart';
import 'package:bilisail/features/image_viewer/application/image_viewer_controller.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/dynamic_compose_dialog.dart';
import 'package:bilisail/shared/ui/dynamic_post_menu.dart';
import 'package:bilisail/shared/ui/dynamic_poll_dialog.dart';
import 'package:bilisail/shared/ui/sliver_dynamic_post_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';
import '../../support/dynamic_management_fakes.dart';
import '../../support/dynamic_managed_poll_fakes.dart';

class ExportFake implements ImageExportService {
  final images = <Uint8List>[];
  @override
  bool get supported => true;
  @override
  Future<String> save(Uint8List bytes) async {
    images.add(bytes);
    return 'saved.png';
  }

  @override
  Future<void> copy(Uint8List bytes) async {
    images.add(bytes);
  }
}

void main() {
  late DynamicManagementFake repo;
  late DynamicEditComposerFake composer;
  late DynamicPollFake polls;
  late DynamicAuthFake auth;
  late ExportFake export;
  var external = 0;
  late ProviderContainer container;
  DynamicPost own() => DynamicPost(
    id: '100',
    authorId: const UserId('7'),
    authorName: '自己',
    title: '原标题',
    text: '原正文',
    editable: true,
    commentTarget: const CommentTarget('100', CommentTargetType.dynamic),
  );
  DynamicPost other() => DynamicPost(
    id: '200',
    authorId: const UserId('8'),
    authorName: '另一位UP主',
    text: '参与投票',
    commentTarget: const CommentTarget('200', CommentTargetType.dynamic),
    contentCards: [
      DynamicContentCard(
        kind: DynamicCardKind.vote,
        title: '周末去哪儿',
        url: Uri.https('t.bilibili.com', '/vote/h5/index/', {
          'vote_id': '123',
          'dynamic_id': '200',
        }),
      ),
    ],
  );
  setUp(() {
    repo = DynamicManagementFake()..loaded = own();
    composer = DynamicEditComposerFake();
    polls = DynamicPollFake();
    auth = DynamicAuthFake();
    export = ExportFake();
    external = 0;
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        dynamicRepositoryProvider.overrideWithValue(repo),
        dynamicComposerRepositoryProvider.overrideWithValue(composer),
        dynamicPollRepositoryProvider.overrideWithValue(polls),
        imageExportServiceProvider.overrideWithValue(export),
      ],
    );
    WidgetController.hitTestWarningShouldBeFatal = true;
  });
  tearDown(() async {
    container.dispose();
    await auth.stream.close();
    WidgetController.hitTestWarningShouldBeFatal = false;
  });
  Future<void> show(
    WidgetTester tester, {
    Size size = const Size(1000, 800),
    double scale = 1,
    double keyboard = 0,
    bool dark = false,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? BiliTheme.dark() : BiliTheme.light(),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboard),
            ),
            child: AppNoticeHost(child: child!),
          ),
          home: Scaffold(
            body: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: DynamicComposeToolbar(child: const Text('动态')),
                ),
                SliverDynamicPostList(
                  posts: [own(), other()],
                  onOpenLink: (_) => external++,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, {bool own = true}) async {
    await tester.tap(find.byTooltip('更多动态操作').at(own ? 0 : 1));
    await tester.pumpAndSettle();
  }

  Future<void> action(WidgetTester tester, String text) async {
    final scrollable = find
        .descendant(
          of: find.byType(DynamicPostMenu),
          matching: find.byType(Scrollable),
        )
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(text),
      140,
      scrollable: scrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  testWidgets('long press and more button expose the same owner-aware menu', (
    tester,
  ) async {
    await show(tester);
    await menu(tester);
    expect(find.text('置顶动态'), findsOneWidget);
    expect(find.text('举报动态'), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.longPress(find.text('原正文'));
    await tester.pumpAndSettle();
    expect(find.text('置顶动态'), findsOneWidget);
    expect(repo.writes, isEmpty);
  });
  testWidgets(
    'deleting requires confirmation and removes the shared card only after success',
    (tester) async {
      await show(tester);
      await menu(tester);
      await action(tester, '删除动态');
      expect(repo.writes, isEmpty);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(find.text('原正文'), findsOneWidget);
      await action(tester, '删除动态');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(repo.writes, ['remove:100']);
      expect(find.text('原正文'), findsNothing);
      expect(find.byType(DynamicPostMenu), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'pin and visibility update the list and menu without duplicating writes',
    (tester) async {
      await show(tester);
      await menu(tester);
      await action(tester, '置顶动态');
      expect(repo.writes, ['pin:100:true']);
      expect(find.text('取消置顶'), findsOneWidget);
      await action(tester, '可见范围');
      await tester.tap(find.text('仅自己可见').last);
      await tester.pumpAndSettle();
      expect(repo.writes.last, 'visibility:100:true');
      expect(
        container.read(dynamicContentProvider).posts['100']!.onlySelf,
        true,
      );
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'editing uses an isolated draft and preserves the pending new dynamic',
    (tester) async {
      await show(tester);
      container.read(dynamicComposerProvider.notifier).setText('尚未发送的新动态');
      await menu(tester);
      await action(tester, '编辑动态');
      expect(find.text('编辑动态'), findsNWidgets(2));
      await tester.enterText(
        find.byKey(const ValueKey('dynamic-compose-text')),
        '修改后的正文',
      );
      await tester.tap(find.byKey(const ValueKey('dynamic-compose-submit')));
      await tester.pumpAndSettle();
      expect(composer.edits.single.id, '100');
      expect(composer.edits.single.text, '修改后的正文');
      expect(composer.drafts, isEmpty);
      expect(container.read(dynamicComposerProvider).text, '尚未发送的新动态');
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'temporary author hiding prunes known extents and has a restoration entry',
    (tester) async {
      await show(tester);
      await menu(tester, own: false);
      await action(tester, '临时屏蔽该UP主');
      expect(find.text('另一位UP主'), findsNothing);
      await tester.tap(find.byTooltip('临时屏蔽的UP主'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('恢复显示'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.text('另一位UP主'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('reporting requires an explicit submission', (tester) async {
    await show(tester);
    await menu(tester, own: false);
    expect(find.text('置顶动态'), findsNothing);
    await action(tester, '举报动态');
    expect(repo.writes, isEmpty);
    await tester.tap(find.text('提交举报'));
    await tester.pumpAndSettle();
    expect(repo.writes, ['report:200:4:']);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'message sharing confirms the selected recipient before sending',
    (tester) async {
      await show(tester);
      await menu(tester, own: false);
      await action(tester, '分享至消息');
      expect(repo.writes, isEmpty);
      await tester.tap(find.text('测试用户'));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      expect(find.text('发送这条动态给 测试用户？'), findsOneWidget);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(repo.writes, isEmpty);
      await action(tester, '分享至消息');
      await tester.tap(find.text('测试用户'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(repo.writes, ['share:200:9007199254740993123']);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('save preview exports a bounded PNG without any account write', (
    tester,
  ) async {
    await show(tester);
    await menu(tester);
    await action(tester, '保存动态');
    await tester.runAsync(() async {
      await tester.tap(find.text('保存图片'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(export.images.single.take(4), [137, 80, 78, 71]);
    expect(repo.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  for (final (size, scale, keyboard) in [
    (const Size(320, 568), 2.0, 180.0),
    (const Size(844, 390), 1.3, 120.0),
    (const Size(1280, 900), 1.0, 0.0),
  ]) {
    testWidgets(
      'menu and poll fit $size with scale $scale and keyboard $keyboard',
      (tester) async {
        await show(
          tester,
          size: size,
          scale: scale,
          keyboard: keyboard,
          dark: size.width == 1280,
        );
        await menu(tester);
        expect(tester.takeException(), isNull);
        await action(tester, '检查动态公开可见性');
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('关闭'));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(
          find.text('周末去哪儿'),
          150,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('周末去哪儿'));
        await tester.pumpAndSettle();
        expect(find.byType(DynamicPollDialog), findsOneWidget);
        expect(external, 0);
        expect(tester.takeException(), isNull);
        final submit = find.byKey(const ValueKey('dynamic-poll-submit'));
        expect(
          tester.getRect(submit).bottom,
          lessThanOrEqualTo(size.height - keyboard),
        );
        final scrollable = find
            .descendant(
              of: find.byType(DynamicPollDialog),
              matching: find.byType(Scrollable),
            )
            .first;
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('poll-option-1')),
          100,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('poll-option-1')));
        await tester.pumpAndSettle();
        expect(submit.hitTestable(), findsOneWidget);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(polls.votes.single.choices, [1]);
        expect(polls.votes.single.dynamicId, '200');
        expect(find.text('已投票'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.all(),
    );
  }
}
