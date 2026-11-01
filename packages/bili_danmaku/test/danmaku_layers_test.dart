import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_danmaku/src/danmaku_layers.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final live in [false, true]) {
    final kind = live ? 'live' : 'VOD';
    testWidgets('$kind keeps fixed pictures while scrolling paints', (
      tester,
    ) async {
      final scene = _Scene(live);
      addTearDown(scene.dispose);
      scene.add();
      await tester.pumpWidget(scene.widget());
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final fixed = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('danmaku-fixed-layer')),
      );
      final scrolling = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('danmaku-scrolling-layer')),
      );
      final fixedPicture = fixed.debugLayer?.firstChild;
      final scrollingPicture = scrolling.debugLayer?.firstChild;
      expect(fixedPicture, isA<PictureLayer>());
      final paints = scene.statistics.totalPaints;
      scene.now += const Duration(milliseconds: 100);
      scene.sync();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(fixed.debugLayer?.firstChild, same(fixedPicture));
      expect(scrolling.debugLayer?.firstChild, isNot(same(scrollingPicture)));
      expect(scene.statistics.totalPaints - paints, 1);

      await tester.pumpWidget(scene.widget(width: 600, ratio: 1.25));
      await tester.pump();
      await tester.pump();
      expect(fixed.debugLayer?.firstChild, isNot(same(fixedPicture)));
      final resized = fixed.debugLayer?.firstChild;
      if (live) {
        scene.stream.clear();
      } else {
        scene.vod.replaceEvents(const []);
      }
      await tester.pump();
      await tester.pump();
      expect(fixed.debugLayer?.firstChild, isNot(same(resized)));
      expect(scene.visible, 0);
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test('$kind two painters share one bounded admission', () {
      final scene = _Scene(live, admissions: 1);
      addTearDown(scene.dispose);
      scene.controller.setViewport(width: 800, height: 400);
      scene.add();
      scene.controller.preparePaintLayers();
      expect(scene.visible, 1);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      scene.controller.paintLayers.paint(
        canvas,
        scrolling: true,
        pixelRatio: 1,
      );
      scene.controller.paintLayers.paint(
        canvas,
        scrolling: false,
        pixelRatio: 1,
      );
      recorder.endRecording().dispose();
      expect(scene.visible, 1, reason: 'paint does not admit the second event');
      scene.controller.preparePaintLayers();
      expect(scene.visible, 2);
    });

    testWidgets('$kind retained fixed pixels survive text cache eviction', (
      tester,
    ) async {
      final scene = _Scene(live, layouts: 1);
      addTearDown(scene.dispose);
      scene.add();
      await tester.pumpWidget(scene.widget());
      await tester.pump();
      await tester.pump();
      await tester.pump();
      final fixed = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('danmaku-fixed-layer')),
      );
      Future<List<int>?> pixels() => tester.runAsync(() async {
        final image = await fixed.toImage();
        final data = await image.toByteData();
        final result = data?.buffer.asUint8List().toList() ?? <int>[];
        image.dispose();
        return result;
      });
      final before = await pixels();
      expect(before?.any((value) => value != 0), isTrue);
      final picture = fixed.debugLayer?.firstChild;
      final builds = scene.statistics.rasterBuilds;
      scene.now += const Duration(milliseconds: 100);
      scene.sync();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump();
      expect(scene.statistics.rasterBuilds, greaterThan(builds));
      expect(fixed.debugLayer?.firstChild, same(picture));
      expect(await pixels(), before);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    test(
      '$kind fixed-over-scroll pixels preserve effects, DPR and group alpha',
      () async {
        for (final effect in DanmakuTextEffect.values) {
          for (final ratio in [1.0, 1.25, 2.0]) {
            final scene = _Scene(live);
            try {
              scene.configure(effect);
              scene.controller.setViewport(width: 240, height: 100);
              scene.add();
              scene.controller.preparePaintLayers();
              scene.now = const Duration(milliseconds: 500);
              scene.sync();
              scene.controller.preparePaintLayers();
              final placements = live
                  ? scene.stream
                        .frame()
                        .map(
                          (p) => (
                            p.event.mode,
                            p.event.text,
                            p.event.color,
                            p.event.fontSize,
                            p.x,
                            p.y,
                          ),
                        )
                        .toList()
                  : scene.vod
                        .frame()
                        .map(
                          (p) => (
                            p.event.mode,
                            p.event.text,
                            p.event.color,
                            p.event.fontSize,
                            p.x,
                            p.y,
                          ),
                        )
                        .toList();
              expect(placements, hasLength(2));
              Future<List<int>> pixels(bool layered) async {
                final recorder = ui.PictureRecorder();
                final canvas = Canvas(recorder)..scale(ratio);
                const bounds = Rect.fromLTWH(0, 0, 240, 100);
                canvas.clipRect(bounds);
                canvas.saveLayer(
                  bounds,
                  Paint()..color = const Color(0xccffffff),
                );
                for (final scrolling in [true, false]) {
                  if (layered) {
                    scene.controller.paintLayers.paint(
                      canvas,
                      scrolling: scrolling,
                      pixelRatio: ratio,
                    );
                  } else {
                    for (final item in placements) {
                      if ((item.$1 == DanmakuMode.scroll) != scrolling) {
                        continue;
                      }
                      if (live) {
                        scene.stream.paintText(
                          LiveDanmakuEvent(
                            id: '',
                            text: item.$2,
                            color: item.$3,
                            fontSize: item.$4,
                          ),
                          canvas,
                          Offset(item.$5, item.$6),
                          pixelRatio: ratio,
                        );
                      } else {
                        scene.vod.paintText(
                          DanmakuEvent(
                            id: '',
                            at: Duration.zero,
                            text: item.$2,
                            color: item.$3,
                            fontSize: item.$4,
                          ),
                          canvas,
                          Offset(item.$5, item.$6),
                          pixelRatio: ratio,
                        );
                      }
                    }
                  }
                }
                canvas.restore();
                final picture = recorder.endRecording();
                final image = await picture.toImage(
                  (240 * ratio).ceil(),
                  (100 * ratio).ceil(),
                );
                final data = await image.toByteData();
                final result = data?.buffer.asUint8List().toList() ?? <int>[];
                image.dispose();
                picture.dispose();
                return result;
              }

              final expected = await pixels(false);
              expect(expected.any((value) => value != 0), isTrue);
              expect(
                await pixels(true),
                expected,
                reason: '$effect, DPR $ratio',
              );
            } finally {
              scene.dispose();
            }
          }
        }
      },
    );
  }
}

