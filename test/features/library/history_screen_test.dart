import 'package:bilisail/domain/video.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/library/application/library_controller.dart';
import 'package:bilisail/features/library/domain/library_repository.dart';
import 'package:bilisail/features/library/presentation/history_screen.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final pgc in [false, true]) {
    testWidgets('history preserves each ${pgc ? 'episode' : 'part'} identity', (
      tester,
    ) async {
      const video = VideoSummary(
        id: VideoId('BV1234567890'),
        title: '同一视频的两条历史',
        coverUrl: '',
        author: '作者',
        duration: Duration(seconds: 100),
        playCount: 12345,
        danmakuCount: 0,
      );
      final entries = [
        for (var index = 1; index <= 2; index++)
          WatchHistoryEntry(
            video: video,
            part: VideoPart(
              cid: '$index',
              page: index,
              title: '第 $index 集',
              duration: const Duration(seconds: 100),
            ),
            episodeId: pgc ? '${100 + index}' : null,
            position: Duration(seconds: index * 20),
            watchedAt: DateTime(2026, 10, 5),
          ),
      ];
      final router = GoRouter(
        initialLocation: '/history',
        routes: [
          GoRoute(path: '/history', builder: (_, _) => const HistoryScreen()),
          for (final path in ['/video/:id', '/pgc/episode/:id'])
            GoRoute(path: path, builder: (_, _) => const Text('播放目的地')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            libraryRepositoryProvider.overrideWithValue(
              _HistoryRepository(entries),
            ),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final cards = find.byType(VideoCard);
      expect(tester.widget<VideoCard>(cards.at(0)).progress, 0.2);
      expect(tester.widget<VideoCard>(cards.at(1)).progress, 0.4);
      expect(find.text('当前账号的云端观看记录'), findsOneWidget);
      expect(
        tester.widget<VideoCard>(cards.at(0)).publishTooltip,
        '观看于 2026-10-05 00:00',
      );
      expect(
        tester.widget<VideoCard>(cards.at(0)).publishText,
        DateTime.now().year == 2026 ? '10-05' : '2026-10-05',
      );
      expect(find.text('1.2万'), findsNWidgets(2));
      expect(find.text('0'), findsNWidgets(2));
      await tester.tap(cards.at(1));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri, entries[1].location);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

final class _HistoryRepository implements LibraryRepository {
  _HistoryRepository(this.entries);
  final List<WatchHistoryEntry> entries;
  @override
  String get accountScope => 'user:1';
  @override
  Future<WatchHistoryPage> loadHistory({
    String? cursor,
    required RequestCancellation cancellation,
  }) async => WatchHistoryPage(entries, hasMore: false);
}
