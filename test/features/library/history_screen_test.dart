import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/features/library/application/library_controller.dart';
import 'package:bili_lite/features/library/domain/library_repository.dart';
import 'package:bili_lite/features/library/presentation/history_screen.dart';
import 'package:bili_lite/shared/ui/video_card.dart';
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
          overrides: [historyProvider.overrideWith((_) async => entries)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      final cards = find.byType(VideoCard);
      expect(tester.widget<VideoCard>(cards.at(0)).progress, 0.2);
      expect(tester.widget<VideoCard>(cards.at(1)).progress, 0.4);
      await tester.tap(cards.at(1));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri, entries[1].location);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
