import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final channel in [
    HomeChannel.recommended,
    HomeChannel.popular,
    HomeChannel.categories,
    HomeChannel.ranking,
  ]) {
    testWidgets('${channel.name} mounts only viewport rows from 500 videos', (
      tester,
    ) async {
      _viewport(tester);
      final repository = _Feed();
      await tester.pumpWidget(_app(repository, channel));
      await tester.pumpAndSettle();
      expect(_items(tester).length, 500);
      expect(find.byType(VideoCard).evaluate().length, inInclusiveRange(2, 20));
      expect(find.text('视频 0'), findsOneWidget);
      _position(tester).jumpTo(4000);
      await tester.pumpAndSettle();
      expect(find.text('视频 0'), findsNothing);
      expect(find.byType(VideoCard).evaluate().length, inInclusiveRange(2, 20));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'top actions and pagination flags preserve existing card widgets',
    (tester) async {
      _viewport(tester);
      final repository = _Feed();
      await tester.pumpWidget(_app(repository, HomeChannel.recommended));
      await tester.pumpAndSettle();
      final first = tester.widget<VideoCard>(find.byType(VideoCard).first);
      _position(tester).jumpTo(12);
      await tester.pumpAndSettle();
      expect(find.byTooltip('回到顶部'), findsOneWidget);
      expect(tester.widget(find.byKey(first.key!)), same(first));
      var rebuilt = 0;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget is VideoCard) rebuilt++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      _position(tester).jumpTo(24);
      await tester.pumpAndSettle();
      expect(
        rebuilt,
        0,
        reason: 'Scroll offset must not replace the row delegate',
      );
      final container = _container(tester);
      final load = container.read(feedControllerProvider.notifier).loadMore();
      await tester.pump();
      expect(rebuilt, 0, reason: 'Loading state belongs to the footer');
      expect(tester.widget(find.byKey(first.key!)), same(first));
      expect(_position(tester).pixels, 24);
      repository.next.completeError(
        const AppFailure(AppFailureKind.network, '分页失败'),
      );
      await load;
      await tester.pumpAndSettle();
      expect(rebuilt, 0, reason: 'Page error belongs to the footer');
      expect(tester.widget(find.byKey(first.key!)), same(first));
      expect(_position(tester).pixels, 24);
      expect(
        container.read(feedControllerProvider).pageError,
        isA<AppFailure>(),
      );
      debugOnRebuildDirtyWidget = null;
      final retry = container.read(feedControllerProvider.notifier).loadMore();
      await tester.pump();
      repository.retry.complete(
        PageResult(items: [_video(500)], hasMore: false),
      );
      await retry;
      await tester.pumpAndSettle();
      expect(_items(tester).length, 501);
      expect(find.byType(VideoCard).evaluate().length, lessThan(20));
      expect(_position(tester).pixels, 24);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('refresh clears the previous card data and viewport offset', (
    tester,
  ) async {
    _viewport(tester);
    final repository = _Feed();
    await tester.pumpWidget(_app(repository, HomeChannel.recommended));
    await tester.pumpAndSettle();
    _position(tester).jumpTo(4000);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('刷新视频'));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, 0);
    expect(repository.firstCalls, 2);
    expect(find.text('视频 0'), findsOneWidget);
    expect(find.byType(VideoCard).evaluate().length, lessThan(20));
    expect(tester.takeException(), isNull);
  });
}

void _viewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(430, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _app(_Feed repository, HomeChannel channel) => ProviderScope(
  overrides: [feedRepositoryProvider.overrideWithValue(repository)],
  child: MaterialApp(
    home: Scaffold(body: FeedScreen(channel: channel)),
  ),
);

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(FeedScreen)));

List<VideoSummary> _items(WidgetTester tester) =>
    _container(tester).read(feedControllerProvider).items.requireValue;

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

VideoSummary _video(int index) => VideoSummary(
  id: VideoId('BV1abc${index.toString().padLeft(6, '0')}'),
  title: '视频 $index',
  coverUrl: '',
  author: 'UP $index',
  playCount: 32000,
  danmakuCount: 1000,
  duration: const Duration(minutes: 3),
);

final class _Feed implements FeedRepository, RankingFeedRepository {
  final next = Completer<PageResult<VideoSummary>>();
  final retry = Completer<PageResult<VideoSummary>>();
  int firstCalls = 0;
  int pageCalls = 0;

  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async {
    if (page == 1) {
      firstCalls++;
      return PageResult(items: List.generate(500, _video), hasMore: true);
    }
    return pageCalls++ == 0 ? next.future : retry.future;
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [VideoCategory(id: '1', name: '动画')];

  @override
  Future<List<VideoCategory>> loadRankingCategories({
    required RequestCancellation cancellation,
  }) => loadCategories(cancellation: cancellation);

  @override
  Future<PageResult<VideoSummary>> loadRanking({
    required String categoryId,
    required RequestCancellation cancellation,
  }) async => PageResult(items: List.generate(500, _video), hasMore: false);
}
