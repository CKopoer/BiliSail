import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_danmaku/src/danmaku_text_style.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'small scaled text keeps its requested font size and measured width',
    () {
      final layouts = DanmakuTextLayouts(8);
      addTearDown(layouts.clear);
      final normal = layouts.layout('Text', const Color(0xffffffff), 24);
      for (final size in [2.4, 4.8]) {
        final small = layouts.layout('Text', const Color(0xffffffff), size);
        final span = small.text as TextSpan;
        expect(span.style?.fontSize, size);
        expect(small.width, lessThan(normal.width));
        expect(small.height, lessThan(normal.height));
      }
    },
  );
  test('same-screen density is independent from arrival rate and keeps safety bounds', () {
    final vod = DanmakuController(monotonicNow: () => Duration.zero);
    final live = LiveDanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(vod.dispose);
    addTearDown(live.dispose);
    vod.setViewport(width: 600, height: 400);
    live.setViewport(width: 600, height: 400);
    final events = List.generate(
      5,
      (i) => DanmakuEvent(id: '$i', at: Duration.zero, text: '$i'),
    );
    for (final count in [2, 0]) {
      vod.configure(area: 1, speed: 1, maxOnScreen: count);
      live.configure(area: 1, speed: 1, maxPerSecond: 0, maxOnScreen: count);
      vod.replaceEvents(events);
      live.add(events.map((e) => LiveDanmakuEvent(id: e.id, text: e.text)));
      expect(vod.frame(), hasLength(count == 0 ? 5 : 2));
      expect(live.frame(), hasLength(count == 0 ? 5 : 2));
    }
  });
  test('positive offsets delay, negative offsets advance, seeks replay merged comments', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 400);
    controller.configure(
      area: 1,
      speed: 1,
      offset: const Duration(seconds: 2),
      mergeDuplicates: true,
    );
    controller.replaceEvents(const [
      DanmakuEvent(id: 'a', at: Duration(seconds: 1), text: 'same'),
      DanmakuEvent(id: 'b', at: Duration(seconds: 1), text: 'same'),
      DanmakuEvent(id: 'c', at: Duration(seconds: 1), text: 'different'),
      DanmakuEvent(
        id: 'top',
        at: Duration(seconds: 1),
        text: 'same',
        mode: DanmakuMode.top,
      ),
    ]);
    controller.seekConfirmed(const Duration(seconds: 2));
    expect(controller.frame(), isEmpty);
    controller.seekConfirmed(const Duration(seconds: 3));
    expect(controller.frame().map((p) => p.event.id), ['a', 'c', 'top']);
    controller.seekConfirmed(Duration.zero);
    expect(controller.frame(), isEmpty);
    controller.configure(
      area: 1,
      speed: 1,
      offset: const Duration(seconds: -1),
    );
    expect(controller.frame(), hasLength(4));
    expect(controller.position, Duration.zero);
  });

  test(
    'live delay preserves capacity and zero density allows more than twenty',
    () {
      var now = Duration.zero;
      final controller = LiveDanmakuController(
        monotonicNow: () => now,
        maxPending: 30,
      );
      addTearDown(controller.dispose);
      controller.configure(
        area: 1,
        speed: 1,
        maxPerSecond: 0,
        offset: const Duration(seconds: 5),
        mergeDuplicates: true,
      );
      controller.setViewport(width: 600, height: 400);
      controller.add(
        List.generate(30, (i) => LiveDanmakuEvent(id: '$i', text: 'same')),
      );
      expect(controller.pendingCount, 30);
      now = const Duration(seconds: 4);
      expect(controller.frame(), isEmpty);
      expect(controller.pendingCount, 30);
      now = const Duration(seconds: 5);
      expect(controller.frame(), hasLength(1));
      controller.setEnabled(false);
      controller.setEnabled(true);
      expect(controller.frame(), isEmpty);
      controller.configure(
        area: 1,
        speed: 1,
        maxPerSecond: 0,
        offset: const Duration(seconds: -1),
      );
      controller.add(const [LiveDanmakuEvent(id: 'instant', text: 'now')]);
      expect(controller.frame().single.event.id, 'instant');
    },
  );

  test('large VOD fonts reserve measured lane height and active size updates apply', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 400);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'one', at: Duration.zero, text: 'one', fontSize: 54),
      DanmakuEvent(id: 'two', at: Duration.zero, text: 'two', fontSize: 54),
    ]);
    final frame = controller.frame();
    expect(frame[1].y - frame[0].y, greaterThanOrEqualTo(54));
    controller.replaceEvents(const [
      DanmakuEvent(id: 'one', at: Duration.zero, text: 'one', fontSize: 24),
    ]);
    expect(controller.frame().single.event.fontSize, 24);
  });

  test(
    'font, weight and effects alter actual cached text and painted pixels',
    () async {
      final layouts = DanmakuTextLayouts(2);
      addTearDown(layouts.clear);
      final pixels = <List<int>>[];
      for (final effect in DanmakuTextEffect.values) {
        layouts.clear();
        layouts.style = DanmakuTextStyle(
          fontFamily: 'Ahem',
          bold: true,
          effect: effect,
        );
        final painter = layouts.layout('Text', const Color(0xffffffff), 24);
        final span = painter.text as TextSpan;
        expect(span.style?.fontFamily, 'Ahem');
        expect(span.style?.fontWeight, FontWeight.bold);
        expect(
          span.style?.shadows?.isNotEmpty ?? false,
          effect == DanmakuTextEffect.shadow,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        layouts.paint(
          'Text',
          const Color(0xffffffff),
          24,
          canvas,
          const Offset(4, 4),
        );
        final picture = recorder.endRecording();
        final bitmap = await picture.toImage(140, 50);
        final data = await bitmap.toByteData();
        expect(data, isNotNull);
        pixels.add(data?.buffer.asUint8List().toList() ?? []);
        bitmap.dispose();
        picture.dispose();
      }
      expect(pixels[0], isNot(pixels[1]));
      expect(pixels[1], isNot(pixels[2]));
      for (final text in ['a', 'b', 'c']) {
        layouts.layout(text, const Color(0xffffffff), 24);
      }
      expect(layouts.length, 2);
    },
  );
}
