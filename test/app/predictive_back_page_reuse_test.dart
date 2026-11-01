import 'package:bilisail/app/router.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_repository_provider.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/comments/application/comments_controller.dart';
import 'package:bilisail/features/comments/domain/comments_repository.dart';
import 'package:bilisail/shared/ui/comments_panel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/input_test_app.dart';
import '../support/system_back_gesture.dart';

void main() {
  testWidgets('history UI is reused and only its player mounts after commit', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const a = VideoId('BV1ab411c7mD');
    const b = VideoId('BV1xx411c7mQ');
    final videos = _Videos();
    final comments = _Comments();
    final players = <VideoId>[];
    final router = createBiliRouter(
      playerBuilder: (_, video, _) => _PlayerProbe(video.summary.id, players),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_Guest.new),
          videoCommentsRepositoryProvider.overrideWithValue(comments),
          settingsRepositoryProvider.overrideWithValue(_Settings()),
          videoRepositoryProvider.overrideWithValue(videos),
          homeRepositoryProvider.overrideWithValue(_Home()),
          feedRepositoryProvider.overrideWithValue(_Feed()),
        ],
        child: InputTestApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
    final header = tester.element(
      find.byKey(const ValueKey('workspace-search')),
    );
    final navigation = tester.element(
      find.byKey(const ValueKey('workspace-bottom-navigation')),
    );
    final headerRect = tester.getRect(
      find.byKey(const ValueKey('workspace-search')),
    );
    router.go('/video/${a.value}');
    await tester.pumpAndSettle();
    Finder page(VideoId id) => find.byWidgetPredicate(
      (widget) => widget is VideoScreen && widget.id == id,
    );
    final stateA = tester.state(page(a));
    await tester.tap(find.text('评论'));
    await tester.pumpAndSettle();
    final commentState = tester.state(find.byType(CommentsPanel));
    expect(comments.loads['11'], 1);
    final commentScrollFinder = find.descendant(
      of: find.byType(CommentsPanel),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is Scrollable && widget.axisDirection == AxisDirection.down,
      ),
    );
    await tester.drag(find.byType(CommentsPanel), const Offset(0, -180));
    await tester.pumpAndSettle();
    final commentScroll = commentScrollFinder
        .evaluate()
        .map((element) => (element as StatefulElement).state)
        .whereType<ScrollableState>()
        .firstWhere((state) => state.position.pixels > 0);
    final commentOffset = commentScroll.position.pixels;
    expect(commentOffset, greaterThan(0));
    router.go('/video/${b.value}');
    await tester.pumpAndSettle();
    expect(players, [a, b]);
    expect(videos.loads, {a: 1, b: 1});
    final commentLoads = Map.of(comments.loads);
    expect(await systemBackGesture(tester, 'startBackGesture'), isTrue);
    await tester.pumpAndSettle();
    expect(tester.state(page(a)), same(stateA));
    expect(tester.state(find.byType(CommentsPanel)), same(commentState));
    expect(
      commentScrollFinder.evaluate().any(
        (element) => (element as StatefulElement).state == commentScroll,
      ),
      isTrue,
    );
    expect(commentScroll.position.pixels, commentOffset);
    expect(WorkspaceActivity.isActive(tester.element(page(a))), isFalse);
    expect(WorkspaceActivity.isVisible(tester.element(page(a))), isTrue);
    expect(
      find.byKey(const ValueKey('workspace-preview-player')),
      findsOneWidget,
    );
    expect(players, [a, b]);
    expect(videos.loads, {a: 1, b: 1});
    await systemBackGesture(tester, 'cancelBackGesture');
    await tester.pumpAndSettle();
    expect(players, [a, b]);
    expect(router.routeInformationProvider.value.uri.path, '/video/${b.value}');
    await systemBackGesture(tester, 'startBackGesture');
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(tester.state(page(a)), same(stateA));
    expect(players, [a, b, a]);
    expect(tester.state(find.byType(CommentsPanel)), same(commentState));
    expect(
      commentScrollFinder.evaluate().any(
        (element) => (element as StatefulElement).state == commentScroll,
      ),
      isTrue,
    );
    expect(commentScroll.position.pixels, commentOffset);
    expect(comments.loads, commentLoads);
    expect(videos.loads, {a: 1, b: 1});
    expect(
      find.byKey(const ValueKey('workspace-preview-player')),
      findsNothing,
    );

    await systemBackGesture(tester, 'startBackGesture');
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byKey(const ValueKey('workspace-search'))),
      same(header),
    );
    expect(
      tester.element(find.byKey(const ValueKey('workspace-bottom-navigation'))),
      same(navigation),
    );
    await systemBackGesture(tester, 'commitBackGesture');
    await tester.pumpAndSettle();
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(
      tester.element(find.byKey(const ValueKey('workspace-search'))),
      same(header),
    );
    expect(
      tester.element(find.byKey(const ValueKey('workspace-bottom-navigation'))),
      same(navigation),
    );
    expect(
      tester.getRect(find.byKey(const ValueKey('workspace-search'))),
      headerRect,
    );
    expect(players, [a, b, a]);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

class _PlayerProbe extends StatefulWidget {
  const _PlayerProbe(this.id, this.opens);
  final VideoId id;
  final List<VideoId> opens;
  @override
  State<_PlayerProbe> createState() => _PlayerProbeState();
}

class _PlayerProbeState extends State<_PlayerProbe> {
  @override
  void initState() {
    super.initState();
    widget.opens.add(widget.id);
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

class _Videos implements VideoRepository {
  final loads = <VideoId, int>{};
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    loads.update(id, (n) => n + 1, ifAbsent: () => 1);
    return VideoDetail(
      aid: id.value == 'BV1ab411c7mD' ? '11' : '22',
      summary: VideoSummary(
        id: id,
        title: '视频 ${id.value}',
        coverUrl: '',
        author: 'UP',
        duration: const Duration(minutes: 2),
      ),
      description: '保留简介和评论组件',
      parts: const [
        VideoPart(
          cid: '1',
          page: 1,
          title: '第一集',
          duration: Duration(minutes: 2),
        ),
      ],
    );
  }
}

class _Guest extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _Comments extends Fake implements CommentsRepository {
  final loads = <String, int>{};
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
  }) async {
    loads.update(oid, (n) => n + 1, ifAbsent: () => 1);
    return CommentPage(
      items: List.generate(
        20,
        (i) => CommentEntry(id: '$i', author: '读者', message: '一条评论 $i'),
      ),
      hasMore: false,
    );
  }
}

class _Settings implements SettingsRepository {
  @override
  Future<AppSettings> load() async => const AppSettings.defaults(
    navigationMode: WorkspaceNavigationMode.dualTabs,
  );
  @override
  Future<void> save(AppSettings settings) async {}
}

class _Home implements HomeRepository {
  @override
  String get accountScope => 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => const HomePage([], hasMore: false);
}

class _Feed implements FeedRepository {
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
}
