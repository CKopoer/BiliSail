import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/comment_target.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_screen.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/shared/ui/playback_info_tabs.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../support/detached_window_fake.dart';
import '../support/input_test_app.dart';

const _id = VideoId('BV1ab411c7mD');
const _target = CommentTarget('42', CommentTargetType.video);
const _root = CommentEntry(
  id: '10',
  author: '甲',
  message: '原评论',
  replyCount: 3,
);
const _reply = CommentEntry(
  id: '11',
  author: '乙',
  message: '二级回复',
  rootId: '10',
  parentId: '10',
);
const _detail = VideoDetail(
  aid: '42',
  summary: VideoSummary(
    id: _id,
    title: '测试视频',
    coverUrl: '',
    author: 'UP',
    duration: Duration(minutes: 1),
  ),
  description: '',
  parts: [
    VideoPart(cid: '1', page: 1, title: 'P1', duration: Duration(minutes: 1)),
  ],
);
final _season = PgcSeason(
  id: const PgcSeasonId('1'),
  title: '测试影视',
  description: '',
  episodes: const [
    PgcEpisode(
      id: PgcEpisodeId('1'),
      title: '1',
      aid: '42',
      bvid: 'BV1ab411c7mD',
      cid: '1',
    ),
  ],
);

void main() {
  for (final platform in [TargetPlatform.android, TargetPlatform.windows]) {
    for (final pgc in [false, true]) {
      testWidgets(
        '${platform.name} ${pgc ? 'PGC' : 'video'} detail owns back and preserves the player',
        (tester) async {
          final harness = await _mount(tester, platform: platform, pgc: pgc);
          final player = tester.element(
            find.byKey(const ValueKey('test-player')),
          );
          final infoTop = tester.getTopLeft(find.byType(PlaybackInfoTabs)).dy;
          final location = harness.router.routeInformationProvider.value.uri;

          for (final action in [
            'button',
            'close',
            'system',
            'shortcut',
            'mouse',
          ]) {
            await _openDetail(tester);
            expect(find.text('简介'), findsNothing);
            expect(find.text('评论'), findsNothing);
            expect(
              tester.getTopLeft(find.byTooltip('返回评论')).dy,
              closeTo(infoTop, 4),
            );
            await tester.drag(find.text('原评论'), const Offset(280, 0));
            await tester.pumpAndSettle();
            expect(find.text('评论详情'), findsOneWidget);
            switch (action) {
              case 'button':
                await tester.tap(find.byTooltip('返回评论'));
              case 'close':
                await tester.tap(find.byTooltip('关闭评论详情'));
              case 'system':
                await tester.binding.handlePopRoute();
              case 'shortcut':
                await tester.enterText(find.byType(TextField), '保留草稿');
                await _closeShortcut(tester);
              case 'mouse':
                await _mouseBack(tester);
            }
            await tester.pumpAndSettle();
            expect(find.text('评论详情'), findsNothing, reason: action);
            expect(find.text('简介'), findsOneWidget);
            expect(find.text('共 3 条回复 ›'), findsOneWidget);
            expect(harness.router.routeInformationProvider.value.uri, location);
            expect(
              tester.element(find.byKey(const ValueKey('test-player'))),
              same(player),
            );
          }
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text,
            '保留草稿',
          );
          await _closeShortcut(tester);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('test-player')), findsNothing);
          expect(find.text('首页内容'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant.only(platform),
      );
    }
  }

  for (final pgc in [false, true]) {
    testWidgets(
      'desktop dual ${pgc ? 'PGC' : 'video'} detail consumes side and keyboard back before closing',
      (tester) async {
        final harness = await _mount(tester, pgc: pgc, detached: true);
        final window = harness.windows.lastWindow!;
        final composer = find.descendant(
          of: find.byType(CommentsPanel),
          matching: find.byType(TextField),
        );
        final player = tester.element(
          find.byKey(const ValueKey('test-player')),
        );
        final location = harness.router.routeInformationProvider.value.uri;
        expect(View.of(player).viewId, window.viewId);

        for (final action in ['mouse', 'shortcut']) {
          await _openDetail(tester);
          await tester.enterText(composer, '保留草稿');
          final dialog = showDialog<void>(
            context: tester.element(find.byType(CommentsPanel)),
            useRootNavigator: false,
            barrierDismissible: false,
            requestFocus: false,
            builder: (_) => const AlertDialog(content: Text('模态窗口')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text('评论详情'),
            findsOneWidget,
            reason: 'before modal input',
          );
          await _mouseBack(tester, viewId: window.viewId);
          expect(find.text('评论详情'), findsOneWidget, reason: 'modal mouse');
          await _closeShortcut(tester);
          expect(find.text('评论详情'), findsOneWidget, reason: 'modal shortcut');
          expect(find.text('模态窗口'), findsOneWidget);
          expect(window.disposed, isFalse);
          Navigator.of(tester.element(find.text('模态窗口'))).pop();
          await tester.pumpAndSettle();
          await dialog;
          await tester.enterText(composer, '保留草稿');

          if (action == 'mouse') {
            await _mouseBack(tester, viewId: window.viewId);
          } else {
            await _closeShortcut(tester);
          }
          await tester.pumpAndSettle();
          expect(find.text('评论详情'), findsNothing, reason: action);
          expect(find.text('共 3 条回复 ›'), findsOneWidget);
          expect(harness.router.routeInformationProvider.value.uri, location);
          expect(window.disposed, isFalse);
          expect(harness.windows.creationCount, 1);
          expect(
            tester.element(find.byKey(const ValueKey('test-player'))),
            same(player),
          );
          expect(tester.widget<TextField>(composer).controller?.text, '保留草稿');
        }

        await _mouseBack(tester, viewId: window.viewId);
        await tester.pumpAndSettle();
        expect(window.disposed, isTrue);
        expect(find.byKey(const ValueKey('test-player')), findsNothing);
        expect(find.text('首页内容'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'desktop dual side back consumes comment detail before media history',
    (tester) async {
      final harness = await _mount(tester, detached: true);
      final window = harness.windows.lastWindow!;
      harness.router.go('/pgc/1');
      await tester.pumpAndSettle();
      await tester.tap(find.text('评论'));
      await tester.pumpAndSettle();
      await _openDetail(tester);

      await _mouseBack(tester, viewId: window.viewId);
      await tester.pumpAndSettle();
      expect(find.text('评论详情'), findsNothing);
      expect(harness.router.routeInformationProvider.value.uri.path, '/pgc/1');
      expect(window.disposed, isFalse);

      await _mouseBack(tester, viewId: window.viewId);
      await tester.pumpAndSettle();
      expect(
        harness.router.routeInformationProvider.value.uri.path,
        '/video/BV1ab411c7mD',
      );
      expect(window.disposed, isFalse);
      expect(harness.windows.creationCount, 1);

      await _mouseBack(tester, viewId: window.viewId);
      await tester.pumpAndSettle();
      expect(window.disposed, isTrue);
      expect(find.text('首页内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'modal and inactive pages cannot consume the active workspace back',
    (tester) async {
      final harness = await _mount(tester);
      await _openDetail(tester);
      final dialog = showDialog<void>(
        context: tester.element(find.byType(CommentsPanel)),
        barrierDismissible: false,
        builder: (_) => const AlertDialog(content: Text('模态窗口')),
      );
      await tester.pumpAndSettle();
      await _closeShortcut(tester);
      expect(find.text('评论详情'), findsOneWidget, reason: 'shortcut while modal');
      await _mouseBack(tester);
      expect(find.text('评论详情'), findsOneWidget, reason: 'mouse while modal');
      expect(find.text('模态窗口'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await dialog;
      expect(find.text('评论详情'), findsOneWidget);

      harness.router.go('/search?q=detail');
      await tester.pumpAndSettle();
      expect(find.text('搜索内容'), findsOneWidget);
      await _closeShortcut(tester);
      await tester.pumpAndSettle();
      expect(find.text('评论详情'), findsOneWidget);
      await _mouseBack(tester);
      await tester.pumpAndSettle();
      expect(find.text('评论详情'), findsNothing);
      expect(find.byKey(const ValueKey('test-player')), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets('back cancels pending replies and ignores their late result', (
    tester,
  ) async {
    final harness = await _mount(tester);
    harness.repo.pending = Completer<CommentPage>();
    await tester.tap(find.text('共 3 条回复 ›'));
    await tester.pump();
    await tester.pump();
    expect(find.text('评论详情'), findsOneWidget);
    await _mouseBack(tester);
    await tester.pumpAndSettle();
    expect(harness.repo.replyCancellation?.isCancelled, isTrue);
    harness.repo.pending!.complete(
      const CommentPage(items: [_reply], hasMore: false),
    );
    await tester.pumpAndSettle();
    expect(find.text('评论详情'), findsNothing);
    expect(find.text('二级回复'), findsNothing);
    expect(find.byKey(const ValueKey('test-player')), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
    'standalone comments use system back without popping their route',
    (tester) async {
      final repo = _Comments();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authControllerProvider.overrideWith(_Guest.new),
            videoCommentsRepositoryProvider.overrideWithValue(repo),
          ],
          child: const InputTestApp(
            home: Scaffold(
              body: WorkspaceActivity(
                active: true,
                child: CommentsPanel(target: _target),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await _openDetail(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('共 3 条回复 ›'), findsOneWidget);
      expect(find.text('评论详情'), findsNothing);
    },
  );
}

Future<({GoRouter router, _Comments repo, FakeDetachedWindowFactory windows})>
_mount(
  WidgetTester tester, {
  TargetPlatform platform = TargetPlatform.windows,
  bool pgc = false,
  bool detached = false,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(
    platform == TargetPlatform.android ? 390 : 1200,
    844,
  );
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final repo = _Comments();
  final windows = FakeDetachedWindowFactory(tester.view);
  final shortcuts = const ShortcutSettings.defaults().withKeys(
    ShortcutAction.closeTab,
    ['Ctrl+W', 'MouseBack'],
  );
  final router = GoRouter(
    observers: [],
    routes: [
      ShellRoute(
        observers: [],
        builder: (_, state, child) => BiliAppShell(
          location: state.uri.toString(),
          shortcuts: shortcuts,
          navigationMode: detached || platform == TargetPlatform.android
              ? WorkspaceNavigationMode.dualTabs
              : WorkspaceNavigationMode.multipleTabs,
          playbackWindowBuilder: detached
              ? (
                  context, {
                  required child,
                  required playback,
                  required keepPlaybackMounted,
                  required activationToken,
                  required onClose,
                  required onBack,
                  required onHome,
                  required onError,
                }) => DesktopPlaybackWindow(
                  keepPlaybackMounted: keepPlaybackMounted,
                  windowFactory: windows.call,
                  activationToken: activationToken,
                  onCloseRequested: onClose,
                  onError: onError,
                  playback: playback == null
                      ? null
                      : WorkspacePlaybackWindow(
                          theme: ThemeData(),
                          shortcuts: shortcuts,
                          onClose: onClose,
                          onBack: onBack,
                          onHome: onHome,
                          onActivateBrowser: () {},
                          child: playback,
                        ),
                  child: child,
                )
              : null,
          pageBuilder: (_, tab) => switch (tab.location.path) {
            '/video/BV1ab411c7mD' => VideoScreen(
              id: _id,
              playerBuilder: (_, _, _) =>
                  const SizedBox.expand(key: ValueKey('test-player')),
            ),
            '/pgc/1' => PgcScreen(
              seasonId: '1',
              playerBuilder: (_, _, _) =>
                  const SizedBox.expand(key: ValueKey('test-player')),
              commentsBuilder: (_, _, _) =>
                  const CommentsPanel(target: _target),
            ),
            '/search' => const Text('搜索内容'),
            _ => const Text('首页内容'),
          },
          child: child,
        ),
        routes: [
          for (final path in ['/', '/video/BV1ab411c7mD', '/pgc/1', '/search'])
            GoRoute(path: path, builder: (_, _) => const SizedBox.shrink()),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_Guest.new),
        videoCommentsRepositoryProvider.overrideWithValue(repo),
        videoDetailProvider(_id).overrideWith((_) async => _detail),
        relatedVideosProvider(_id).overrideWith((_) async => []),
        videoTagsProvider(_id).overrideWith((_) async => []),
        pgcRepositoryProvider.overrideWithValue(_Pgc()),
      ],
      child: InputTestApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  router.go(pgc ? '/pgc/1' : '/video/BV1ab411c7mD');
  await tester.pumpAndSettle();
  if (detached) {
    tester.binding.handleViewFocusChanged(
      ViewFocusEvent(
        viewId: windows.lastWindow!.viewId,
        state: ViewFocusState.focused,
        direction: ViewFocusDirection.undefined,
      ),
    );
    await tester.pumpAndSettle();
  }
  await tester.tap(find.text('评论'));
  await tester.pumpAndSettle();
  return (router: router, repo: repo, windows: windows);
}

Future<void> _openDetail(WidgetTester tester) async {
  await tester.tap(find.text('共 3 条回复 ›'));
  await tester.pumpAndSettle();
  expect(find.text('评论详情'), findsOneWidget);
}

Future<void> _closeShortcut(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await tester.pump();
}

Future<void> _mouseBack(WidgetTester tester, {int? viewId}) async {
  tester.binding.handlePointerEvent(
    PointerDownEvent(
      viewId: viewId ?? tester.view.viewId,
      kind: PointerDeviceKind.mouse,
      buttons: kBackMouseButton,
      position: const Offset(20, 200),
    ),
  );
  tester.binding.handlePointerEvent(
    PointerUpEvent(
      viewId: viewId ?? tester.view.viewId,
      kind: PointerDeviceKind.mouse,
      position: const Offset(20, 200),
    ),
  );
  await tester.pump();
}

class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, mid: '7');
}

class _Comments extends Fake implements CommentsRepository {
  Completer<CommentPage>? pending;
  RequestCancellation? replyCancellation;
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<CommentPage> load(
    String oid,
    int page,
    CommentSort sort,
    RequestCancellation cancellation, {
    String? cursor,
  }) async => const CommentPage(items: [_root], hasMore: false);
  @override
  Future<CommentPage> replies(
    String oid,
    String rootId,
    int page,
    RequestCancellation cancellation,
  ) async {
    replyCancellation = cancellation;
    return pending?.future ??
        Future.value(const CommentPage(items: [_reply], hasMore: false));
  }
}

class _Pgc extends Fake implements PgcRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    bool refresh = false,
    required RequestCancellation cancellation,
  }) async => _season;
}