final class _Scene {
  _Scene(this.live, {this.admissions = 32, this.layouts = 256});
  final bool live;
  final int admissions, layouts;
  Duration now = Duration.zero;
  late final vod = DanmakuController(
    monotonicNow: () => now,
    maxAdmissionsPerFrame: admissions,
    maxTextLayouts: layouts,
    scrollDuration: const Duration(seconds: 1),
  );
  late final stream = LiveDanmakuController(
    monotonicNow: () => now,
    maxAdmissionsPerFrame: admissions,
    maxTextLayouts: layouts,
    scrollDuration: const Duration(seconds: 1),
  );
  LayeredDanmakuController get controller => live ? stream : vod;
  int get visible => live ? stream.visibleCount : vod.visibleCount;
  DanmakuRasterStatistics get statistics =>
      live ? stream.rasterStatistics : vod.rasterStatistics;
  void add() {
    if (live) {
      stream.add(const [
        LiveDanmakuEvent(
          id: 'fixed',
          text: '分层覆盖',
          mode: DanmakuMode.top,
          color: Color(0xffff0000),
          fontSize: 25,
        ),
        LiveDanmakuEvent(
          id: 'scroll',
          text: '分层覆盖',
          color: Color(0xff00ff00),
          fontSize: 25,
        ),
      ]);
    } else {
      vod.replaceEvents(const [
        DanmakuEvent(
          id: 'fixed',
          at: Duration.zero,
          text: '分层覆盖',
          mode: DanmakuMode.top,
          color: Color(0xffff0000),
          fontSize: 25,
        ),
        DanmakuEvent(
          id: 'scroll',
          at: Duration.zero,
          text: '分层覆盖',
          color: Color(0xff00ff00),
          fontSize: 25,
        ),
      ]);
      sync();
    }
  }

  void configure(DanmakuTextEffect effect) {
    final style = DanmakuTextStyle(effect: effect);
    if (live) {
      stream.configure(area: 1, speed: 1, maxPerSecond: 0, textStyle: style);
    } else {
      vod.configure(area: 1, speed: 1, textStyle: style);
    }
  }

  void sync() {
    if (!live) {
      vod.sync(
        confirmedPosition: now,
        playing: true,
        buffering: false,
        seeking: false,
        rate: 1,
      );
    }
  }

  Widget widget({double width = 800, double ratio = 1}) => Directionality(
    textDirection: TextDirection.ltr,
    child: MediaQuery(
      data: MediaQueryData(devicePixelRatio: ratio),
      child: Center(
        child: SizedBox(
          width: width,
          height: 400,
          child: Opacity(
            opacity: .8,
            child: live
                ? LiveDanmakuOverlay(controller: stream, bottomInset: 0)
                : DanmakuOverlay(controller: vod),
          ),
        ),
      ),
    ),
  );
  void dispose() {
    if (live) {
      stream.dispose();
    } else {
      vod.dispose();
    }
  }
}
