import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final live in [false, true]) {
    test('canvas_danmaku batching preserves mixed text at multiple DPRs '
        '(${live ? 'live' : 'VOD'})', () async {
      var now = Duration.zero;
      final reference = _Scene(live, true, () => now, count: 18);
      final batched = _Scene(live, true, () => now, count: 18);
      addTearDown(reference.dispose);
      addTearDown(batched.dispose);
      for (final effect in DanmakuTextEffect.values) {
        for (final scene in [reference, batched]) {
          scene.configure(effect);
          scene.viewport(360);
          scene.add();
          scene.sync(now);
          // Drain bounded admission before advancing the external clock.
          for (var i = 0; i < 9; i++) {
            if (live) {
              scene.stream.frame();
            } else {
              scene.vod.frame();
            }
          }
        }
        expect(batched.visible, greaterThan(10));
        for (final ratio in [1.0, 1.25, 2.0]) {
          now += const Duration(milliseconds: 100);
          reference.sync(now);
          batched.sync(now);
          expect(
            await batched.pixels(ratio, direct: true),
            await reference.pixels(ratio, direct: false),
            reason: '${effect.name}, DPR $ratio',
          );
        }
      }
    });
  }

  for (final live in [false, true]) {
    for (final mixed in [false, true]) {
      test(
        '${live ? 'live' : 'VOD'} direct paint matches '
        '${mixed ? 'mixed' : 'scrolling'} snapshots through lifecycle changes',
        () async {
          var now = Duration.zero;
          final reference = _Scene(live, mixed, () => now);
          final direct = _Scene(live, mixed, () => now);
          addTearDown(reference.dispose);
          addTearDown(direct.dispose);
          var sawPixels = false;
          Future<void> compare(double ratio) async {
            final expected = await reference.pixels(ratio, direct: false);
            final actual = await direct.pixels(ratio, direct: true);
            expect(actual, expected, reason: 'time $now, DPR $ratio');
            sawPixels |= actual.any((value) => value != 0);
            expect(direct.visible, reference.visible);
            expect(direct.stats.imagePaints, reference.stats.imagePaints);
            expect(direct.stats.rasterBuilds, reference.stats.rasterBuilds);
            expect(direct.stats.directPaints, reference.stats.directPaints);
          }

          for (final scene in [reference, direct]) {
            scene.configure(DanmakuTextEffect.shadow);
            scene.viewport(360);
            scene.add();
            scene.sync(now);
          }
          await compare(1);
          expect(direct.visible, 2, reason: 'one bounded admission per paint');
          await compare(1);
          await compare(1);
          for (final ratio in [1.0, 1.25, 2.0]) {
            now += const Duration(milliseconds: 150);
            reference.sync(now);
            direct.sync(now);
            await compare(ratio);
          }
          for (final scene in [reference, direct]) {
            scene.release();
            scene.viewport(301.5);
            scene.sync(now, playing: false);
          }
          now += const Duration(milliseconds: 300);
          await compare(1.25);
          for (final scene in [reference, direct]) {
            scene.configure(DanmakuTextEffect.stroke);
            scene.add();
            scene.seek(now);
            scene.sync(now, rate: 3);
          }
          await compare(2);
          await compare(2);
          now += const Duration(milliseconds: 500);
          reference.sync(now, rate: 3);
          direct.sync(now, rate: 3);
          await compare(2);
          reference.viewport(0);
          direct.viewport(0);
          await compare(2);
          reference.viewport(360);
          direct.viewport(360);
          now += const Duration(seconds: 5);
          reference.sync(now);
          direct.sync(now);
          await compare(1);
          expect(direct.visible, 0);
          expect(sawPixels, isTrue);
        },
      );
    }
  }

  test('direct painting does not mutate previously returned positions', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 800, height: 450);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'a', at: Duration.zero, text: 'snapshot'),
    ]);
    controller.sync(
      confirmedPosition: now,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    final saved = controller.frame();
    final originalX = saved.single.x;
    now += const Duration(milliseconds: 100);
    final recorder = ui.PictureRecorder();
    controller.paintFrame(Canvas(recorder));
    recorder.endRecording().dispose();
    expect(saved.single.x, originalX);
    expect(controller.frame().single.x, lessThan(originalX));
  });
}

