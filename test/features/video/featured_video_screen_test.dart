import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/featured_feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/featured_video_overlay.dart';
import 'package:bilisail/features/video/presentation/featured_video_screen.dart';
import 'package:bilisail/shared/ui/app_network_image.dart';
import 'package:bilisail/shared/ui/featured_paging_scope.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/input_test_app.dart';

class _Videos implements FeaturedFeedRepository, VideoRepository {
  _Videos({bool includeCovers = false})
    : items = List.generate(
        5,
        (i) => VideoSummary(
          id: VideoId('BV123456789$i'),
          title: '片段 $i',
          coverUrl: includeCovers ? 'https://i0.hdslb.com/fixture-$i.jpg' : '',
          author: '作者',
          duration: const Duration(minutes: 1),
          previewCid: '$i',
        ),
      );
  final List<VideoSummary> items;
  final details = <VideoId>[];
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
    details.add(id);
    final item = items.singleWhere((v) => v.id == id);
    return VideoDetail(
      summary: item,
      description: '简介',
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

void main() {
  testWidgets(
    'only a settled page opens, panels adapt and the selected page survives hiding',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1200, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final videos = _Videos(includeCovers: true);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [videoRepositoryProvider.overrideWithValue(videos)],
          child: InputTestApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: visible,
                builder: (context, active, child) =>
                    WorkspaceActivity(active: active, child: child!),
                child: FeaturedVideoScreen(
                  createController: () => FeaturedFeedController(
                    videos,
                    FeaturedSource.desktop,
                    RecommendationFilter(
                      const RecommendationSettings.defaults(),
                    ),
                  ),
                  playerBuilder: (context, detail, part) {
                    final featured = FeaturedPagingScope.maybeOf(context)!;
                    return ColoredBox(
                      key: ValueKey('playing-${part.cid}'),
                      color: Colors.black,
                      child: Align(
                        alignment: Alignment.topRight,
                        child: IconButton(
                          key: const ValueKey('toggle-test-overlays'),
                          onPressed: featured.onToggleVideoOverlays,
                          icon: Icon(
                            featured.showVideoOverlays
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                          ),
                        ),
                      ),
                    );
                  },
                  onLogin: () {},
                  onOpenUser: (_) {},
                  splitWidth: 1000,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(videos.details, [videos.items[0].id]);
      final pager = find.byType(PageView);
      final drag = await tester.startGesture(tester.getCenter(pager));
      await drag.moveBy(const Offset(0, -120));
      await tester.pump();
      expect(videos.details, [videos.items[0].id]);
      expect(find.byType(AppNetworkImage), findsNothing);
      await drag.moveBy(const Offset(0, -420));
      await drag.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
      final reverse = await tester.startGesture(tester.getCenter(pager));
      await reverse.moveBy(const Offset(0, 120));
      await tester.pump();
      expect(find.byType(AppNetworkImage), findsNothing);
      await reverse.cancel();
      await tester.pumpAndSettle();
      expect(videos.details, [videos.items[0].id, videos.items[1].id]);
      await tester.tap(find.text('片段 1'));
      await tester.pumpAndSettle();
      final wide = tester.getRect(find.text('视频信息'));
      expect(wide.left, greaterThan(800));
      tester.view.physicalSize = const Size(390, 800);
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.text('视频信息')).dy, greaterThan(260));
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      visible.value = false;
      await tester.pump();
      visible.value = true;
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
      expect(videos.details, hasLength(2));

      final overlay = find.byType(FeaturedVideoOverlay);
      final toggle = find.byKey(const ValueKey('toggle-test-overlays'));
      expect(overlay, findsOneWidget);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(overlay, findsNothing);
      await tester.drag(pager, const Offset(0, -530));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
      expect(overlay, findsNothing);
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(overlay, findsOneWidget);
      expect(find.text('片段 2'), findsOneWidget);
    },
  );
}
