import 'dart:async';

import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/comments/application/comment_link_resolver.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/features/dynamic/application/dynamic_actions_controller.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_repository.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/dynamic_fakes.dart';

void main() {
  late DynamicAuthFake auth;
  late DynamicRepositoryFake repository;
  late DynamicCommentsFake comments;
  late List<CommentTargetType> types;
  final post = DynamicPost(
    id: '100',
    authorName: '动态作者',
    text: '动态正文',
    likeCount: 4,
    repostCount: 2,
    commentCount: 1,
    commentTarget: const CommentTarget('11', CommentTargetType.album),
  );

  setUp(() {
    auth = DynamicAuthFake();
    repository = DynamicRepositoryFake();
    comments = DynamicCommentsFake();
    types = [];
  });
  tearDown(() => auth.stream.close());

  Future<void> show(
    WidgetTester tester, {
    double width = 800,
    double height = 900,
    double keyboardInset = 0,
    double scale = 1,
    DynamicPost? value,
    void Function(VideoId)? onOpenCommentVideo,
  }) async {
    await tester.binding.setSurfaceSize(Size(width, height));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          if (onOpenCommentVideo != null)
            commentVideoNavigatorProvider.overrideWithValue(onOpenCommentVideo),
          authRepositoryProvider.overrideWithValue(auth),
          dynamicRepositoryProvider.overrideWithValue(repository),
          commentsRepositoryProvider.overrideWith((ref, type) {
            types.add(type);
            return comments;
          }),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              viewInsets: EdgeInsets.only(bottom: keyboardInset),
            ),
            child: AppNoticeHost(child: child!),
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: InteractiveDynamicPostCard(post: value ?? post),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('video link in dynamic comments closes dialog and navigates', (
    tester,
  ) async {
    const url = 'https://b23.tv/BV117BkBsEWw';
    comments.items = const [
      CommentEntry(id: '50', author: '评论作者', message: url),
    ];
    final videos = <VideoId>[];
    await show(tester, onOpenCommentVideo: videos.add);
    await tester.tap(find.byTooltip('查看评论'));
    await tester.pumpAndSettle();
    expect(find.byType(CommentsPanel), findsOneWidget);
    await tester.tapOnText(find.textRange.ofSubstring(url));
    await tester.pumpAndSettle();
    expect(videos, [const VideoId('BV117BkBsEWw')]);
    expect(find.byType(CommentsPanel), findsNothing);
    expect(find.byType(Dialog), findsNothing);
    expect(comments.writes, isEmpty);
  });

  testWidgets(
    'card likes and cancels, opens typed comments, and sends directed replies',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('点赞动态'));
      await tester.pumpAndSettle();
      expect(repository.likes, [('100', true)]);
      expect(find.byTooltip('取消点赞动态'), findsOneWidget);
      await tester.tap(find.byTooltip('取消点赞动态'));
      await tester.pumpAndSettle();
      expect(repository.likes.last, ('100', false));
      await tester.tap(find.byTooltip('查看评论'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentsPanel), findsOneWidget);
      expect(types, [CommentTargetType.album]);
      expect(comments.reads, ['11']);
      expect(find.text('测试评论'), findsOneWidget);
      expect(find.textContaining('楼中楼回复'), findsOneWidget);
      await tester.tap(find.byTooltip('点赞评论'));
      await tester.pumpAndSettle();
      expect(comments.likes, [('11', '50', true)]);
      await tester.tap(find.byTooltip('回复评论'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '回复内容');
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(comments.writes.single, ('11', '回复内容', '50', '50'));
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      expect(find.byType(CommentsPanel), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('copy is available to guests and opening share never publishes', (
    tester,
  ) async {
    auth.change(const AuthState());
    final clipboard = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await show(tester);
    await tester.tap(find.byTooltip('分享动态'));
    await tester.pumpAndSettle();
    expect(repository.reposts, isEmpty);
    await tester.tap(find.text('复制动态链接'));
    await tester.pumpAndSettle();
    expect(clipboard, ['https://t.bilibili.com/100']);
    await tester.tap(find.text('登录后转发'));
    await tester.pumpAndSettle();
    expect(repository.reposts, isEmpty);
    expect(find.text('请先登录后操作'), findsOneWidget);
  });

  testWidgets(
    'repost submits the retained draft only on Publish and keeps uncertain draft',
    (tester) async {
      await show(tester);
      await tester.tap(find.byTooltip('分享动态'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '保留转发草稿');
      repository.error = const DynamicWriteUncertain();
      await tester.tap(find.text('转发动态'));
      await tester.pumpAndSettle();
      expect(repository.reposts, [('100', '保留转发草稿')]);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        '保留转发草稿',
      );
      expect(find.text('我已核对结果，允许再次转发'), findsOneWidget);
      repository.error = null;
      await tester.tap(find.text('我已核对结果，允许再次转发'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('转发动态'));
      await tester.pumpAndSettle();
      expect(repository.reposts, hasLength(2));
      expect(find.byType(Dialog), findsNothing);
    },
  );

  testWidgets('same signed-in account switch clears the comment draft', (
    tester,
  ) async {
    await show(tester);
    await tester.tap(find.byTooltip('查看评论'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '账号七的草稿');
    comments.accountScope = 'user:8';
    comments.sessionEpoch++;
    repository.accountScope = 'user:8';
    repository.sessionEpoch++;
    auth.change(const AuthState(status: AuthStatus.signedIn, mid: '8'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller?.text,
      isEmpty,
    );
    expect(comments.writes, isEmpty);
  });

  for (final width in [320.0, 375.0]) {
    testWidgets('share and comments fit $width with doubled text', (
      tester,
    ) async {
      await show(tester, width: width, scale: 2);
      await tester.tap(find.byTooltip('分享动态'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.byTooltip('关闭'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('查看评论'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing comment target is resolved from detail before opening', (
    tester,
  ) async {
    repository.loaded = post;
    await show(
      tester,
      value: DynamicPost(id: '100', text: '无目标'),
    );
    await tester.tap(find.byTooltip('查看评论'));
    await tester.pumpAndSettle();
    expect(comments.reads, ['11']);
    expect(types, [CommentTargetType.album]);
    expect(comments.writes, isEmpty);
  });

  testWidgets('closing the card during a like ignores the late completion', (
    tester,
  ) async {
    await show(tester);
    repository.pendingLike = Completer<void>();
    await tester.tap(find.byTooltip('点赞动态'));
    await tester.pumpWidget(const SizedBox());
    repository.pendingLike!.complete();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'comment composer remains usable above a keyboard with enlarged text',
    (tester) async {
      await show(tester, width: 375, height: 700, scale: 2, keyboardInset: 300);
      await tester.tap(find.byTooltip('查看评论'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '第一行\n第二行\n第三行\n第四行');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('发布'), findsOneWidget);
      await tester.ensureVisible(find.text('发布'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      expect(comments.writes.single.$2, '第一行\n第二行\n第三行\n第四行');
    },
  );
}
