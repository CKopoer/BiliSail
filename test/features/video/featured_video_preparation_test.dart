import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/featured_feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/video/application/featured_video_preparation.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/featured_video_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/input_test_app.dart';

class _Videos implements VideoRepository, FeaturedFeedRepository {
  final items = List.generate(
    5,
    (i) => VideoSummary(
      id: VideoId('BV17x411w7K$i'),
      title: '视频 $i',
      author: '作者',
      coverUrl: '',
      duration: const Duration(minutes: 1),
      previewCid: i == 1 ? null : '${i + 1}',
    ),
  );
  final reads = <VideoId>[];
  @override
  Future<PageResult<VideoSummary>> loadFeatured({
    required FeaturedSource source,
    required int batch,
    required bool refresh,
    FeaturedSeed? seed,
    required RequestCancellation cancellation,
  }) async => PageResult(items: items, hasMore: false);
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    reads.add(id);
    final video = items.firstWhere((item) => item.id == id);
    return VideoDetail(
      summary: video,
      description: '',
      parts: [
        VideoPart(
          cid: video.previewCid ?? '2',
          page: 1,
          title: video.title,
          duration: video.duration,
        ),
      ],
    );
  }
}

void main() {
  testWidgets(
    'next card resolves before a swipe, only the settled card mounts a player and leaving drops leases',
    (tester) async {
      final videos = _Videos();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      final opened = <VideoId>{};
      final leases = <(VideoId, String, bool)>{};
      final preparations = <VideoId>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoRepositoryProvider.overrideWithValue(videos),
            featuredPlayInfoPreparationProvider.overrideWithValue((
              video,
              cid, {
              required neighbor,
            }) {
              preparations.add(video);
              leases.add((video, cid, neighbor));
              return () => leases.remove((video, cid, neighbor));
            }),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: active,
                builder: (context, on, child) =>
                    WorkspaceActivity(active: on, child: child!),
                child: FeaturedVideoScreen(
                  createController: () => FeaturedFeedController(
                    videos,
                    FeaturedSource.desktop,
                    RecommendationFilter(
                      const RecommendationSettings.defaults(),
                    ),
                  ),
                  splitWidth: 1000,
                  onLogin: () {},
                  onOpenUser: (_) {},
                  playerBuilder: (_, detail, part) {
                    opened.add(detail.summary.id);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ids = videos.items.map((e) => e.id).toList();
      expect(videos.reads, ids.take(2));
      expect(leases, {(ids[0], '1', false), (ids[1], '2', true)});
      expect(opened, {ids[0]});
      await tester.fling(find.byType(PageView), const Offset(0, -350), 900);
      await tester.pumpAndSettle();
      expect(videos.reads, ids.take(3));
      expect(preparations.toSet(), ids.take(3).toSet());
      expect(opened, {ids[0], ids[1]});
      expect(leases, {
        (ids[0], '1', true),
        (ids[1], '2', false),
        (ids[2], '3', true),
      });
      await tester.fling(find.byType(PageView), const Offset(0, 350), 900);
      await tester.pumpAndSettle();
      expect(videos.reads, ids.take(3));
      expect(leases, {(ids[0], '1', false), (ids[1], '2', true)});
      active.value = false;
      await tester.pumpAndSettle();
      expect(leases, isEmpty);
    },
  );
}
