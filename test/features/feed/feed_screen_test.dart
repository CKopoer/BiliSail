import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:bilisail/shared/ui/bili_badges.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';

void main() {
  testWidgets(
    'mouse wheel exposes and selects the final home subtab in a narrow viewport',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 850);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final repository = _HomeRepository(folders: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(repository),
          ],
          child: MaterialApp(
            theme: ThemeData(platform: TargetPlatform.windows),
            home: const Scaffold(
              body: FeedScreen(
                channel: HomeChannel.favorites,
                isSignedIn: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final strip = find.byKey(const ValueKey('home-section-strip-favorites'));
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: strip, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(strip),
          scrollDelta: const Offset(0, 1200),
        ),
      );
      await tester.pumpAndSettle();
      final lastTab = find.byKey(const ValueKey('home-section-我的追剧'));
      expect(lastTab.hitTestable(), findsOneWidget);
      await tester.tap(lastTab);
      await tester.pumpAndSettle();
      expect(find.text('追剧内容'), findsOneWidget);
      expect(repository.calls.last, 'favorites:我的追剧');
      await tester.sendEventToBinding(
        PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: tester.getCenter(strip),
          scrollDelta: const Offset(-1200, 0),
        ),
      );
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, 0);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'entering and returning to a favorite folder retains both lists',
    (tester) async {
      final repository = _HomeRepository(folders: true);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(_FeedRepository()),
            homeRepositoryProvider.overrideWithValue(repository),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: FeedScreen(
                channel: HomeChannel.favorites,
                isSignedIn: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('home-section-我创建的收藏夹')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('收藏夹A'));
      await tester.pumpAndSettle();
      expect(find.text('夹内视频'), findsOneWidget);
      expect(find.byType(VideoCard), findsOneWidget);
      await tester.tap(find.byTooltip('返回列表'));
      await tester.pumpAndSettle();
      expect(find.text('收藏夹A'), findsOneWidget);
      await tester.tap(find.text('收藏夹A'));
      await tester.pumpAndSettle();
      expect(find.text('夹内视频'), findsOneWidget);
      expect(repository.calls, [
        'favorites:默认收藏夹',
        'favorites:我创建的收藏夹',
        'favorites:我创建的收藏夹:A',
      ]);
    },
  );
  testWidgets('five favorite tabs keep collection paths and loaded contents', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _HomeRepository(folders: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          homeRepositoryProvider.overrideWithValue(repository),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: FeedScreen(channel: HomeChannel.favorites, isSignedIn: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    for (final tab in ['默认收藏夹', '我创建的收藏夹', '我的收藏与订阅', '我的追番', '我的追剧']) {
      expect(find.byKey(ValueKey('home-section-$tab')), findsOneWidget);
    }
    expect(find.byType(VideoCard), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-section-我的收藏与订阅')));
    await tester.pumpAndSettle();
    expect(find.byType(FavoriteFolderCard), findsOneWidget);
    expect(find.text('38个内容'), findsOneWidget);
    expect(find.text('合集'), findsOneWidget);
    await tester.tap(find.text('订阅合集'));
    await tester.pumpAndSettle();
    expect(repository.calls.last, 'favorites:我的收藏与订阅:ugc:42');
    expect(find.byType(VideoCard), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-section-我的追剧')));
    await tester.pumpAndSettle();
    expect(find.text('追剧内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-section-我的追番')));
    await tester.pumpAndSettle();
    expect(find.text('追番内容'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('home-section-我的收藏与订阅')));
    await tester.pumpAndSettle();
    expect(find.text('夹内视频'), findsOneWidget);
    await tester.tap(find.byTooltip('返回列表'));
    await tester.pumpAndSettle();
    expect(find.text('订阅合集'), findsOneWidget);
    expect(repository.calls.where((e) => e.contains('ugc:42')), hasLength(1));
    expect(tester.takeException(), isNull);
  });
  testWidgets('subchannels preserve loaded lists on round-trip', (
    tester,
  ) async {
    final repository = _HomeRepository();
    final channel = ValueNotifier(HomeChannel.bangumi);
    addTearDown(channel.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          feedRepositoryProvider.overrideWithValue(_FeedRepository()),
          homeRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: channel,
              builder: (context, value, child) => FeedScreen(channel: value),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('时间表'));
    await tester.pumpAndSettle();
    expect(find.text('番剧时间表'), findsOneWidget);
    channel.value = HomeChannel.cinema;
    await tester.pumpAndSettle();
    channel.value = HomeChannel.bangumi;
    await tester.pumpAndSettle();
    expect(find.text('番剧时间表'), findsOneWidget);
    expect(repository.calls.where((call) => call == 'bangumi:时间表').length, 1);
  });
  testWidgets('feed error retries and retains compact content', (tester) async {
    final repository = _FeedRepository(failFirst: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.text('网络暂时不可用'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('推荐视频'), findsOneWidget);
    expect(find.byType(VideoCard), findsOneWidget);
    expect(find.text('已关注'), findsOneWidget);
    expect(find.byType(BiliUpBadge), findsNothing);
    expect(find.text('热门精选'), findsNothing);
    expect(repository.calls, ['recommended:1', 'recommended:1']);
    await tester.tap(find.byTooltip('刷新视频'));
    await tester.pumpAndSettle();
    expect(repository.calls.length, 3);
  });

  testWidgets('channels have distinct content and restore loaded lists', (
    tester,
  ) async {
    final repository = _FeedRepository();
    final channel = ValueNotifier(HomeChannel.recommended);
    addTearDown(channel.dispose);
    await tester.pumpWidget(_app(repository, channel: channel));
    await tester.pumpAndSettle();
    channel.value = HomeChannel.popular;
    await tester.pumpAndSettle();
    expect(find.text('热门视频'), findsOneWidget);
    expect(find.text('已关注'), findsNothing);
    expect(find.text('推荐视频'), findsNothing);
    channel.value = HomeChannel.recommended;
    await tester.pumpAndSettle();
    expect(find.text('推荐视频'), findsOneWidget);
    expect(repository.calls, ['recommended:1', 'popular:1']);
    channel.value = HomeChannel.categories;
    await tester.pumpAndSettle();
    expect(find.text('分区1视频'), findsOneWidget);
    await tester.tap(find.text('音乐'));
    await tester.pumpAndSettle();
    expect(find.text('分区3视频'), findsOneWidget);
    channel.value = HomeChannel.ranking;
    await tester.pumpAndSettle();
    expect(find.text('排行0视频'), findsOneWidget);
    expect(find.text('推荐视频'), findsNothing);
    expect(repository.calls.last, 'ranking:0');
  });

  testWidgets('native content subnavigation and login work at narrow width', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FeedRepository();
    final channel = ValueNotifier(HomeChannel.bangumi);
    addTearDown(channel.dispose);
    var loginCalls = 0;
    await tester.pumpWidget(
      _app(repository, channel: channel, onLogin: () => loginCalls++),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('时间表'));
    await tester.pumpAndSettle();
    expect(find.text('番剧时间表'), findsOneWidget);
    channel.value = HomeChannel.dynamic;
    await tester.pumpAndSettle();
    expect(find.text('登录后可查看动态'), findsOneWidget);
    await tester.tap(find.text('登录账号'));
    expect(loginCalls, 1);
    expect(repository.calls, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pagination error preserves list and retries failed page', (
    tester,
  ) async {
    final repository = _FeedRepository(paginated: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(find.text('推荐视频'), findsOneWidget);
    expect(find.text('下一页加载失败'), findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('第二页视频'), findsOneWidget);
    expect(repository.calls, [
      'recommended:1',
      'recommended:2',
      'recommended:2',
    ]);
  });

  testWidgets(
    'favorites login empty state fits narrow viewport at double text size',
    (tester) async {
      tester.view.physicalSize = const Size(400, 460);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _FeedRepository();
      var loginCalls = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [feedRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: const TextScaler.linear(2)),
              child: child ?? const SizedBox(),
            ),
            home: Scaffold(
              body: FeedScreen(
                channel: HomeChannel.favorites,
                onLogin: () => loginCalls++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('登录账号'));
      await tester.tap(find.text('登录账号'));
      expect(loginCalls, 1);
      expect(repository.calls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('switching channels restores their scroll position', (
    tester,
  ) async {
    final repository = _FeedRepository(itemCount: 40);
    final channel = ValueNotifier(HomeChannel.recommended);
    addTearDown(channel.dispose);
    await tester.pumpWidget(_app(repository, channel: channel));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -600));
    await tester.pumpAndSettle();
    final scrollable = find.descendant(
      of: find.byType(CustomScrollView),
      matching: find.byType(Scrollable),
    );
    final previousOffset = tester
        .state<ScrollableState>(scrollable)
        .position
        .pixels;
    expect(previousOffset, greaterThan(200));
    channel.value = HomeChannel.popular;
    await tester.pumpAndSettle();
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
    channel.value = HomeChannel.recommended;
    await tester.pumpAndSettle();
    expect(
      tester.state<ScrollableState>(scrollable).position.pixels,
      closeTo(previousOffset, 1),
    );
    expect(repository.calls, ['recommended:1', 'popular:1']);
  });
}

Widget _app(
  _FeedRepository repository, {
  ValueNotifier<HomeChannel>? channel,
  VoidCallback? onLogin,
}) => ProviderScope(
  overrides: [
    feedRepositoryProvider.overrideWithValue(repository),
    homeRepositoryProvider.overrideWithValue(_HomeRepository()),
  ],
  child: MaterialApp(
    home: Scaffold(
      body: channel == null
          ? const FeedScreen()
          : ValueListenableBuilder(
              valueListenable: channel,
              builder: (context, value, child) =>
                  FeedScreen(channel: value, onLogin: onLogin),
            ),
    ),
  ),
);

final class _HomeRepository implements HomeRepository {
  _HomeRepository({this.folders = false});
  final bool folders;
  final List<String> calls = [];
  @override
  String get accountScope => folders ? 'user:1' : 'guest';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add(
      '${query.channel.name}:${query.section}${query.folderId == null ? '' : ':${query.folderId}'}',
    );
    if (folders) {
      if (query.section == '我的追番' || query.section == '我的追剧') {
        return HomePage([
          HomeEntry(
            id: '12',
            title: query.section == '我的追番' ? '追番内容' : '追剧内容',
            kind: HomeEntryKind.season,
          ),
        ], hasMore: false);
      }
      return HomePage([
        query.folderId == null && query.section != '默认收藏夹'
            ? query.section == '我的收藏与订阅'
                  ? const HomeEntry(
                      id: '42',
                      title: '订阅合集',
                      kind: HomeEntryKind.collection,
                      contentCount: 38,
                      viewCount: 1635000,
                    )
                  : const HomeEntry(
                      id: 'A',
                      title: '收藏夹A',
                      kind: HomeEntryKind.folder,
                    )
            : const HomeEntry(
                id: 'BV1234567890',
                title: '夹内视频',
                kind: HomeEntryKind.video,
                bvid: 'BV1234567890',
              ),
      ], hasMore: false);
    }
    return HomePage([
      HomeEntry(
        id: query.section,
        title: '${query.channel.label}${query.section}',
        kind: HomeEntryKind.season,
      ),
    ], hasMore: false);
  }
}

final class _FeedRepository implements FeedRepository, RankingFeedRepository {
  _FeedRepository({
    this.failFirst = false,
    this.paginated = false,
    this.itemCount = 1,
  });
  final bool failFirst;
  final bool paginated;
  final int itemCount;
  final List<String> calls = [];
  bool _pageFailed = false;
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [
    VideoCategory(id: '1', name: '动画'),
    VideoCategory(id: '3', name: '音乐'),
  ];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls.add('${categoryId ?? 'recommended'}:$page');
    if (failFirst && calls.length == 1) {
      throw const AppFailure(AppFailureKind.network, '网络暂时不可用');
    }
    if (paginated && page == 2 && !_pageFailed) {
      _pageFailed = true;
      throw const AppFailure(AppFailureKind.network, '下一页加载失败');
    }
    return _page(
      categoryId == null
          ? page == 1
                ? '推荐视频'
                : '第二页视频'
          : '分区$categoryId视频',
      hasMore: paginated && page == 1,
      page: page,
    );
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async {
    calls.add('popular:$page');
    return _page('热门视频', page: page);
  }

  @override
  Future<PageResult<VideoSummary>> loadRanking({
    required String categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls.add('ranking:$categoryId');
    return _page('排行$categoryId视频');
  }

  PageResult<VideoSummary> _page(
    String title, {
    bool hasMore = false,
    int page = 1,
  }) => PageResult(
    items: [
      for (var index = 0; index < itemCount; index++)
        VideoSummary(
          id: VideoId(
            'BV${(title.codeUnits.fold<int>(0, (sum, unit) => sum + unit) * 10000 + page * 1000 + index).toString().padLeft(10, '0')}',
          ),
          title: title,
          coverUrl: '',
          author: '测试 UP',
          duration: const Duration(minutes: 3),
          recommendationReason: '已关注',
        ),
    ],
    hasMore: hasMore,
  );
}
