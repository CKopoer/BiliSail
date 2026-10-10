import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_danmaku/src/danmaku_text_style.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
          ('one', const Color(0xffffffff), 24.0),
          ('two', const Color(0xffffffff), 24.0),
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
      layouts.clear();
      expect(layouts.rasterBytes, 0);
    },
  );
}
