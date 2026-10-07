import 'dart:async';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final channel in [HomeChannel.recommended, HomeChannel.popular]) {
    testWidgets('${channel.name} fills the first viewport without a scroll', (
      tester,
    ) async {
      final repository = _ImmediateFeedRepository(itemCount: 1);
      final selected = ValueNotifier(channel);
      addTearDown(selected.dispose);
      await tester.pumpWidget(_app(repository, channel: selected));
      await tester.pumpAndSettle();
      expect(repository.calls, ['${channel.name}:1', '${channel.name}:2']);
      expect(_position(tester).pixels, 0);
      expect(find.byTooltip('刷新视频'), findsOneWidget);
      expect(find.byTooltip('回到顶部'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('recommended fills an empty first page when more is available', (
    tester,
  ) async {
    final repository = _ImmediateFeedRepository(emptyFirst: true);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(repository.calls, ['recommended:1', 'recommended:2']);
    expect(find.text('推荐2-0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('recommended checks pagination after a window grows', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ImmediateFeedRepository(itemCount: 30);
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    expect(repository.calls, ['recommended:1']);
    tester.view.physicalSize = const Size(1920, 1600);
    await tester.pumpAndSettle();
    expect(repository.calls, ['recommended:1', 'recommended:2']);
    expect(_position(tester).pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'wheel prefetches once near the bottom and stops at the last page',
    (tester) async {
      final repository = _FeedRepository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();

      await _wheel(tester, 200);
      expect(repository.calls, ['recommended:1']);
      await _wheelNearBottom(tester);
      expect(_position(tester).extentAfter, greaterThan(0));
      expect(repository.calls, ['recommended:1', 'recommended:2']);

      for (var i = 0; i < 5; i++) {
        await _wheel(tester, 20);
      }
      expect(repository.calls, ['recommended:1', 'recommended:2']);
      final previousOffset = _position(tester).pixels;
      repository.nextPage.complete(_page(2));
      await tester.pumpAndSettle();
      expect(_titles(tester), containsAll(['推荐1-0', '推荐2-0']));
      expect(_position(tester).pixels, closeTo(previousOffset, 1));

      await _wheelNearBottom(tester);
      await tester.pumpAndSettle();
      expect(_titles(tester), contains('推荐3-0'));
      await _wheel(tester, _position(tester).extentAfter + 100);
      await _wheel(tester, 100);
      expect(repository.calls, [
        'recommended:1',
        'recommended:2',
        'recommended:3',
      ]);
      expect(find.text('加载更多'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('failed automatic page waits for manual retry of the same page', (
    tester,
  ) async {
    final repository = _FeedRepository();
    await tester.pumpWidget(_app(repository));
    await tester.pumpAndSettle();
    await _wheelNearBottom(tester);
    repository.nextPage.completeError(
      const AppFailure(AppFailureKind.network, '下一页加载失败'),
    );
    await tester.pumpAndSettle();

    await _wheel(tester, _position(tester).extentAfter + 100);
    await _wheel(tester, 100);
    await tester.pumpAndSettle();
    expect(_titles(tester), contains('推荐1-0'));
    expect(find.text('下一页加载失败'), findsOneWidget);
    expect(repository.calls, ['recommended:1', 'recommended:2']);
    await tester.ensureVisible(find.text('重试'));
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(_titles(tester), contains('推荐2-0'));
    expect(repository.calls, [
      'recommended:1',
      'recommended:2',
      'recommended:2',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'refresh cancels an automatic page and discards its late result',
    (tester) async {
      final repository = _FeedRepository();
      await tester.pumpWidget(_app(repository));
      await tester.pumpAndSettle();
      await _wheelNearBottom(tester);
      await tester.tap(find.byTooltip('刷新视频'));
      await tester.pumpAndSettle();
      expect(repository.pageCancellation?.isCancelled, isTrue);
      repository.nextPage.complete(_page(2));
      await tester.pumpAndSettle();
      expect(_titles(tester), contains('推荐1-0'));
      expect(_titles(tester), isNot(contains('推荐2-0')));
      expect(repository.calls, [
        'recommended:1',
        'recommended:2',
        'recommended:1',
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'channel switch cancels automatic pagination without mixing lists',
    (tester) async {
      final repository = _FeedRepository();
      final channel = ValueNotifier(HomeChannel.recommended);
      addTearDown(channel.dispose);
      await tester.pumpWidget(_app(repository, channel: channel));
      await tester.pumpAndSettle();
      await _wheelNearBottom(tester);
      channel.value = HomeChannel.popular;
      await tester.pumpAndSettle();
      expect(repository.pageCancellation?.isCancelled, isTrue);
      repository.nextPage.complete(_page(2));
      await tester.pumpAndSettle();
      await _wheelNearBottom(tester);
      await tester.pumpAndSettle();
      expect(_titles(tester), isNot(contains('推荐2-0')));
      expect(_titles(tester), contains('热门2-0'));
      expect(repository.calls, [
        'recommended:1',
        'recommended:2',
        'popular:1',
        'popular:2',
      ]);

      channel.value = HomeChannel.recommended;
      await tester.pumpAndSettle();
      expect(_titles(tester), containsAll(['推荐1-0', '推荐2-0']));
      expect(repository.calls.last, 'recommended:2');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('inactive workspace does not request an automatic page', (
    tester,
  ) async {
    final repository = _FeedRepository();
    await tester.pumpWidget(_app(repository, active: false));
    await tester.pumpAndSettle();
    await _wheelNearBottom(tester);
    await tester.pumpAndSettle();
    expect(repository.calls, ['recommended:1']);
    expect(tester.takeException(), isNull);
  });
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

// Offscreen rows are deliberately unmounted. Check the loaded data as well as
// the scroll-triggered requests so a hidden stale page cannot escape detection.
List<String> _titles(WidgetTester tester) => [
  for (final item
      in ProviderScope.containerOf(tester.element(find.byType(FeedScreen)))
              .read(feedControllerProvider)
              .items
              .asData
              ?.value ??
          const <VideoSummary>[])
    item.title,
];

Future<void> _wheelNearBottom(WidgetTester tester) =>
    _wheel(tester, _position(tester).extentAfter - 400);

Future<void> _wheel(WidgetTester tester, double delta) async {
  await tester.sendEventToBinding(
    PointerScrollEvent(
      position: tester.getCenter(find.byType(CustomScrollView)),
      scrollDelta: Offset(0, delta),
    ),
  );
  await tester.pump();
}

Widget _app(
  FeedRepository repository, {
  ValueNotifier<HomeChannel>? channel,
  bool active = true,
}) => ProviderScope(
  overrides: [feedRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(
      body: WorkspaceActivity(
        active: active,
        child: channel == null
            ? const FeedScreen()
            : ValueListenableBuilder(
                valueListenable: channel,
                builder: (context, value, child) => FeedScreen(channel: value),
              ),
      ),
    ),
  ),
);

PageResult<VideoSummary> _page(
  int page, {
  String prefix = '推荐',
  int itemCount = 30,
  bool? hasMore,
}) => PageResult(
  items: [
    for (var index = 0; index < itemCount; index++)
      VideoSummary(
        id: VideoId('BV${(page * 30 + index).toString().padLeft(10, '0')}'),
        title: '$prefix$page-$index',
        coverUrl: '',
        author: '测试 UP',
        duration: const Duration(minutes: 3),
      ),
  ],
  hasMore: hasMore ?? page < 3,
);

final class _ImmediateFeedRepository implements FeedRepository {
  _ImmediateFeedRepository({this.itemCount = 1, this.emptyFirst = false});
  final int itemCount;
  final bool emptyFirst;
  final calls = <String>[];

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls.add('recommended:$page');
    return _page(
      page,
      itemCount: emptyFirst && page == 1 ? 0 : itemCount,
      hasMore: page < 2,
    );
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async {
    calls.add('popular:$page');
    return _page(page, prefix: '热门', itemCount: itemCount, hasMore: page < 2);
  }
}

final class _FeedRepository implements FeedRepository {
  final calls = <String>[];
  final nextPage = Completer<PageResult<VideoSummary>>();
  RequestCancellation? pageCancellation;
  bool _requestedNextPage = false;

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    calls.add('recommended:$page');
    if (page == 2 && !_requestedNextPage) {
      _requestedNextPage = true;
      pageCancellation = cancellation;
      return nextPage.future;
    }
    return _page(page);
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async {
    calls.add('popular:$page');
    return _page(page, prefix: '热门');
  }
}
