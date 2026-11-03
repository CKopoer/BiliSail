import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_danmaku/src/danmaku_text_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('animation frames skip unchanged VOD and live admission work', () {
    var now = Duration.zero;
    final vod = DanmakuController(monotonicNow: () => now);
    final live = LiveDanmakuController(monotonicNow: () => now);
    addTearDown(vod.dispose);
    addTearDown(live.dispose);
    vod.setViewport(width: 800, height: 450);
    live.setViewport(width: 800, height: 450);
    live.configure(area: 1, speed: 1, maxPerSecond: 0);
    vod.replaceEvents([
      for (final mode in DanmakuMode.values)
        DanmakuEvent(
          id: mode.name,
          at: Duration.zero,
          text: mode.name,
          mode: mode,
        ),
    ]);
    live.add([
      for (final mode in DanmakuMode.values)
        LiveDanmakuEvent(id: mode.name, text: mode.name, mode: mode),
    ]);
    vod.sync(
      confirmedPosition: now,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    final firstVod = vod.frame();
    final firstLive = live.frame();
    for (var frame = 1; frame <= 240; frame++) {
      now = Duration(milliseconds: frame * 2);
      final vf = vod.frame();
      final lf = live.frame();
      expect(vf.map((p) => p.event.id), DanmakuMode.values.map((m) => m.name));
      expect(lf.map((p) => p.event.id), DanmakuMode.values.map((m) => m.name));
      expect(vf.first.x, lessThan(firstVod.first.x));
      expect(lf.first.x, lessThan(firstLive.first.x));
      expect(vf[1].x, firstVod[1].x);
      expect(lf[1].x, firstLive[1].x);
      expect(vf.map((p) => p.y), firstVod.map((p) => p.y));
      expect(lf.map((p) => p.y), firstLive.map((p) => p.y));
    }
    // Previously both indexes and protection sets were rebuilt on all 241
    // calls. Frame count and position updates still remain unchanged.
    expect(vod.laneIndexBuildCount, 1);
    expect(live.laneIndexBuildCount, 1);
    expect(vod.rasterProtectionUpdateCount, 1);
    expect(live.rasterProtectionUpdateCount, 1);
    expect(vod.textLayoutBuildCount, 3);
    expect(live.textLayoutBuildCount, 3);

    // Expiration must still refresh protection on an animation-only frame.
    for (var sample = 1; sample <= 90; sample++) {
      now += const Duration(milliseconds: 100);
      vod.sync(
        confirmedPosition: now,
        playing: true,
        buffering: false,
        seeking: false,
        rate: 1,
      );
      vod.frame();
      live.frame();
    }
    expect(vod.visibleCount, 0);
    expect(live.visibleCount, 0);
    expect(vod.laneIndexBuildCount, 1);
    expect(live.laneIndexBuildCount, 1);
    expect(vod.rasterProtectionUpdateCount, 3);
    expect(live.rasterProtectionUpdateCount, 3);
  });

  test(
    'VOD protection follows filtering, seek, viewport and raster release',
    () {
      final controller = DanmakuController(monotonicNow: () => Duration.zero);
      addTearDown(controller.dispose);
      controller.setViewport(width: 800, height: 450);
      const events = [
        DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
        DanmakuEvent(
          id: 'top',
          at: Duration.zero,
          text: 'top',
          mode: DanmakuMode.top,
        ),
      ];
      controller.replaceEvents(events);
      expect(controller.frame(), hasLength(2));
      expect(controller.rasterProtectionUpdateCount, 1);
      controller.replaceEvents(events);
      controller.setViewport(width: 1000, height: 450);
      expect(controller.frame(), hasLength(2));
      expect(controller.laneIndexBuildCount, 1);
      expect(controller.rasterProtectionUpdateCount, 1);

      controller.releaseRasterCache();
      controller.frame();
      expect(controller.rasterProtectionUpdateCount, 2);
      controller.replaceEvents([events.last]);
      expect(controller.frame().single.event.id, 'top');
      expect(controller.rasterProtectionUpdateCount, 3);
      expect(controller.laneIndexBuildCount, 1);

      controller.seekConfirmed(Duration.zero);
      expect(controller.frame().single.event.id, 'top');
      expect(controller.laneIndexBuildCount, 2);
      expect(controller.rasterProtectionUpdateCount, 4);
      controller.setViewport(width: 1000, height: 1);
      expect(controller.frame(), isEmpty);
      expect(controller.rasterProtectionUpdateCount, 5);
      controller.setViewport(width: 1000, height: 450);
      expect(controller.frame(), isEmpty);
      expect(controller.laneIndexBuildCount, 2);
      expect(controller.rasterProtectionUpdateCount, 5);
    },
  );

  test('live protection follows admissions, viewport clipping and clear', () {
    final controller = LiveDanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.configure(area: 1, speed: 1, maxPerSecond: 0);
    controller.setViewport(width: 800, height: 450);
    controller.add(const [LiveDanmakuEvent(id: 'one', text: 'one')]);
    controller.frame();
    controller.setViewport(width: 1000, height: 450);
    controller.frame();
    expect(controller.laneIndexBuildCount, 1);
    expect(controller.rasterProtectionUpdateCount, 1);
    controller.add(const [LiveDanmakuEvent(id: 'two', text: 'two')]);
    expect(controller.frame(), hasLength(2));
    expect(controller.laneIndexBuildCount, 2);
    expect(controller.rasterProtectionUpdateCount, 2);
    controller.setViewport(width: 1000, height: 1);
    expect(controller.frame(), isEmpty);
    expect(controller.rasterProtectionUpdateCount, 3);
    controller.setViewport(width: 1000, height: 450);
    expect(controller.frame(), isEmpty);
    expect(controller.laneIndexBuildCount, 2);
    expect(controller.rasterProtectionUpdateCount, 3);
    controller.add(const [LiveDanmakuEvent(id: 'three', text: 'three')]);
    expect(controller.frame(), hasLength(1));
    expect(controller.laneIndexBuildCount, 3);
    expect(controller.rasterProtectionUpdateCount, 4);
    controller.clear();
    expect(controller.frame(), isEmpty);
    expect(controller.rasterProtectionUpdateCount, 5);
  });

  test('hidden raster reclamation keeps layouts and scheduling reusable', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 800, height: 450);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'visible', at: Duration.zero, text: 'visible'),
      DanmakuEvent(id: 'future', at: Duration(seconds: 20), text: 'future'),
    ], sorted: true);
    final placement = controller.frame().single;
    void paint() {
      final recorder = ui.PictureRecorder();
      controller.paintText(
        placement.event,
        ui.Canvas(recorder),
        ui.Offset.zero,
      );
      recorder.endRecording().dispose();
    }

    paint();
    final builds = controller.textLayoutBuildCount;
    expect(controller.textRasterBytes, greaterThan(0));
    controller.releaseRasterCache();
    expect(controller.textRasterBytes, 0);
    expect(controller.textLayoutBuildCount, builds);
    expect(controller.textLayoutCount, 1);
    expect(controller.pendingCount, 1);
    expect(controller.frame().single.event.id, placement.event.id);
    paint();
    expect(controller.textRasterBytes, greaterThan(0));
    expect(controller.textLayoutBuildCount, builds);
  });

  for (final isLive in [false, true]) {
    testWidgets(
      '${isLive ? 'live' : 'VOD'} retained overlay updates raster DPR at the same logical size',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(800, 600);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final vod = DanmakuController(monotonicNow: () => Duration.zero);
        final live = LiveDanmakuController(monotonicNow: () => Duration.zero);
        addTearDown(vod.dispose);
        addTearDown(live.dispose);
        live.configure(area: 1, speed: 1, maxPerSecond: 0);
        vod.replaceEvents(const [
          DanmakuEvent(id: 'text', at: Duration.zero, text: 'DPR text'),
        ]);
        live.add(const [LiveDanmakuEvent(id: 'text', text: 'DPR text')]);
        final overlay = isLive
            ? LiveDanmakuOverlay(controller: live)
            : DanmakuOverlay(controller: vod);
        await tester.pumpWidget(
          MediaQuery.fromView(
            view: tester.view,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Center(
                child: SizedBox(width: 600, height: 300, child: overlay),
              ),
            ),
          ),
        );
        await tester.pump();
        final initialBytes = isLive
            ? live.textRasterBytes
            : vod.textRasterBytes;
        expect(initialBytes, greaterThan(0));
        final initialElement = tester.element(find.byWidget(overlay));
        tester.view.physicalSize = const Size(1600, 1200);
        tester.view.devicePixelRatio = 2;
        await tester.pump();
        await tester.pump();
        expect(tester.element(find.byWidget(overlay)), same(initialElement));
        expect(tester.getSize(find.byWidget(overlay)), const Size(600, 300));
        expect(
          isLive ? live.textRasterBytes : vod.textRasterBytes,
          greaterThan(initialBytes * 3),
        );
        expect(
          isLive ? live.textLayoutBuildCount : vod.textLayoutBuildCount,
          1,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  test('VOD windows do not shape future text or evict visible painters', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 800, height: 400);
    final events = [
      const DanmakuEvent(id: 'visible', at: Duration.zero, text: 'visible'),
      for (var i = 1; i < 500; i++)
        DanmakuEvent(
          id: '$i',
          at: Duration(seconds: i),
          text: 'future $i',
        ),
    ];
    controller.replaceEvents(events);
    expect(controller.textLayoutBuildCount, 0);
    controller.frame();
    expect(controller.textLayoutBuildCount, 1);
    for (var i = 0; i < 10; i++) {
      controller.replaceEvents(events);
      expect(controller.frame().single.event.id, 'visible');
    }
    expect(controller.textLayoutBuildCount, 1);
  });

  test(
    'paused seeks finish bounded admission without advancing the clocks',
    () {
      final controller = DanmakuController(
        monotonicNow: () => Duration.zero,
        maxAdmissionsPerFrame: 2,
      );
      addTearDown(controller.dispose);
      controller.setViewport(width: 800, height: 400);
      controller.replaceEvents([
        for (var i = 0; i < 6; i++)
          DanmakuEvent(id: '$i', at: Duration.zero, text: 'line $i'),
      ]);
      expect(controller.isAnimating, isFalse);
      expect(controller.needsFrame, isTrue);
      for (var batch = 1; batch <= 3; batch++) {
        expect(controller.frame(), hasLength(batch * 2));
        expect(controller.textLayoutBuildCount, batch * 2);
        expect(controller.position, Duration.zero);
      }
      expect(controller.needsFrame, isFalse);
      controller.seekConfirmed(Duration.zero);
      expect(controller.frame().map((p) => p.event.id), ['0', '1']);
      expect(controller.textLayoutBuildCount, 6);
    },
  );

  test(
    'live bursts prepare bounded text and expired backlog needs no layout',
    () {
      var now = Duration.zero;
      final controller = LiveDanmakuController(
        monotonicNow: () => now,
        maxAdmissionsPerFrame: 8,
      );
      addTearDown(controller.dispose);
      controller.configure(area: 1, speed: 1, maxPerSecond: 0);
      controller.setViewport(width: 800, height: 400);
      controller.add([
        for (var i = 0; i < 500; i++)
          LiveDanmakuEvent(id: '$i', text: 'line $i'),
      ]);
      expect(controller.frame(), hasLength(8));
      expect(controller.textLayoutBuildCount, 8);
      expect(controller.pendingCount, 492);
      now = const Duration(seconds: 3);
      final remaining = controller.frame();
      expect(remaining, hasLength(8));
      expect(controller.pendingCount, 0);
      expect(controller.textLayoutBuildCount, 8);
      expect(controller.dropped, 492);
      now = const Duration(seconds: 9);
      expect(controller.frame(), isEmpty);
      expect(controller.isAnimating, isFalse);
    },
  );

  test(
    'larger arriving text reflows lanes without clearing valid active IDs',
    () {
      var now = Duration.zero;
      final vod = DanmakuController(monotonicNow: () => now);
      final live = LiveDanmakuController(monotonicNow: () => now);
      addTearDown(vod.dispose);
      addTearDown(live.dispose);
      vod.setViewport(width: 800, height: 400);
      live.setViewport(width: 800, height: 400);
      live.configure(area: 1, speed: 1, maxPerSecond: 0);
      vod.replaceEvents(const [
        DanmakuEvent(
          id: 'small',
          at: Duration.zero,
          text: 'small',
          fontSize: 12,
        ),
        DanmakuEvent(
          id: 'large',
          at: Duration(seconds: 1),
          text: 'large',
          fontSize: 54,
        ),
      ]);
      live.add(const [
        LiveDanmakuEvent(id: 'small', text: 'small', fontSize: 12),
      ]);
      vod.frame();
      live.frame();
      now = const Duration(seconds: 1);
      vod.sync(
        confirmedPosition: now,
        playing: true,
        buffering: false,
        seeking: false,
        rate: 1,
      );
      live.add(const [
        LiveDanmakuEvent(id: 'large', text: 'large', fontSize: 54),
      ]);
      final vf = vod.frame();
      final lf = live.frame();
      expect(vf.map((p) => p.event.id), ['small', 'large']);
      expect(lf.map((p) => p.event.id), ['small', 'large']);
      expect(vf[1].y - vf[0].y, greaterThanOrEqualTo(54));
      expect(lf[1].y - lf[0].y, greaterThanOrEqualTo(54));
    },
  );

  test('effect pixels match direct painting at display DPR 1 and 2', () async {
    final layouts = DanmakuTextLayouts(8);
    addTearDown(layouts.clear);
    for (final effect in DanmakuTextEffect.values) {
      layouts.style = DanmakuTextStyle(effect: effect);
      for (final ratio in [1.0, 2.0]) {
        final images = <List<int>>[];
        for (final cached in [false, true]) {
          final recorder = ui.PictureRecorder();
          final canvas = Canvas(recorder)..scale(ratio);
          layouts.paint(
            'Text',
            const Color(0xffffffff),
            24,
            canvas,
            const Offset(10, 10),
            pixelRatio: ratio,
            cacheRaster: cached,
          );
          final picture = recorder.endRecording();
          final bitmap = await picture.toImage(
            (160 * ratio).ceil(),
            (60 * ratio).ceil(),
          );
          final data = await bitmap.toByteData();
          images.add(data?.buffer.asUint8List().toList() ?? []);
          bitmap.dispose();
          picture.dispose();
        }
        expect(images[0], isNotEmpty);
        expect(images[1], images[0], reason: '$effect at DPR $ratio');
      }
    }
    expect(layouts.rasterBuildCount, 6);
  });

  test(
    'cached pixels match fresh rasters through fractional DPR and release',
    () async {
      final layouts = DanmakuTextLayouts(8);
      addTearDown(layouts.clear);
      const offset = Offset(10.25, 11.75);
      Future<List<int>> pixels(DanmakuTextLayouts cache, double ratio) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(2);
        cache.paint(
          'Text',
          const Color(0xffaaffcc),
          24,
          canvas,
          offset,
          pixelRatio: ratio,
        );
        final picture = recorder.endRecording();
        final bitmap = await picture.toImage(320, 120);
        final data = await bitmap.toByteData();
        final result = data?.buffer.asUint8List().toList() ?? [];
        bitmap.dispose();
        picture.dispose();
        return result;
      }

      for (final effect in DanmakuTextEffect.values) {
        layouts.style = DanmakuTextStyle(effect: effect);
        for (final ratio in [1.0, 1.25, 2.75, 1.0]) {
          final fresh = DanmakuTextLayouts(8)..style = layouts.style;
          try {
            final expected = await pixels(fresh, ratio);
            expect(expected, isNotEmpty);
            for (var draw = 0; draw < 2; draw++) {
              expect(
                await pixels(layouts, ratio),
                expected,
                reason: '$effect at DPR $ratio, draw $draw',
              );
            }
            layouts.releaseRasters();
            expect(layouts.rasterBytes, 0);
            expect(await pixels(layouts, ratio), expected);
          } finally {
            fresh.clear();
          }
        }
      }
      expect(layouts.rasterBuildCount, 24);
      expect(layouts.rasterStatistics.cacheHits, 12);
      final reference = await pixels(layouts, 1);
      for (final invalid in [double.nan, double.infinity, 0.0, -1.0]) {
        expect(await pixels(layouts, invalid), reference);
      }
      expect(layouts.rasterBuildCount, 24);
    },
  );

  test('raster cache hits keep recently drawn images resident', () {
    final layouts = DanmakuTextLayouts(8, maxRasterBytes: 30000);
    addTearDown(layouts.clear);
    void paint(String text) {
      final recorder = ui.PictureRecorder();
      layouts.paint(
        text,
        const Color(0xffffffff),
        24,
        Canvas(recorder),
        Offset.zero,
      );
      recorder.endRecording().dispose();
      expect(layouts.rasterBytes, lessThanOrEqualTo(30000));
    }

    paint('one');
    paint('two');
    paint('one');
    paint('six');
    paint('one');
    expect(layouts.rasterBuildCount, 3);
    paint('two');
    expect(layouts.rasterBuildCount, 4);
    expect(layouts.rasterStatistics.imagePaints, 6);
    expect(layouts.rasterStatistics.directPaints, 0);
  });

  test(
    'text cache reuses images and releases pixels on LRU/style/DPR changes',
    () {
      final layouts = DanmakuTextLayouts(8, maxRasterBytes: 65536);
      addTearDown(layouts.clear);
      void paint(String text, {double ratio = 1}) {
        final recorder = ui.PictureRecorder();
        layouts.paint(
          text,
          const Color(0xffffffff),
          24,
          Canvas(recorder),
          Offset.zero,
          pixelRatio: ratio,
        );
        recorder.endRecording().dispose();
        expect(layouts.rasterBytes, lessThanOrEqualTo(65536));
      }

      paint('one');
      paint('one');
      expect(layouts.rasterBuildCount, 1);
      paint('one', ratio: 2);
      expect(layouts.rasterBuildCount, 2);
      for (final text in ['two', 'three', 'four']) {
        paint(text);
      }
      expect(layouts.rasterBytes, greaterThan(0));
      layouts.style = const DanmakuTextStyle(effect: DanmakuTextEffect.plain);
      expect(layouts.rasterBytes, 0);
      expect(layouts.length, 0);
      paint('plain');
      expect(layouts.rasterBytes, greaterThan(0));
      layouts.clear();
      expect(layouts.rasterBytes, 0);
    },
  );

  test(
    'oversized visible raster working sets do not cyclically evict images',
    () {
      final layouts = DanmakuTextLayouts(8, maxRasterBytes: 20000);
      addTearDown(layouts.clear);
      for (var frame = 0; frame < 10; frame++) {
        layouts.protectRasters([
          ('one', const Color(0xffffffff), 24.0, false),
          ('two', const Color(0xffffffff), 24.0, false),
        ]);
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        for (final text in ['one', 'two']) {
          layouts.paint(text, const Color(0xffffffff), 24, canvas, Offset.zero);
        }
        recorder.endRecording().dispose();
        expect(layouts.rasterBytes, lessThanOrEqualTo(20000));
      }
      expect(layouts.rasterBuildCount, 1);
      final stats = layouts.rasterStatistics;
      expect(stats.totalPaints, 20);
      expect(stats.imagePaints, 10);
      expect(stats.cacheHits, 9);
      expect(stats.workingSetFallbacks, 10);
      expect(stats.directPaints, 10);
      expect(stats.dimensionFallbacks, 0);
      expect(stats.imageBudgetFallbacks, 0);
      expect(stats.peakRasterBytes, lessThanOrEqualTo(20000));
      layouts.clear();
      expect(layouts.rasterBytes, 0);
    },
  );

  test(
    'raster counters distinguish oversized, image-budget and uncached paint',
    () {
      final layouts = DanmakuTextLayouts(8, maxRasterBytes: 100);
      addTearDown(layouts.clear);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      layouts.paint(
        'x' * 300,
        const Color(0xffffffff),
        24,
        canvas,
        Offset.zero,
        pixelRatio: 3,
      );
      layouts.paint('short', const Color(0xffffffff), 24, canvas, Offset.zero);
      layouts.paint(
        'direct',
        const Color(0xffffffff),
        24,
        canvas,
        Offset.zero,
        cacheRaster: false,
      );
      recorder.endRecording().dispose();
      final stats = layouts.rasterStatistics;
      expect(stats.dimensionFallbacks, 1);
      expect(stats.imageBudgetFallbacks, 1);
      expect(stats.uncachedPaints, 1);
      expect(stats.workingSetFallbacks, 0);
      expect(stats.directPaints, 3);
      expect(stats.totalPaints, 3);
      expect(stats.rasterBuilds, 0);
      expect(stats.peakRasterBytes, 0);
    },
  );
}
