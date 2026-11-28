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
import 'package:flutter/gestures.dart' show PointerDeviceKind;
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

Future<PageController> _pumpFeaturedPager(
  WidgetTester tester, {
  double pixelRatio = 1,
  double height = 800,
}) async {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = Size(390, height) * pixelRatio;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final videos = _Videos();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [videoRepositoryProvider.overrideWithValue(videos)],
      child: InputTestApp(
        home: Scaffold(
          body: FeaturedVideoScreen(
            createController: () => FeaturedFeedController(
              videos,
              FeaturedSource.desktop,
              RecommendationFilter(const RecommendationSettings.defaults()),
            ),
            playerBuilder: (_, _, part) =>
                SizedBox.expand(key: ValueKey('playing-${part.cid}')),
            onLogin: () {},
            onOpenUser: (_) {},
            splitWidth: 1000,
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return tester.widget<PageView>(find.byType(PageView)).controller!;
}

Future<void> _slowDrag(
  WidgetTester tester,
  PageController controller,
  double distance, {
  double retract = 0,
  bool cancel = false,
}) async {
  final start = controller.position.pixels;
  final drag = await tester.startGesture(
    tester.getCenter(find.byType(PageView)),
  );
  // Account for touch slop before measuring page travel. Samples 50 ms apart
  // produce a stationary velocity estimate.
  const interval = Duration(milliseconds: 50);
  await tester.pump(interval);
  await drag.moveBy(Offset(0, 20.0 * distance.sign), timeStamp: interval);
  await tester.pump();
  final afterSlop = controller.position.pixels;
  final remaining = distance + afterSlop - start;
  for (var sample = 1; sample <= 4; sample++) {
    await tester.pump(interval);
    await drag.moveBy(
      Offset(0, remaining / 4),
      timeStamp: interval * (sample + 1),
    );
    await tester.pump();
    expect(
      controller.position.pixels,
      closeTo(afterSlop - remaining * sample / 4, .01),
    );
  }
  var releaseSample = 6;
  if (retract != 0) {
    await tester.pump(interval);
    await drag.moveBy(
      Offset(0, -retract * distance.sign),
      timeStamp: interval * releaseSample++,
    );
    await tester.pump();
    expect(
      controller.position.pixels,
      closeTo(start - distance + retract * distance.sign, .01),
    );
  }
  await tester.pump(interval);
  final timeStamp = interval * releaseSample;
  if (cancel) {
    await drag.cancel(timeStamp: timeStamp);
  } else {
    await drag.up(timeStamp: timeStamp);
  }
}

Future<void> _pumpTouchLanding(WidgetTester tester) async {
  await tester.pump();
  for (var frame = 0; frame < 13; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await tester.pump(const Duration(milliseconds: 12));
  await tester.pump();
}

void main() {
  for (final direction in <int>[1, -1]) {
    testWidgets(
      '120 px slow drag lands on the ${direction == 1 ? 'next' : 'previous'} clip within 220 ms',
      (tester) async {
        final controller = await _pumpFeaturedPager(tester, pixelRatio: 3);
        controller.jumpToPage(1);
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);

        await _slowDrag(tester, controller, -120.0 * direction);
        expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
        await _pumpTouchLanding(tester);

        final target = 1 + direction;
        expect(controller.position.pixels, 800.0 * target);
        expect(find.byKey(ValueKey('playing-$target')), findsOneWidget);
      },
      variant: const TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }

  testWidgets('the exact slow drag threshold advances from a later page', (
    tester,
  ) async {
    final controller = await _pumpFeaturedPager(tester, height: 600);
    controller.jumpToPage(1);
    await tester.pumpAndSettle();
    await _slowDrag(tester, controller, -96);
    await _pumpTouchLanding(tester);
    expect(controller.page, 2);
    expect(find.byKey(const ValueKey('playing-2')), findsOneWidget);
  });

  testWidgets('a 35 px slow drag returns to the current clip', (tester) async {
    final controller = await _pumpFeaturedPager(tester);
    await _slowDrag(tester, controller, -35);
    await _pumpTouchLanding(tester);

    expect(controller.position.pixels, 0);
    expect(find.byKey(const ValueKey('playing-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('playing-1')), findsNothing);
  });

  testWidgets('dragging back before release keeps the current clip', (
    tester,
  ) async {
    final controller = await _pumpFeaturedPager(tester);
    await _slowDrag(tester, controller, -120, retract: 100);
    await _pumpTouchLanding(tester);

    expect(controller.position.pixels, 0);
    expect(find.byKey(const ValueKey('playing-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('playing-1')), findsNothing);
  });

  testWidgets('a short fast fling still advances one clip', (tester) async {
    final controller = await _pumpFeaturedPager(tester);
    await tester.fling(find.byType(PageView), const Offset(0, -65), 1600);
    await _pumpTouchLanding(tester);

    expect(controller.position.pixels, 800);
    expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
  });

  testWidgets('a fast release near the next clip never overshoots it', (
    tester,
  ) async {
    final controller = await _pumpFeaturedPager(tester);
    final drag = await tester.startGesture(
      tester.getCenter(find.byType(PageView)),
    );
    await drag.moveBy(
      const Offset(0, -20),
      timeStamp: const Duration(milliseconds: 20),
    );
    // End close to the next page with six samples at 4,000 pixels/second.
    await drag.moveBy(
      Offset(0, controller.position.pixels - 772),
      timeStamp: const Duration(milliseconds: 100),
    );
    for (var sample = 1; sample <= 6; sample++) {
      await drag.moveBy(
        const Offset(0, -4),
        timeStamp: Duration(milliseconds: 100 + sample),
      );
    }
    expect(controller.position.pixels, 796);
    await drag.up(timeStamp: const Duration(milliseconds: 107));

    await tester.pump();
    for (var frame = 0; frame < 55; frame++) {
      await tester.pump(const Duration(milliseconds: 4));
      expect(controller.position.pixels, inInclusiveRange(796, 800));
    }
    await tester.pump();
    expect(controller.position.pixels, 800);
    expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
  });

  testWidgets(
    'a pointer cancellation does not switch clips past the threshold',
    (tester) async {
      final controller = await _pumpFeaturedPager(tester);
      await _slowDrag(tester, controller, -200, cancel: true);
      await _pumpTouchLanding(tester);

      expect(controller.position.pixels, 0);
      expect(find.byKey(const ValueKey('playing-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('playing-1')), findsNothing);
    },
  );

  testWidgets('macOS trackpad pan keeps the PageView landing threshold', (
    tester,
  ) async {
    final controller = await _pumpFeaturedPager(tester);
    final origin = tester.getCenter(find.byType(PageView));
    Future<void> pan(double distance) async {
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.trackpad,
      );
      await gesture.panZoomStart(origin);
      const interval = Duration(milliseconds: 50);
      for (var sample = 1; sample <= 4; sample++) {
        await tester.pump(interval);
        await gesture.panZoomUpdate(
          origin,
          pan: Offset(0, -distance * sample / 4),
          timeStamp: interval * sample,
        );
      }
      expect(controller.position.pixels, greaterThan(0));
      await tester.pump(interval);
      await gesture.panZoomEnd(timeStamp: interval * 5);
      await tester.pumpAndSettle();
    }

    await pan(120);
    expect(controller.position.pixels, 0);
    expect(find.byKey(const ValueKey('playing-0')), findsOneWidget);
    await pan(560);
    expect(controller.position.pixels, 800);
    expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
  }, variant: const TargetPlatformVariant({TargetPlatform.macOS}));

  testWidgets('Reduce Motion lands a touch swipe without a timed animation', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(reduceMotion: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final controller = await _pumpFeaturedPager(tester);
    await _slowDrag(tester, controller, -120);

    await tester.pump();
    expect(controller.position.pixels, 800);
    await tester.pump();
    expect(find.byKey(const ValueKey('playing-1')), findsOneWidget);
  });

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
                    if (part.cid == '0') {
                      featured.controlsGeometry?.reportHeight(80);
                    }
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
      final overlay = find.byType(FeaturedVideoOverlay);
      expect(
        tester
            .widget<FeaturedVideoOverlay>(overlay)
            .controlsGeometry
            .height
            .value,
        80,
      );
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
      expect(
        tester
            .widget<FeaturedVideoOverlay>(overlay)
            .controlsGeometry
            .height
            .value,
        0,
      );
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
