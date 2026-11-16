import 'dart:async';

import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_screen.dart';
import 'package:bilisail/shared/ui/paged_scroll_viewport.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'pagination updates only the current video channel after visiting all tabs',
    (tester) async {
      final repository = _Feed();
      final channel = ValueNotifier(HomeChannel.recommended);
      addTearDown(channel.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            feedRepositoryProvider.overrideWithValue(repository),
            homeRepositoryProvider.overrideWithValue(_Home()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: channel,
                builder: (_, selected, _) => FeedScreen(
                  channel: selected,
                  onChannelChanged: (value) => channel.value = value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final entry in HomeChannel.primaryValues.skip(1)) {
        channel.value = entry;
        await tester.pumpAndSettle();
      }
      channel.value = HomeChannel.recommended;
      await tester.pumpAndSettle();
      final allPages = find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_HomeChannelPage',
        skipOffstage: false,
      );
      expect(allPages, findsNWidgets(HomeChannel.primaryValues.length - 1));
      expect(
        find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == 'PopularFeed',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(FeedScreen)),
      );
      final pageCounts = <String, int>{};
      final viewportCounts = <String, int>{};
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        if (element.widget.runtimeType.toString() == '_HomeChannelPage') {
          final name = element.widget.toString();
          pageCounts.update(name, (n) => n + 1, ifAbsent: () => 1);
        }
        if (element.widget is PagedScrollViewport) {
          final name = element.widget.key.toString();
          viewportCounts.update(name, (n) => n + 1, ifAbsent: () => 1);
        }
      };
      addTearDown(() => debugOnRebuildDirtyWidget = null);
      final pending = container
          .read(feedControllerProvider.notifier)
          .loadMore();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final loading = {
        'pages': Map.of(pageCounts),
        'viewports': Map.of(viewportCounts),
      };
      pageCounts.clear();
      viewportCounts.clear();
      repository.next.complete(
        PageResult(items: [_video(500)], hasMore: false),
      );
      await pending;
      await tester.pumpAndSettle();
      final complete = {'pages': pageCounts, 'viewports': viewportCounts};
      debugOnRebuildDirtyWidget = null;
      for (final phase in [loading, complete]) {
        expect(
          phase['pages']!.values.fold<int>(0, (sum, count) => sum + count),
          1,
        );
        expect(phase['viewports']!.keys, [
          '[<(video-feed, HomeChannel.recommended)>]',
        ]);
      }
      expect(tester.takeException(), isNull);
    },
  );
}

VideoSummary _video(int i) => VideoSummary(
  id: VideoId('BV1abc${i.toString().padLeft(6, '0')}'),
  title: 'Video $i',
  author: 'author',
  coverUrl: '',
  duration: const Duration(minutes: 1),
);

final class _Feed implements FeedRepository, RankingFeedRepository {
  final next = Completer<PageResult<VideoSummary>>();
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => page == 1
      ? PageResult(items: List.generate(500, _video), hasMore: true)
      : next.future;
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => loadFeed(page: page, categoryId: null, cancellation: cancellation);
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => const [VideoCategory(id: '1', name: 'Animation')];
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

final class _Home implements HomeRepository {
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
