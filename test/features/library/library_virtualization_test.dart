import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/library/presentation/history_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'large history lazily mounts cards and preserves offscreen part navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1000, 650);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      final router = GoRouter(
        initialLocation: '/history',
        routes: [
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          GoRoute(path: '/video/:id', builder: (_, _) => const Text('播放')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [libraryRepositoryProvider.overrideWithValue(repository)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final cards = find.byType(VideoCard);
      expect(cards.evaluate().length, inExclusiveRange(0, 25));
      expect(tester.widget<VideoCard>(cards.first).progress, 0);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(2500);
      await tester.pumpAndSettle();
      expect(cards.evaluate().length, inExclusiveRange(0, 25));
      final visible =
          cards
                  .evaluate()
                  .where((element) {
                    final rect = tester.getRect(find.byWidget(element.widget));
                    return rect.top >= 0 && rect.bottom <= 650;
                  })
                  .first
                  .widget
              as VideoCard;
      final index = repository.entries.indexWhere(
        (entry) => entry.position.inSeconds / 1000 == visible.progress,
      );
      expect(index, greaterThan(0));
      expect(visible.publishTooltip, contains('观看于'));
      await tester.tap(find.byWidget(visible));
      await tester.pumpAndSettle();
      expect(
        router.routeInformationProvider.value.uri,
        repository.entries[index].location,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _Repository implements LibraryRepository {
  final entries = [
    for (var index = 0; index < 400; index++)
      WatchHistoryEntry(
        video: const VideoSummary(
          id: VideoId('BV1234567890'),
          title: '多分P历史',
          coverUrl: '',
          author: '作者',
          duration: Duration(seconds: 1000),
        ),
        part: VideoPart(
          cid: '$index',
          page: index + 1,
          title: '分P$index',
          duration: const Duration(seconds: 1000),
        ),
        position: Duration(seconds: index),
        watchedAt: DateTime(2026, 10, 7, 0, index),
      ),
  ];
  @override
  String get accountScope => 'user:1';
  @override
  Future<WatchHistoryPage> loadHistory({
    String? cursor,
    required RequestCancellation cancellation,
  }) async => WatchHistoryPage(entries, hasMore: false);
}
