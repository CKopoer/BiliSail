import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_danmaku/src/danmaku_text_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final effect in DanmakuTextEffect.values) {
    for (final ratio in [1.0, 2.0]) {
      test(
        'member outline stays pink-blue and white with $effect at DPR $ratio',
        () async {
          final layouts = DanmakuTextLayouts(8)
            ..style = DanmakuTextStyle(fontFamily: 'Ahem', effect: effect);
          addTearDown(layouts.clear);
          for (final cached in [false, true]) {
            final recorder = ui.PictureRecorder();
            final canvas = Canvas(recorder)..scale(ratio);
            layouts.paint(
              'MMMM',
              const Color(0xff000000),
              24,
              canvas,
              const Offset(10, 10),
              pixelRatio: ratio,
              cacheRaster: cached,
              isColorful: true,
            );
            final picture = recorder.endRecording();
            final image = await picture.toImage(
              (160 * ratio).ceil(),
              (70 * ratio).ceil(),
            );
            final bytes = (await image.toByteData())!.buffer.asUint8List();
            var pink = false, blue = false, white = false;
            for (var i = 0; i < bytes.length; i += 4) {
              if (bytes[i + 3] < 240) continue;
              pink |= bytes[i] > bytes[i + 2] + 20;
              blue |= bytes[i + 2] > bytes[i] + 20;
              white |=
                  bytes[i] > 245 && bytes[i + 1] > 245 && bytes[i + 2] > 245;
            }
            image.dispose();
            picture.dispose();
            expect(
              (pink, blue, white),
              (true, true, true),
              reason: 'cacheRaster=$cached',
            );
          }
          expect(layouts.buildCount, 1);
          expect(layouts.rasterBuildCount, 1);
        },
      );
    }
  }

  test('member and ordinary entries retain separate bounded caches', () {
    final layouts = DanmakuTextLayouts(4);
    addTearDown(layouts.clear);
    for (var frame = 0; frame < 3; frame++) {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      for (final colorful in [false, true]) {
        layouts.paint(
          'same',
          const Color(0xffffffff),
          24,
          canvas,
          Offset(frame.toDouble(), 0),
          isColorful: colorful,
        );
      }
      recorder.endRecording().dispose();
    }
    expect(layouts.buildCount, 2);
    expect(layouts.rasterBuildCount, 2);
    expect(layouts.rasterStatistics.cacheHits, 4);
  });

  test('member style survives all retained layers and same-ID updates', () {
    for (final mode in DanmakuMode.values) {
      final controller = DanmakuController(monotonicNow: () => Duration.zero);
      addTearDown(controller.dispose);
      controller.setViewport(width: 640, height: 360);
      controller.replaceEvents([
        DanmakuEvent(id: 'one', at: Duration.zero, text: 'same', mode: mode),
      ]);
      expect(controller.frame().single.event.isColorful, isFalse);
      controller.replaceEvents([
        DanmakuEvent(
          id: 'one',
          at: Duration.zero,
          text: 'same',
          mode: mode,
          isColorful: true,
        ),
      ]);
      expect(controller.frame().single.event.isColorful, isTrue);
      controller.preparePaintLayers();
      final recorder = ui.PictureRecorder();
      controller.paintLayers.paint(
        Canvas(recorder),
        scrolling: mode == DanmakuMode.scroll,
        pixelRatio: 1,
      );
      recorder.endRecording().dispose();
      expect(controller.rasterStatistics.rasterBuilds, greaterThan(0));
    }
  });
}