final class _Scene {
  _Scene(this.live, this.mixed, Duration Function() now, {this.count = 6})
    : vod = DanmakuController(
        monotonicNow: now,
        maxAdmissionsPerFrame: 2,
        maxTextLayouts: count == 6 ? 3 : 24,
        scrollDuration: const Duration(seconds: 1),
        fixedDuration: const Duration(seconds: 2),
      ),
      stream = LiveDanmakuController(
        monotonicNow: now,
        maxAdmissionsPerFrame: 2,
        maxTextLayouts: count == 6 ? 3 : 24,
        scrollDuration: const Duration(seconds: 1),
        fixedDuration: const Duration(seconds: 2),
      );
  final bool live, mixed;
  final int count;
  final DanmakuController vod;
  final LiveDanmakuController stream;
  int get visible => live ? stream.visibleCount : vod.visibleCount;
  DanmakuRasterStatistics get stats =>
      live ? stream.rasterStatistics : vod.rasterStatistics;
  void configure(DanmakuTextEffect effect) {
    final style = DanmakuTextStyle(effect: effect);
    vod.configure(area: 1, speed: 1, topInset: 8, textStyle: style);
    stream.configure(
      area: 1,
      speed: 1,
      topInset: 8,
      maxPerSecond: 0,
      textStyle: style,
    );
  }

  void viewport(double width) {
    vod.setViewport(width: width, height: 220);
    stream.setViewport(width: width, height: 220);
  }

  void add() {
    final events = [
      for (var i = 0; i < count; i++)
        DanmakuEvent(
          id: '$i',
          at: Duration.zero,
          text: 'Text $i',
          color: i.isEven ? const Color(0xff33ccff) : const Color(0xffff66aa),
          mode: mixed ? DanmakuMode.values[i % 3] : DanmakuMode.scroll,
        ),
    ];
    vod.replaceEvents(events);
    stream.add(
      events.map(
        (e) => LiveDanmakuEvent(
          id: e.id,
          text: e.text,
          color: e.color,
          mode: e.mode,
        ),
      ),
    );
  }

  void sync(Duration at, {bool playing = true, double rate = 1}) => vod.sync(
    confirmedPosition: at,
    playing: playing,
    buffering: false,
    seeking: false,
    rate: rate,
  );
  void seek(Duration at) => vod.seekConfirmed(at);
  void release() {
    vod.releaseRasterCache();
  }

  Future<List<int>> pixels(double ratio, {required bool direct}) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(ratio);
    const bounds = Rect.fromLTWH(0, 0, 360, 220);
    canvas.clipRect(bounds);
    canvas.saveLayer(bounds, Paint()..color = const Color(0xccffffff));
    if (live) {
      if (direct) {
        stream.paintFrame(canvas, pixelRatio: ratio);
      } else {
        for (final item in stream.frame()) {
          stream.paintText(
            item.event,
            canvas,
            Offset(item.x, item.y),
            pixelRatio: ratio,
          );
        }
      }
    } else {
      if (direct) {
        vod.paintFrame(canvas, pixelRatio: ratio);
      } else {
        for (final item in vod.frame()) {
          vod.paintText(
            item.event,
            canvas,
            Offset(item.x, item.y),
            pixelRatio: ratio,
          );
        }
      }
    }
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (360 * ratio).ceil(),
      (220 * ratio).ceil(),
    );
    final data = await image.toByteData();
    final result = data?.buffer.asUint8List().toList() ?? [];
    image.dispose();
    picture.dispose();
    return result;
  }

  void dispose() {
    vod.dispose();
    stream.dispose();
  }
}
