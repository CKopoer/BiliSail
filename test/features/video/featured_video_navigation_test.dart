import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/workspace_root_page.dart';
import 'package:bilisail/core/presentation/input_scope.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/features/feed/application/featured_feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/featured_video_screen.dart';
import 'package:bilisail/shared/ui/measured_list_view.dart';
import 'package:bilisail/shared/ui/playback_page_commands.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/input_test_app.dart';

void main() {
  for (final (width, prefix) in [
    (390.0, 'workspace-bottom'),
    (1200.0, 'workspace-nav'),
  ]) {
    testWidgets('$prefix refreshes only when featured is already selected', (
      tester,
    ) async {
      _size(tester, width);
      final videos = _Videos();
      final router = GoRouter(
        initialLocation: '/',
        routes: [
          ShellRoute(
            builder: (_, state, child) => BiliAppShell(
              location: state.uri.toString(),
              navigationMode: WorkspaceNavigationMode.singlePage,
              pageBuilder: (_, tab) => WorkspaceRootPage(
                location: tab.location,
                featuredBuilder: (_, _) => _screen(videos),
                feedBuilder: _placeholder,
                accountBuilder: _placeholder,
                messagesBuilder: _placeholder,
                downloadsBuilder: _placeholder,
                settingsBuilder: _placeholder,
              ),
              child: child,
            ),
            observers: [],
            routes: [
              for (final path in ['/', '/featured', '/me'])
                GoRoute(path: path, builder: (_, _) => const SizedBox()),
            ],
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        _withVideos(videos, InputTestApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();

      Future<void> select(String section, {String? using}) async {
        await tester.tap(find.byKey(ValueKey('${using ?? prefix}-$section')));
        await tester.pumpAndSettle();
      }

      expect(videos.refreshes, isEmpty);
      await select('featured');
      expect(videos.refreshes, [false]);
      expect(find.byTooltip('换一批'), findsNothing);
      expect(find.byTooltip('上一条'), findsNothing);
      expect(find.byTooltip('下一条'), findsNothing);
      expect(find.text('精选'), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);

      videos.failNext = true;
      await select('featured');
      expect(videos.refreshes, [false, true]);
      expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
      await tester.tap(find.textContaining('重试'));
      await tester.pumpAndSettle();
      expect(videos.refreshes, [false, true, true]);
      expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await select('mine');
      await select('featured');
      expect(videos.refreshes, [false, true, true]);
      expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
      router.go('/me');
      await tester.pumpAndSettle();
      router.go('/featured?tab=home');
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
      expect(videos.refreshes, hasLength(3));
      final otherWidth = width > 600 ? 390.0 : 1200.0;
      tester.view.display.size = Size(otherWidth, 800);
      tester.view.physicalSize = Size(otherWidth, 800);
      await tester.pumpAndSettle();
      expect(videos.refreshes, hasLength(3));
      expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
      await select(
        'featured',
        using: width > 600 ? 'workspace-bottom' : 'workspace-nav',
      );
      expect(videos.refreshes, [false, true, true, true]);
      expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
    });
  }

  for (final comments in [true, false]) {
    testWidgets(
      'featured ${comments ? 'comments' : 'description'} scroll leaves the bottom navigation alone',
      (tester) async {
        _size(tester, 390);
        final videos = _Videos(withPanelContent: true);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              authControllerProvider.overrideWith(_GuestAuth.new),
              videoRepositoryProvider.overrideWithValue(videos),
              videoCommentsRepositoryProvider.overrideWithValue(_Comments()),
            ],
            child: InputTestApp(
              home: BiliAppShell(
                location: '/featured',
                navigationMode: WorkspaceNavigationMode.singlePage,
                pageBuilder: (_, _) => _screen(videos),
                child: const SizedBox.shrink(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final bar = find.byKey(const ValueKey('workspace-bottom-navigation'));
        final pager = find.byType(PageView);
        final list = find.byType(comments ? MeasuredListView : ListView);
        ScrollPosition position() => tester
            .state<ScrollableState>(
              find
                  .descendant(of: list, matching: find.byType(Scrollable))
                  .first,
            )
            .position;

        Future<void> openPanel(int clip) async {
          await tester.tap(
            comments
                ? find.byIcon(Icons.chat_bubble_outline)
                : find.text('片段 $clip'),
          );
          await tester.pumpAndSettle();
        }

        Future<void> wheel(Finder area, double dy) async {
          tester.binding.handlePointerEvent(
            PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: tester.getCenter(area),
              scrollDelta: Offset(0, dy),
            ),
          );
          await tester.pumpAndSettle();
          await tester.pump(const Duration(milliseconds: 190));
        }

        Future<void> drag(double dy) async {
          await tester.timedDrag(
            list,
            Offset(0, dy),
            const Duration(milliseconds: 300),
          );
          await tester.pumpAndSettle();
        }

        expect(bar.hitTestable(), findsOneWidget);
        await openPanel(1);
        await drag(-160);
        final afterDrag = position().pixels;
        expect(afterDrag, greaterThan(0));
        expect(bar.hitTestable(), findsOneWidget);
        await wheel(list, 130);
        expect(position().pixels, greaterThan(afterDrag));
        expect(bar.hitTestable(), findsOneWidget);

        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        await wheel(pager, 130);
        expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
        expect(bar, findsNothing);

        await openPanel(2);
        position().jumpTo(300);
        await tester.pumpAndSettle();
        await drag(120);
        final afterReverseDrag = position().pixels;
        expect(afterReverseDrag, lessThan(300));
        expect(bar, findsNothing);
        await wheel(list, -130);
        expect(position().pixels, lessThan(afterReverseDrag));
        expect(bar, findsNothing);
        position().jumpTo(0);
        await tester.pumpAndSettle();
        await wheel(list, -130);
        await drag(120);
        expect(bar, findsNothing);

        await tester.tap(find.byType(CloseButton));
        await tester.pumpAndSettle();
        await wheel(pager, -130);
        expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
        expect(bar.hitTestable(), findsOneWidget);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );
  }

  testWidgets(
    'arrows page without picture focus and yield to editors and overlays',
    (tester) async {
      _size(tester, 1200);
      final videos = _Videos();
      await tester.pumpWidget(
        _withVideos(
          videos,
          InputTestApp(
            shortcuts: const ShortcutSettings.defaults().withEnabled(false),
            home: Scaffold(body: _screen(videos, withEditor: true)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> press(LogicalKeyboardKey key) async {
        await tester.sendKeyEvent(key);
        await tester.pumpAndSettle();
      }

      final onFirst = find.byKey(const ValueKey('playing-1'));
      final onSecond = find.byKey(const ValueKey('playing-2'));
      expect(onFirst, findsOneWidget);
      await press(LogicalKeyboardKey.arrowDown);
      expect(onSecond, findsOneWidget);
      await press(LogicalKeyboardKey.arrowUp);
      expect(onFirst, findsOneWidget);

      final editor = find.byType(TextField);
      await tester.enterText(editor, 'draft');
      await press(LogicalKeyboardKey.arrowDown);
      expect(onFirst, findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      final player = tester.element(
        find.byKey(const ValueKey('test-controls')),
      );
      await tester.tap(find.byKey(const ValueKey('open-test-comments')));
      await tester.pumpAndSettle();
      expect(find.text('暂无评论信息'), findsOneWidget);
      await press(LogicalKeyboardKey.arrowDown);
      expect(onFirst, findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();

      final navigator = Navigator.of(player);
      final input = InputScope.of<Object>(player)!;
      for (final presentation in [false, true]) {
        final route = RawDialogRoute<void>(
          requestFocus: false,
          pageBuilder: (_, _, _) =>
              Center(child: Text(presentation ? 'Fullscreen' : 'Menu')),
        );
        if (presentation) input.routes.presentation(route);
        navigator.push(route);
        await tester.pumpAndSettle();
        await press(LogicalKeyboardKey.arrowDown);
        expect(onSecond, findsNothing);
        navigator.pop();
        await tester.pumpAndSettle();
        expect(onFirst, findsOneWidget);
      }

      final pager = find.byType(PageView);
      tester.binding.handlePointerEvent(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(pager),
          scrollDelta: const Offset(0, 50),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 200));
      expect(onSecond, findsOneWidget);
    },
  );

  testWidgets('seeded viewing retains an on-screen return button', (
    tester,
  ) async {
    _size(tester, 390);
    final videos = _Videos();
    var returns = 0;
    await tester.pumpWidget(
      _withVideos(
        videos,
        InputTestApp(
          home: Scaffold(
            body: _screen(videos, onReturnToVideo: () => returns++),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(BackButton));
    expect(returns, 1);
  });
}

void _size(WidgetTester tester, double width) {
  tester.view.devicePixelRatio = 1;
  tester.view.display.size = Size(width, 800);
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.display.resetSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _placeholder(BuildContext context, Uri location) => const SizedBox();

Widget _withVideos(_Videos videos, Widget child) => ProviderScope(
  overrides: [videoRepositoryProvider.overrideWithValue(videos)],
  child: child,
);

Widget _screen(
  _Videos videos, {
  bool withEditor = false,
  VoidCallback? onReturnToVideo,
}) => FeaturedVideoScreen(
  onReturnToVideo: onReturnToVideo,
  createController: () => FeaturedFeedController(
    videos,
    FeaturedSource.desktop,
    RecommendationFilter(const RecommendationSettings.defaults()),
    seed: onReturnToVideo == null
        ? null
        : (video: videos.items.first.id, cid: '1', aid: null, trackId: null),
  ),
  playerBuilder: (context, detail, part) => ColoredBox(
    key: ValueKey('playing-${part.cid}'),
    color: Colors.black,
    child: withEditor
        ? Center(
            key: const ValueKey('test-controls'),
            child: SizedBox(
              width: 160,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const TextField(),
                  TextButton(
                    key: const ValueKey('open-test-comments'),
                    onPressed: () =>
                        PlaybackPageCommands.maybeOf(context)?.toggleComments
                            ?.call(),
                    child: const Text('测试评论'),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.expand(),
  ),
  onLogin: () {},
  onOpenUser: (_) {},
  splitWidth: 1000,
);

class _Videos implements FeaturedFeedRepository, VideoRepository {
  _Videos({this.withPanelContent = false});

  final bool withPanelContent;
  final items = List.generate(5, (index) {
    final i = index + 1;
    return VideoSummary(
      id: VideoId('BV123456789$i'),
      title: '片段 $i',
      coverUrl: '',
      author: '作者',
      duration: const Duration(minutes: 1),
      previewCid: '$i',
    );
  });
  final refreshes = <bool>[];
  bool failNext = false;

  @override
  Future<PageResult<VideoSummary>> loadFeatured({
    required FeaturedSource source,
    required int batch,
    required bool refresh,
    FeaturedSeed? seed,
    required RequestCancellation cancellation,
  }) async {
    refreshes.add(refresh);
    if (failNext) {
      failNext = false;
      throw StateError('offline');
    }
    return PageResult(items: items, hasMore: false);
  }

  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    final item = items.singleWhere((video) => video.id == id);
    return VideoDetail(
      summary: item,
      aid: withPanelContent ? item.previewCid : null,
      description: withPanelContent ? '分段简介\n' * 60 : '简介',
      parts: [
        VideoPart(
          cid: item.previewCid!,
          page: 1,
          title: item.title,
          duration: item.duration,
        ),
      ],
    );
  }
}

class _Comments extends Fake implements CommentsRepository {
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
  }) async => CommentPage(
    items: List.generate(
      40,
      (index) => CommentEntry(
        id: '$index',
        author: '用户 $index',
        message: '评论内容 $index',
      ),
    ),
    hasMore: false,
  );
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState();
}
