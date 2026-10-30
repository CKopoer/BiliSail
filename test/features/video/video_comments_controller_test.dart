import 'package:bilisail/domain/user.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/comments/application/comment_link_resolver.dart';
import 'package:bilisail/features/comments/domain/comment_video_link.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/video/presentation/comment_rich_content.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/shared/ui/bili_icons.dart';
import 'package:bili_player/bili_player.dart';

import '../../support/video_card_fake_engine.dart';
import '../../support/text_selection.dart';
import '../../support/input_test_app.dart';

import 'dart:async';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/video/application/video_comments_controller.dart';
import 'package:bilisail/features/video/domain/video_comments_repository.dart';
import 'package:bilisail/features/video/presentation/video_comments_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const root = CommentEntry(
  id: '10',
  author: '甲',
  authorId: UserId('100'),
  message: '原评论',
  ipLocation: 'IP属地：广东',
  replyCount: 3,
);
const child = CommentEntry(
  id: '11',
  author: '乙',
  authorId: UserId('101'),
  message: '回复',
  ipLocation: 'IP属地：上海',
  rootId: '10',
  parentId: '10',
);
void main() {
  late _Auth auth;
  late _Repo repo;
  late ProviderContainer container;
  late VideoCommentsController controller;
  VideoCommentsState state() =>
      container.read(videoCommentsControllerProvider('42'));
  setUp(() async {
    auth = _Auth();
    repo = _Repo();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        videoCommentsRepositoryProvider.overrideWithValue(repo),
      ],
    );
    container.listen(videoCommentsControllerProvider('42'), (_, _) {});
    controller = container.read(videoCommentsControllerProvider('42').notifier);
    await Future<void>.delayed(Duration.zero);
  });
  tearDown(() {
    container.dispose();
    auth.changesController.close();
  });
  testWidgets(
    'main, preview and detailed replies open URLs and seek the local session',
    (tester) async {
      const url = 'https://daily.juya.uk/issues/2026-10-06/';
      const videoUrl = 'https://b23.tv/BV117BkBsEWw';
      const timestampReply = CommentEntry(
        id: '11',
        author: '乙',
        message: '$url $videoUrl 00：12',
        rootId: '10',
        parentId: '10',
      );
      repo.items = [
        const CommentEntry(
          id: '10',
          author: '甲',
          message: '$url $videoUrl 00：09 00:34',
          replyCount: 3,
          replies: [timestampReply],
        ),
      ];
      repo.replyItems = [timestampReply];
      final engine = CardFakeEngine()
        ..snapshot = const PlaybackSnapshot(
          phase: PlaybackPhase.paused,
          generation: 1,
          duration: Duration(seconds: 20),
        );
      final session =
          PlaybackSession(
              engine: engine,
              repository: _UnusedPlaybackRepository(),
              progress: _UnusedProgressStore(),
              accountScope: () => 'user:7',
            )
            ..detail = _detail
            ..media = cardPreviewMedia();
      addTearDown(session.close);
      final opened = <Uri>[];
      final videos = <VideoId>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            videoCommentsRepositoryProvider.overrideWithValue(repo),
            playbackSessionProvider.overrideWithValue(session),
            commentVideoNavigatorProvider.overrideWithValue(videos.add),
            webLinkOpenerProvider.overrideWithValue((uri) async {
              opened.add(uri);
              return true;
            }),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(body: VideoCommentsPanel(detail: _detail)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final (index, time, seconds) in [
        (0, '00：09', 9),
        (1, '00：12', 12),
      ]) {
        final richContent = find.byType(CommentRichContent).at(index);
        await tester.tapOnText(
          find.textRange.ofSubstring(url, descendentOf: richContent),
        );
        await tester.tapOnText(
          find.textRange.ofSubstring(videoUrl, descendentOf: richContent),
        );
        await tester.tapOnText(
          find.textRange.ofSubstring(time, descendentOf: richContent),
        );
        await tester.pumpAndSettle();
        expect(engine.currentSnapshot.position, Duration(seconds: seconds));
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(find.text('评论详情'), findsNothing);
      }
      await tester.tap(find.text('共 3 条回复 ›'));
      await tester.pumpAndSettle();
      await tester.tapOnText(
        find.textRange.ofSubstring(
          url,
          descendentOf: find.byType(CommentRichContent).at(1),
        ),
      );
      await tester.tapOnText(find.textRange.ofSubstring('00：12'));
      await tester.tapOnText(
        find.textRange.ofSubstring(
          videoUrl,
          descendentOf: find.byType(CommentRichContent).at(1),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring('00:34'));
      await tester.pumpAndSettle();
      expect(engine.currentSnapshot.position, const Duration(seconds: 20));
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(engine.seeks, 4);
      expect(engine.opens, 0);
      expect(opened, List.filled(3, Uri.parse(url)));
      expect(videos, List.filled(3, const VideoId('BV117BkBsEWw')));
      expect(repo.writes, 0);
    },
  );

  testWidgets('a newer link click cancels stale short-link navigation', (
    tester,
  ) async {
    const short = 'https://b23.tv/randomToken';
    const direct = 'https://b23.tv/BV117BkBsEWw';
    repo.items = [
      const CommentEntry(id: '10', author: '甲', message: '$short $direct'),
    ];
    final links = _LinkRepository();
    final videos = <VideoId>[];
    final external = <Uri>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          videoCommentsRepositoryProvider.overrideWithValue(repo),
          commentVideoLinkRepositoryProvider.overrideWithValue(links),
          commentVideoNavigatorProvider.overrideWithValue(videos.add),
          webLinkOpenerProvider.overrideWithValue((uri) async {
            external.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          builder: AppNoticeHost.builder,
          home: const Scaffold(body: VideoCommentsPanel(detail: _detail)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tapOnText(find.textRange.ofSubstring(short));
    await tester.pump();
    expect(links.cancellation?.isCancelled, isFalse);
    await tester.tapOnText(find.textRange.ofSubstring(direct));
    await tester.pump();
    expect(links.cancellation?.isCancelled, isTrue);
    links.pending.complete(const VideoId('BV1234567890'));
    await tester.pump();
    expect(videos, [const VideoId('BV117BkBsEWw')]);
    expect(external, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final transition in ['hidden', 'disposed', 'new account epoch']) {
    testWidgets('pending link cannot navigate after $transition', (
      tester,
    ) async {
      const short = 'https://b23.tv/randomToken';
      repo.items = [const CommentEntry(id: '10', author: '甲', message: short)];
      final links = _LinkRepository();
      final videos = <VideoId>[];
      var externalCalls = 0;
      var active = true;
      late StateSetter update;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            videoCommentsRepositoryProvider.overrideWithValue(repo),
            commentVideoLinkRepositoryProvider.overrideWithValue(links),
            commentVideoNavigatorProvider.overrideWithValue(videos.add),
            webLinkOpenerProvider.overrideWithValue((_) async {
              externalCalls++;
              return true;
            }),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: StatefulBuilder(
              builder: (_, setState) {
                update = setState;
                return WorkspaceActivity(
                  active: active,
                  child: const Scaffold(
                    body: VideoCommentsPanel(detail: _detail),
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring(short));
      await tester.pump();
      if (transition == 'hidden') {
        update(() => active = false);
        await tester.pump();
      } else if (transition == 'disposed') {
        await tester.pumpWidget(const SizedBox.shrink());
      } else {
        repo.epoch++;
      }
      if (transition != 'new account epoch') {
        expect(links.cancellation?.isCancelled, isTrue);
      }
      links.pending.complete(const VideoId('BV117BkBsEWw'));
      await tester.pump();
      expect(videos, isEmpty);
      expect(externalCalls, 0);
      expect(tester.takeException(), isNull);
    });
  }

  for (final failed in [false, true]) {
    testWidgets(
      'short-link ${failed ? 'failure shows notice' : 'non-video opens browser'}',
      (tester) async {
        const short = 'https://b23.tv/randomToken';
        repo.items = [
          const CommentEntry(id: '10', author: '甲', message: short),
        ];
        final links = _LinkRepository();
        final external = <Uri>[];
        final videos = <VideoId>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authRepositoryProvider.overrideWithValue(auth),
              videoCommentsRepositoryProvider.overrideWithValue(repo),
              commentVideoLinkRepositoryProvider.overrideWithValue(links),
              commentVideoNavigatorProvider.overrideWithValue(videos.add),
              webLinkOpenerProvider.overrideWithValue((uri) async {
                external.add(uri);
                return true;
              }),
            ],
            child: MaterialApp(
              builder: AppNoticeHost.builder,
              home: const Scaffold(body: VideoCommentsPanel(detail: _detail)),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tapOnText(find.textRange.ofSubstring(short));
        if (failed) {
          links.pending.completeError(
            const AppFailure(AppFailureKind.network, '视频链接解析失败，请检查网络后重试'),
          );
        } else {
          links.pending.complete(null);
        }
        await tester.pump();
        expect(videos, isEmpty);
        expect(external, failed ? isEmpty : [Uri.parse(short)]);
        await tester.pump();
        if (failed) expect(find.text('视频链接解析失败，请检查网络后重试'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'unavailable player and launcher refusal show actionable notices',
    (tester) async {
      repo.items = [
        const CommentEntry(
          id: '10',
          author: '甲',
          message: '00:09 https://example.com/',
        ),
      ];
      final engine = CardFakeEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _UnusedPlaybackRepository(),
        progress: _UnusedProgressStore(),
        accountScope: () => 'user:7',
      );
      addTearDown(session.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            videoCommentsRepositoryProvider.overrideWithValue(repo),
            playbackSessionProvider.overrideWithValue(session),
            webLinkOpenerProvider.overrideWithValue((_) async => false),
          ],
          child: MaterialApp(
            builder: AppNoticeHost.builder,
            home: const Scaffold(body: VideoCommentsPanel(detail: _detail)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring('00:09'));
      await tester.pump();
      expect(find.text('播放器尚未就绪'), findsOneWidget);
      expect(engine.seeks, 0);
      await tester.tapOnText(
        find.textRange.ofSubstring('https://example.com/'),
      );
      await tester.pump();
      expect(find.text('无法打开浏览器，请稍后重试'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
  test('comment copies preserve author IDs', () {
    expect(root.withLike(true).authorId, const UserId('100'));
    expect(root.withReplies([child]).authorId, const UserId('100'));
    expect(
      root.withReplies([child]).replies.single.authorId,
      const UserId('101'),
    );
  });
  testWidgets('root and nested identity open matching user', (tester) async {
    final opened = <UserId>[];
    repo.items = [
      root.withReplies([child]),
    ];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          videoCommentsRepositoryProvider.overrideWithValue(repo),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: VideoCommentsPanel(detail: _detail, onOpenUser: opened.add),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('甲').first);
    expect(opened, [const UserId('100')]);
    await tester.tap(find.text('乙：').first);
    expect(opened.last, const UserId('101'));
    expect(find.text('评论详情').evaluate(), isEmpty);
    await tester.tap(find.textContaining('共 3 条回复').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('乙').first);
    expect(opened.last, const UserId('101'));
  });
  testWidgets(
    'reply preview preserves text cursor, copying and profile links',
    (tester) async {
      final opened = <UserId>[];
      const mentionedReply = CommentEntry(
        id: '11',
        author: '乙',
        authorId: UserId('101'),
        message: '回复 @小迷糊陈 :看了',
        mentionedUsers: {'小迷糊陈': UserId('102')},
        rootId: '10',
        parentId: '10',
      );
      repo.items = [
        const CommentEntry(
          id: '10',
          author: '甲',
          message: '@主评论用户',
          mentionedUsers: {'主评论用户': UserId('103')},
          replyCount: 3,
          replies: [mentionedReply],
        ),
      ];
      repo.replyItems = [mentionedReply];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            videoCommentsRepositoryProvider.overrideWithValue(repo),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: VideoCommentsPanel(detail: _detail, onOpenUser: opened.add),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 1,
      );
      await mouse.addPointer(location: Offset.zero);
      Future<void> expectCursor(String substring, MouseCursor cursor) async {
        final match = find.textRange
            .ofSubstring(
              substring,
              descendentOf: find.byType(CommentRichContent).at(1),
            )
            .evaluate()
            .single;
        final box = match.renderObject
            .getBoxesForSelection(
              TextSelection(
                baseOffset: match.textRange.start,
                extentOffset: match.textRange.end,
              ),
            )
            .first;
        await mouse.moveTo(
          match.renderObject.localToGlobal(box.toRect().center),
        );
        await tester.pump();
        expect(
          RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
          cursor,
        );
      }

      await expectCursor('回复 ', SystemMouseCursors.text);
      await expectCursor('@小迷糊陈', SystemMouseCursors.click);
      await mouse.moveTo(tester.getCenter(find.text('共 3 条回复 ›')));
      await tester.pump();
      expect(
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1),
        SystemMouseCursors.basic,
      );
      await mouse.removePointer();
      expect(
        await selectAndCopyText(tester, find.text(mentionedReply.message)),
        mentionedReply.message,
      );
      expect(find.text('评论详情'), findsNothing);
      await tester.tapOnText(find.textRange.ofSubstring('@主评论用户'));
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      await tester.pumpAndSettle();
      expect(opened, [const UserId('103'), const UserId('102')]);
      expect(find.text('评论详情'), findsNothing);
      await tester.tap(find.text('共 3 条回复 ›'));
      await tester.pumpAndSettle();
      await tester.tapOnText(find.textRange.ofSubstring('@小迷糊陈'));
      expect(opened.last, const UserId('102'));
      expect(repo.writes, 0);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
  test('emote loading discards response from previous session epoch', () async {
    repo.emotePending = Completer();
    final loading = controller.loadEmotes();
    expect(state().emotesLoading, true);
    repo.epoch++;
    repo.emotePending!.complete(const [CommentEmotePackage('old', [])]);
    await loading;
    expect(state().emotePackages, isEmpty);
  });
  test('logout cancels in-flight emotes and rejects late package', () async {
    repo.emotePending = Completer();
    final loading = controller.loadEmotes();
    final cancellation = repo.emoteCancellation!;
    repo.epoch++;
    auth.emit(const AuthState(status: AuthStatus.guest));
    await Future<void>.delayed(Duration.zero);
    expect(state().signedIn, false);
    expect(cancellation.isCancelled, true);
    repo.emotePending!.complete(const [CommentEmotePackage('private', [])]);
    await loading;
    expect(state().emotePackages, isEmpty);
    expect(state().emotesLoading, false);
  });
  test('emote packages load only once and disposal cancels request', () async {
    await controller.loadEmotes();
    expect(state().emotePackages.single.items.single.text, '[笑]');
    final cancellation = repo.emoteCancellation;
    await controller.loadEmotes();
    expect(repo.emoteCancellation, same(cancellation));
    container.dispose();
    expect(cancellation!.isCancelled, true);
    container = ProviderContainer();
  });
  test(
    'pagination uses selected sort, deduplicates and stops empty pages',
    () async {
      expect(state().items.length, 1);
      await controller.load();
      expect(repo.pages, [1, 2]);
      expect(state().items.length, 1);
      await controller.load(sort: CommentSort.latest);
      expect(repo.sort, CommentSort.latest);
      expect(state().page, 1);
      repo.empty = true;
      await controller.load();
      expect(state().hasMore, false);
    },
  );
  test(
    'reply to nested comment sends original root and selected parent',
    () async {
      await controller.openReplies(root);
      expect(state().replyItems.single.id, '11');
      controller.target(child);
      expect(await controller.send(' hello '), true);
      expect(repo.sentRoot, '10');
      expect(repo.sentParent, '11');
      expect(repo.sentText, 'hello');
      expect(state().replyItems.length, 2);
      controller.closeReplies();
      expect(state().openRoot, isNull);
      expect(state().items.single.replyCount, 4);
      expect(state().page, 1);
    },
  );
  test('uncertain send blocks replay until explicit acknowledgement', () async {
    repo.failure = const CommentWriteUncertain();
    expect(await controller.send('x'), false);
    expect(await controller.send('x'), false);
    expect(repo.writes, 1);
    await controller.load(refresh: true);
    expect(state().uncertain, contains('send'));
    controller.acknowledgeSend();
    repo.failure = null;
    expect(await controller.send('x'), true);
  });

  test(
    'a reply completing after detail closes does not retain hidden detail data',
    () async {
      await controller.openReplies(root);
      repo.writePending = Completer<void>();
      final sending = controller.send('关闭详情期间发送');
      controller.closeReplies();
      repo.writePending!.complete();
      expect(await sending, isTrue);
      expect(state().openRoot, isNull);
      expect(state().replyItems, isEmpty);
      expect(state().items.single.replyCount, 4);
      expect(state().items.single.replies.single.message, '关闭详情期间发送');
      expect(repo.writes, 1);
    },
  );
  test(
    'pagination forwards opaque cursors and resets them on sort and refresh',
    () async {
      repo.nextCursor = 'opaque-first';
      await controller.load(refresh: true);
      expect(state().nextCursor, 'opaque-first');
      expect(repo.cursors.last, isNull);
      repo.nextCursor = 'opaque-second';
      await controller.load();
      expect(repo.cursors.last, 'opaque-first');
      expect(state().nextCursor, 'opaque-second');
      await controller.load(sort: CommentSort.latest);
      expect(repo.cursors.last, isNull);
      expect(state().page, 1);
      await controller.load(refresh: true);
      expect(repo.cursors.last, isNull);
      repo.nextCursor = null;
      repo.empty = true;
      await controller.load();
      expect(state().nextCursor, isNull);
      expect(state().hasMore, false);
    },
  );
  test('repeated cursor pages stop when they add no new comments', () async {
    repo.nextCursor = 'same';
    await controller.load(refresh: true);
    expect(state().hasMore, true);
    repo.items = [child];
    await controller.load();
    expect(state().hasMore, true);
    expect(state().items, hasLength(2));
    await controller.load();
    expect(state().hasMore, false);
    final reads = repo.pages.length;
    await controller.load();
    expect(repo.pages, hasLength(reads));
  });
  test(
    'restricted submissions retain the entry and explain visibility',
    () async {
      repo.sentVisibility = CommentVisibility.restricted;
      repo.submissionMessage = '发送成功';
      expect(await controller.send('fixture'), true);
      expect(state().items.first.visibility, CommentVisibility.restricted);
      expect(state().message, '评论已提交，暂未公开，请稍后查看');
      expect(state().uncertain, isEmpty);
      await controller.openReplies(root);
      expect(await controller.send('reply fixture'), true);
      expect(state().message, '回复已提交，暂未公开，请稍后查看');
      expect(repo.writes, 2);
    },
  );
  test('normal submissions keep server feedback and absent state stays unconfirmed', () async {
    repo.sentVisibility = CommentVisibility.normal;
    repo.submissionMessage = '评论已收到';
    expect(await controller.send('fixture'), true);
    expect(state().message, '评论已收到');
    repo.submissionMessage = null;
    expect(await controller.send('fixture'), true);
    expect(state().message, '评论已发送');
    repo.sentVisibility = CommentVisibility.unknown;
    expect(await controller.send('fixture'), true);
    expect(state().message, '评论已提交，请刷新确认显示状态');
  });
  testWidgets('restricted comment stays labelled after a server refresh', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: VideoCommentsPanel(detail: _detail)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    repo.sentVisibility = CommentVisibility.restricted;
    await tester.enterText(find.byType(TextField), '尚未公开的评论');
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(find.text('评论已提交，暂未公开，请稍后查看'), findsOneWidget);
    expect(find.text('暂未公开'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      isEmpty,
    );
    repo.items = state().items;
    await tester.tap(find.byTooltip('刷新评论'));
    await tester.pumpAndSettle();
    expect(find.text('尚未公开的评论'), findsOneWidget);
    expect(find.text('暂未公开'), findsOneWidget);
    expect(repo.writes, 1);
  });
  test(
    'busy prevents duplicate likes; confirmed success updates count',
    () async {
      repo.writePending = Completer<void>();
      final pending = controller.toggleLike(root);
      expect(await controller.toggleLike(root), false);
      expect(repo.writes, 1);
      repo.writePending!.complete();
      expect(await pending, true);
      expect(state().items.single.liked, true);
      expect(state().items.single.likeCount, 1);
    },
  );
  test('same account epoch transition rejects late read', () async {
    repo.pending = Completer<CommentPage>();
    final pending = controller.load(refresh: true);
    repo.epoch++;
    auth.emit(
      const AuthState(status: AuthStatus.signedIn, mid: '7', userName: '新会话'),
    );
    repo.pending!.complete(const CommentPage(items: [child], hasMore: false));
    await pending;
    expect(state().items.where((c) => c.id == child.id), isEmpty);
  });
  test('close reply view rejects late nested read', () async {
    repo.replyPending = Completer<CommentPage>();
    final pending = controller.openReplies(root);
    controller.closeReplies();
    repo.replyPending!.complete(
      const CommentPage(items: [child], hasMore: false),
    );
    await pending;
    expect(state().openRoot, isNull);
    expect(state().replyItems, isEmpty);
  });

  test(
    'closing loaded replies releases the detail buffer and pagination',
    () async {
      await controller.openReplies(root);
      expect(state().replyItems, isNotEmpty);
      controller.target(child);
      controller.closeReplies();
      expect(repo.replyCancellation!.isCancelled, isTrue);
      expect(state().replyItems, isEmpty);
      expect(state().replyPage, 0);
      expect(state().replyHasMore, isFalse);
      expect(state().replyTarget, isNull);
      expect(state().items.single, same(root));
    },
  );

  for (final sort in [null, CommentSort.latest]) {
    test(
      'reset ($sort) cancels pending replies and allows subsequent writes',
      () async {
        repo.replyPending = Completer<CommentPage>();
        final opening = controller.openReplies(root);
        final cancellation = repo.replyCancellation!;
        await controller.load(refresh: sort == null, sort: sort);
        expect(cancellation.isCancelled, isTrue);
        expect(state().replyLoading, isFalse);
        expect(state().openRoot, isNull);
        expect(state().replyItems, isEmpty);
        expect(state().replyPage, 0);
        expect(state().replyHasMore, isFalse);
        repo.replyPending!.complete(
          const CommentPage(items: [child], hasMore: true),
        );
        await opening;
        expect(state().replyItems, isEmpty);
        expect(await controller.toggleLike(state().items.single), isTrue);
      },
    );
  }

  test(
    'likes preserve unrelated comments and only copy the affected reply branch',
    () async {
      const sibling = CommentEntry(id: '13', author: '丙', message: '另一条回复');
      const parent = CommentEntry(
        id: '20',
        author: '丁',
        message: '另一条评论',
        replies: [child, sibling],
      );
      repo.items = [root, parent];
      repo.replyItems = [child, sibling];
      await controller.load(refresh: true);
      final before = state();
      await controller.openReplies(parent);
      final detailBefore = state();
      expect(await controller.toggleLike(child), isTrue);
      expect(state().items.first, same(before.items.first));
      expect(state().items.last.replies.first.liked, isTrue);
      expect(state().items.last.replies.last, same(sibling));
      expect(state().openRoot!.replies.first.liked, isTrue);
      expect(state().replyItems.first.liked, isTrue);
      expect(state().replyItems.last, same(detailBefore.replyItems.last));
      final replies = state().replyItems;
      final openRoot = state().openRoot;
      final otherComment = state().items.last;
      expect(await controller.toggleLike(root), isTrue);
      expect(state().replyItems, same(replies));
      expect(state().openRoot, same(openRoot));
      expect(state().items.last, same(otherComment));
    },
  );
  test('in-flight read cannot race a mutation', () async {
    repo.pending = Completer<CommentPage>();
    final pending = controller.load(refresh: true);
    expect(await controller.toggleLike(root), false);
    expect(repo.writes, 0);
    repo.pending!.complete(const CommentPage(items: [root], hasMore: false));
    await pending;
    expect(await controller.toggleLike(root), true);
    expect(state().items.single.liked, true);
  });
  testWidgets(
    'composer reveals actions smoothly and preserves collapsed drafts',
    (tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: BiliTheme.light(),
            home: const Scaffold(
              body: SizedBox(
                width: 340,
                child: VideoCommentsPanel(detail: _detail),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final input = find.byType(TextField);
      final collapsedRect = tester.getRect(input);
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(collapsedRect.height, lessThanOrEqualTo(36));
      expect(
        tester.getSize(find.byType(SingleChildScrollView)).height,
        lessThanOrEqualTo(52),
      );
      expect(
        tester
            .renderObject<RenderParagraph>(find.text('发一条友善的评论'))
            .text
            .style
            ?.fontSize,
        13,
      );
      expect(tester.widget<TextField>(input).maxLines, 1);
      expect(find.byTooltip('选择表情'), findsNothing);
      expect(find.text('发布'), findsNothing);

      await tester.tap(input);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final transitioningTop = tester.getTopLeft(input).dy;
      await tester.pumpAndSettle();
      final expandedTop = tester.getTopLeft(input).dy;
      expect(transitioningTop, lessThan(collapsedRect.top));
      expect(transitioningTop, greaterThan(expandedTop));
      expect(find.byTooltip('选择表情').hitTestable(), findsOneWidget);
      expect(find.text('发布').hitTestable(), findsOneWidget);
      expect(tester.widget<TextField>(input).maxLines, 4);
      expect(tester.widget<ListView>(find.byType(ListView)), same(list));

      await tester.enterText(input, '第一行\n第二行\n第三行');
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, greaterThan(collapsedRect.height));
      await tester.tap(find.text('4 条'));
      await tester.pumpAndSettle();
      expect(find.byTooltip('选择表情'), findsNothing);
      expect(find.text('发布'), findsNothing);
      expect(tester.getRect(input), collapsedRect);
      expect(tester.widget<TextField>(input).controller!.text, '第一行\n第二行\n第三行');

      await tester.tap(input);
      await tester.pumpAndSettle();
      expect(tester.getSize(input).height, greaterThan(collapsedRect.height));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).focusNode!.hasFocus, isFalse);
      expect(find.byTooltip('选择表情').hitTestable(), findsOneWidget);
      expect(find.text('发布').hitTestable(), findsOneWidget);
      expect(repo.writes, 0);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final replying in [false, true]) {
    testWidgets(
      'desktop ${replying ? 'reply' : 'comment'} Enter keeps the composer open',
      (tester) async {
        if (replying) await controller.openReplies(root);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const InputTestApp(
              home: Scaffold(
                body: SizedBox(
                  width: 340,
                  child: VideoCommentsPanel(detail: _detail),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final input = find.byType(TextField);
        final collapsedHeight = tester.getSize(input).height;

        for (var attempt = 0; attempt < 2; attempt++) {
          tester.testTextInput.log.clear();
          await tester.tap(input);
          await tester.pumpAndSettle();
          // The native client must support newline from its first attachment,
          // before the focus animation rebuilds the field with more lines.
          final attachment = tester.testTextInput.log.firstWhere(
            (call) => call.method == 'TextInput.setClient',
          );
          final configuration =
              (attachment.arguments as List<Object?>)[1]
                  as Map<Object?, Object?>;
          expect(configuration['inputAction'], 'TextInputAction.newline');
          expect(
            configuration['inputType'],
            containsPair('name', 'TextInputType.multiline'),
          );

          await tester.enterText(input, '第一行');
          // Native text input inserts the newline and then reports the action.
          tester.testTextInput.updateEditingValue(
            const TextEditingValue(
              text: '第一行\n',
              selection: TextSelection.collapsed(offset: 4),
            ),
          );
          await tester.testTextInput.receiveAction(TextInputAction.newline);
          await tester.pumpAndSettle();
          final field = tester.widget<TextField>(input);
          expect(field.focusNode!.hasFocus, isTrue);
          expect(field.controller!.text, '第一行\n');
          expect(tester.getSize(input).height, greaterThan(collapsedHeight));
          expect(find.text('发布').hitTestable(), findsOneWidget);
          expect(repo.writes, 0);

          await tester.tap(find.text(replying ? '评论详情' : '4 条'));
          await tester.pumpAndSettle();
          expect(find.text('发布'), findsNothing);
          expect(field.controller!.text, '第一行\n');
        }
        expect(tester.takeException(), isNull);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }),
    );
  }

  testWidgets('successful send preserves a newer edited draft', (tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一条评论');
    await tester.pumpAndSettle();
    repo.writePending = Completer<void>();
    await tester.tap(find.text('发布'));
    await tester.pump();
    await tester.enterText(find.byType(TextField), '下一条草稿');
    repo.writePending!.complete();
    await tester.pumpAndSettle();
    expect(find.text('下一条草稿'), findsOneWidget);
    expect(repo.sentText, '第一条评论');
  });
  testWidgets('emote picker replaces draft selection without sending', (
    tester,
  ) async {
    repo.emotePackages = const [
      CommentEmotePackage('小黄脸', [CommentEmote('[哭]', null)]),
      CommentEmotePackage('颜文字', [CommentEmote('[笑]', null)]),
    ];
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'abcd');
    await tester.pumpAndSettle();
    final text = tester.widget<TextField>(find.byType(TextField)).controller!;
    text.selection = const TextSelection(baseOffset: 1, extentOffset: 3);
    final inputRect = tester.getRect(find.byType(TextField));
    await tester.tap(find.byTooltip('选择表情'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .getCenter(
            find
                .descendant(
                  of: find.byType(AlertDialog),
                  matching: find.byType(Material),
                )
                .first,
          )
          .dx,
      tester.view.physicalSize.width / tester.view.devicePixelRatio / 2,
    );
    expect(tester.getRect(find.byType(TextField)), inputRect);
    expect(find.byType(DropdownButton<int>), findsNothing);
    expect(find.text('[哭]'), findsOneWidget);
    expect(find.text('[笑]'), findsNothing);
    await tester.tap(find.text('颜文字'));
    await tester.pumpAndSettle();
    expect(find.text('[哭]'), findsNothing);
    expect(find.text('[笑]'), findsOneWidget);
    await tester.tap(find.text('[笑]'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(text.text, 'a[笑]d');
    expect(text.selection.baseOffset, 4);
    expect(repo.writes, 0);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('选择表情'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(text.text, 'a[笑]d');
    expect(
      tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
      isTrue,
    );
    expect(tester.getRect(find.byType(TextField)), inputRect);
    expect(find.text('发布').hitTestable(), findsOneWidget);
  });
  testWidgets('nonzero count with empty result explains session limitation', (
    tester,
  ) async {
    repo.empty = true;
    await controller.load(sort: CommentSort.latest);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('当前会话未返回可展示的评论'), findsOneWidget);
    expect(find.text('还没有评论，来聊聊吧'), findsNothing);
  });
  testWidgets('nested sidebar reply retains draft on uncertain write', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('IP属地：广东'), findsOneWidget);
    expect(find.text('共 3 条回复 ›'), findsOneWidget);
    await tester.tap(find.text('共 3 条回复 ›'));
    await tester.pumpAndSettle();
    expect(find.text('评论详情'), findsOneWidget);
    expect(find.text('回复'), findsOneWidget);
    expect(find.text('IP属地：广东'), findsOneWidget);
    expect(find.text('IP属地：上海'), findsOneWidget);
    await tester.tap(find.widgetWithIcon(IconButton, BiliIcons.reply).last);
    await tester.pumpAndSettle();
    expect(find.text('回复 @乙'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '保留这条回复');
    repo.failure = const CommentWriteUncertain();
    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();
    expect(find.text('保留这条回复'), findsOneWidget);
    expect(find.text('我已核对结果，允许再次发送'), findsOneWidget);
    await tester.tap(find.byTooltip('返回评论'));
    await tester.pumpAndSettle();
    expect(find.text('最热'), findsOneWidget);
    expect(find.text('评论详情'), findsNothing);
  });
  testWidgets('320 pixel panel supports double text scale without overflow', (
    tester,
  ) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: SizedBox(
                width: 320,
                child: VideoCommentsPanel(detail: _detail),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '第一行\n第二行\n第三行\n第四行');
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '第一行\n第二行\n第三行\n第四行',
    );
    expect(find.text('发布').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('共 3 条回复 ›'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
  testWidgets('sidebar details return restores top comment scroll position', (
    tester,
  ) async {
    repo.items = List.generate(
      30,
      (i) => CommentEntry(
        id: '$i',
        author: '用户 $i',
        message: '评论内容 $i',
        replyCount: 3,
      ),
    );
    await controller.load(refresh: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, -450));
    await tester.pumpAndSettle();
    final before = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(before, greaterThan(0));
    await controller.openReplies(state().items[3]);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回评论'));
    await tester.pumpAndSettle();
    final after = tester
        .state<ScrollableState>(find.byType(Scrollable).first)
        .position
        .pixels;
    expect(after, closeTo(before, 1));
  });

  testWidgets('pagination and busy controls reuse unchanged rich comments', (
    tester,
  ) async {
    repo.items = List.generate(
      480,
      (index) => CommentEntry(
        id: '$index',
        author: '用户 $index',
        message: '评论内容 $index 00:09',
        replyCount: 3,
        replies: [
          CommentEntry(
            id: 'preview-$index',
            author: '预览',
            message: '回复 $index',
          ),
        ],
      ),
    );
    await controller.load(refresh: true);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 340,
              child: VideoCommentsPanel(detail: _detail),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final builds = <String, int>{};
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      final widget = element.widget;
      if (widget is CommentRichContent) {
        builds.update(
          widget.comment.id,
          (value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    repo.pending = Completer<CommentPage>();
    final loading = controller.load();
    await tester.pump();
    expect(builds, isEmpty, reason: 'loading should rebuild controls only');
    repo.pending!.complete(
      CommentPage(
        items: List.generate(
          20,
          (index) => CommentEntry(
            id: '${480 + index}',
            author: '新用户',
            message: '新评论 $index',
          ),
        ),
        hasMore: false,
      ),
    );
    await loading;
    await tester.pumpAndSettle();
    expect(state().items, hasLength(500));
    expect(
      builds,
      isEmpty,
      reason: 'appending offscreen data should reuse visible content',
    );

    repo.writePending = Completer<void>();
    final liking = controller.toggleLike(state().items.first);
    await tester.pump();
    expect(builds, isEmpty, reason: 'busy should rebuild controls only');
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, BiliIcons.reply).first,
          )
          .onPressed,
      isNull,
    );
    repo.writePending!.complete();
    await liking;
    await tester.pumpAndSettle();
    expect(builds.keys, unorderedEquals(['0', 'preview-0']));
    expect(state().items.first.liked, isTrue);
    expect(
      tester
          .widget<IconButton>(
            find.widgetWithIcon(IconButton, BiliIcons.reply).first,
          )
          .onPressed,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'retained comment content updates callbacks, theme and server edits',
    (tester) async {
      final first = <UserId>[], second = <UserId>[];
      var onOpen = first.add;
      var theme = ThemeData.light();
      late StateSetter update;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return MaterialApp(
                theme: theme,
                home: Scaffold(
                  body: SizedBox(
                    width: 340,
                    child: VideoCommentsPanel(
                      detail: _detail,
                      onOpenUser: onOpen,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final author = find.descendant(
        of: find.byType(CommentAuthorHeader),
        matching: find.text('甲'),
      );
      await tester.tap(author);
      update(() {
        onOpen = second.add;
        theme = ThemeData.dark();
      });
      await tester.pumpAndSettle();
      await tester.tap(author);
      expect(first, [const UserId('100')]);
      expect(second, [const UserId('100')]);
      final rich = tester.widget<CommentRichContent>(
        find.byType(CommentRichContent),
      );
      final body = tester.widget<Text>(
        find.descendant(
          of: find.byType(CommentRichContent),
          matching: find.byType(Text),
        ),
      );
      expect(body.style!.color, const Color(0xFFE7E9EB));
      repo.items = [
        const CommentEntry(id: '10', author: '修改后的作者', message: '服务端编辑后的正文'),
      ];
      await controller.load();
      await tester.pumpAndSettle();
      expect(find.text('服务端编辑后的正文'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(CommentAuthorHeader),
          matching: find.text('修改后的作者'),
        ),
        findsOneWidget,
      );
      expect(
        tester.widget<CommentRichContent>(find.byType(CommentRichContent)),
        isNot(same(rich)),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'reply views disable per-thread scroll persistence and release rows',
    (tester) async {
      repo.replyItems = List.generate(
        30,
        (index) => CommentEntry(
          id: 'reply-$index',
          author: '回复用户',
          message: '回复内容 $index',
          rootId: root.id,
        ),
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: VideoCommentsPanel(detail: _detail),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await controller.openReplies(root);
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.controller!.keepScrollOffset, isFalse);
      final rich = find.byType(CommentRichContent).evaluate().first;
      await tester.drag(find.byType(ListView), const Offset(0, -700));
      await tester.pumpAndSettle();
      controller.closeReplies();
      await tester.pumpAndSettle();
      expect(state().replyItems, isEmpty);
      expect(rich.mounted, isFalse);
      await controller.openReplies(root);
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView)).controller!.offset,
        0,
      );
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    '500 comments use a lazy delegate and reply targeting does not rebuild the list',
    (tester) async {
      repo.items = List.generate(
        500,
        (index) => CommentEntry(
          id: '$index',
          author: '用户 $index',
          message: '评论内容 $index',
          replyCount: 3,
        ),
      );
      await controller.load(refresh: true);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 340,
                child: VideoCommentsPanel(detail: _detail),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView));
      expect(list.childrenDelegate, isA<SliverChildBuilderDelegate>());
      expect(list.childrenDelegate.estimatedChildCount, 501);
      expect(find.byType(CommentRichContent).evaluate().length, lessThan(30));
      final first = find.byKey(const ValueKey(('comment', '0')));
      final firstElement = tester.element(first);
      controller.target(state().items.first);
      await tester.pumpAndSettle();
      expect(find.text('回复 @用户 0'), findsOneWidget);
      expect(
        identical(tester.widget<ListView>(find.byType(ListView)), list),
        isTrue,
      );
      expect(identical(tester.element(first), firstElement), isTrue);
      repo.writePending = Completer<void>();
      final write = controller.toggleLike(state().items.first);
      await tester.pump();
      expect(
        identical(tester.widget<ListView>(find.byType(ListView)), list),
        isTrue,
      );
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, BiliIcons.reply).first,
            )
            .onPressed,
        isNull,
      );
      repo.writePending!.complete();
      await write;
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconButton>(
              find.widgetWithIcon(IconButton, BiliIcons.reply).first,
            )
            .onPressed,
        isNotNull,
      );
      expect(identical(tester.element(first), firstElement), isTrue);
      expect(tester.takeException(), isNull);
    },
  );
}

const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: '视频',
    coverUrl: '',
    author: 'UP',
    duration: Duration.zero,
  ),
  description: '',
  parts: [],
  aid: '42',
);

class _LinkRepository implements CommentVideoLinkRepository {
  final pending = Completer<VideoId?>();
  RequestCancellation? cancellation;
  @override
  Future<VideoId?> resolve(
    Uri uri, {
    required RequestCancellation cancellation,
  }) {
    this.cancellation = cancellation;
    return pending.future;
  }
}

class _Repo implements VideoCommentsRepository, CommentEmotesRepository {
  Completer<List<CommentEmotePackage>>? emotePending;
  RequestCancellation? emoteCancellation;
  List<CommentEmotePackage> emotePackages = const [
    CommentEmotePackage('test', [CommentEmote('[笑]', null)]),
  ];
  @override
  Future<List<CommentEmotePackage>> emotes(RequestCancellation cancellation) {
    emoteCancellation = cancellation;
    return emotePending?.future ?? Future.value(emotePackages);
  }

  List<CommentEntry> items = [root];
  List<CommentEntry> replyItems = [child];
  int epoch = 0, writes = 0;
  bool empty = false;
  final pages = <int>[];
  final cursors = <String?>[];
  String? nextCursor, submissionMessage;
  CommentVisibility sentVisibility = CommentVisibility.unknown;
  CommentSort? sort;
  String? sentRoot, sentParent, sentText;
  Object? failure;
  Completer<CommentPage>? pending, replyPending;
  RequestCancellation? replyCancellation;
  Completer<void>? writePending;
  @override
  String get accountScope => 'user:7';
  @override
  int get sessionEpoch => epoch;
  @override
  Future<CommentPage> load(
    String aid,
    int page,
    CommentSort selected,
    RequestCancellation cancellation, {
    String? cursor,
  }) async {
    pages.add(page);
    cursors.add(cursor);
    sort = selected;
    if (pending != null) return pending!.future;
    return CommentPage(
      items: empty ? [] : items,
      hasMore: true,
      totalCount: 4,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<CommentPage> replies(
    String aid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async {
    replyCancellation = cancellation;
    return replyPending == null
        ? CommentPage(items: replyItems, hasMore: false)
        : replyPending!.future;
  }

  Future<void> write() async {
    writes++;
    final error = failure;
    if (error != null) throw error;
    if (writePending != null) await writePending!.future;
  }

  @override
  Future<void> like(
    String aid,
    String id,
    bool liked,
    RequestCancellation cancellation,
  ) => write();
  @override
  Future<CommentEntry> send(
    String aid,
    String message, {
    String? rootId,
    String? parentId,
    required RequestCancellation cancellation,
  }) async {
    await write();
    sentRoot = rootId;
    sentParent = parentId;
    sentText = message;
    return CommentEntry(
      id: '12',
      author: '我',
      message: message,
      visibility: sentVisibility,
      submissionMessage: submissionMessage,
      rootId: rootId,
      parentId: parentId,
    );
  }
}

class _UnusedPlaybackRepository extends Fake implements PlaybackRepository {}

class _UnusedProgressStore extends Fake implements PlaybackProgressStore {}

class _Auth implements AuthRepository {
  final changesController = StreamController<AuthState>.broadcast(sync: true);
  AuthState value = const AuthState(status: AuthStatus.signedIn, mid: '7');
  void emit(AuthState state) {
    value = state;
    changesController.add(state);
  }

  @override
  AuthState get current => value;
  @override
  Stream<AuthState> get changes => changesController.stream;
  @override
  Future<void> restore() async {}
  @override
  Future<void> signIn() async {}
  @override
  Future<void> signOut() async {}
  @override
  void cancelSignIn() {}
}
