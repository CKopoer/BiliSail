import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('top inset offsets live modes and shrinks their available lanes', () {
    final controller = LiveDanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 384, bottomInset: 64);
    controller.configure(area: .5, speed: 1, maxPerSecond: 20, topInset: 40);
    const events = [
      LiveDanmakuEvent(id: 'scroll', text: 'scroll'),
      LiveDanmakuEvent(id: 'top', text: 'top', mode: DanmakuMode.top),
      LiveDanmakuEvent(id: 'bottom', text: 'bottom', mode: DanmakuMode.bottom),
    ];
    controller.add(events);
    expect(controller.frame().map((item) => item.y), [40, 40, 132]);
    controller.configure(area: .5, speed: 1, maxPerSecond: 20);
    controller.add(events);
    expect(controller.frame().map((item) => item.y), [0, 0, 112]);
  });
  test(
    'live top inset clamps to short viewports and rejects nonfinite values',
    () {
      final controller = LiveDanmakuController(
        monotonicNow: () => Duration.zero,
      );
      addTearDown(controller.dispose);
      controller.configure(area: 1, speed: 1, maxPerSecond: 20, topInset: 200);
      controller.setViewport(width: 320, height: 160, bottomInset: 40);
      controller.add(const [LiveDanmakuEvent(id: 'small', text: 'small')]);
      expect(controller.frame(), isEmpty);
      controller.setViewport(width: 600, height: 384, bottomInset: 40);
      controller.add(const [LiveDanmakuEvent(id: 'large', text: 'large')]);
      expect(controller.frame().single.y, 200);
      controller.configure(
        area: 1,
        speed: 1,
        maxPerSecond: 20,
        topInset: double.nan,
      );
      controller.add(const [LiveDanmakuEvent(id: 'zero', text: 'zero')]);
      expect(controller.frame().single.y, 0);
    },
  );
  test('receipt clock moves without any video position samples', () {
    var now = Duration.zero;
    final controller = LiveDanmakuController(monotonicNow: () => now);
    controller.setViewport(width: 600, height: 300);
    controller.add(const [LiveDanmakuEvent(id: 'one', text: '实时弹幕')]);
    final first = controller.frame().single;
    now = const Duration(seconds: 1);
    expect(controller.frame().single.x, lessThan(first.x));
    now = const Duration(seconds: 9);
    expect(controller.frame(), isEmpty);
    controller.dispose();
  });
  test('disabled and stale pending messages never replay after return', () {
    var now = Duration.zero;
    final controller = LiveDanmakuController(monotonicNow: () => now);
    controller.setViewport(width: 600, height: 300);
    controller.add(const [LiveDanmakuEvent(id: 'old', text: '旧弹幕')]);
    now = const Duration(seconds: 3);
    expect(controller.frame(), isEmpty);
    controller.setEnabled(false);
    controller.add(const [LiveDanmakuEvent(id: 'hidden', text: '隐藏时收到')]);
    controller.setEnabled(true);
    expect(controller.frame(), isEmpty);
    controller.dispose();
  });
  test('density, pending and visible capacity are independent bounds', () {
    final controller = LiveDanmakuController(
      monotonicNow: () => Duration.zero,
      maxPending: 10,
      maxVisible: 2,
    );
    controller.configure(area: 1, speed: 1, maxPerSecond: 100);
    controller.setViewport(width: 600, height: 300);
    controller.add(
      List.generate(30, (i) => LiveDanmakuEvent(id: '$i', text: '$i')),
    );
    expect(controller.pendingCount, 10);
    expect(controller.frame(), hasLength(2));
    expect(controller.visibleCount, 2);
    expect(controller.pendingCount, 0);
    controller.dispose();
  });
  test(
    'large fonts use measured line height and cannot overlap adjacent lanes',
    () {
      final controller = LiveDanmakuController(
        monotonicNow: () => Duration.zero,
      );
      controller.configure(area: 1, speed: 1, maxPerSecond: 20);
      controller.setViewport(width: 600, height: 400);
      controller.add(const [
        LiveDanmakuEvent(id: 'one', text: '弹幕', fontSize: 54),
        LiveDanmakuEvent(id: 'two', text: '弹幕', fontSize: 54),
      ]);
      final placements = controller.frame();
      expect(placements, hasLength(2));
      final text = TextPainter(
        text: const TextSpan(text: '弹幕', style: TextStyle(fontSize: 54)),
        textDirection: TextDirection.ltr,
      )..layout();
      expect(
        placements[1].y - placements[0].y,
        greaterThanOrEqualTo(text.height),
      );
      text.dispose();
      controller.dispose();
    },
  );
  test(
    'duplicate IDs and invalid text are discarded with bounded layout cache',
    () {
      var now = Duration.zero;
      final controller = LiveDanmakuController(
        monotonicNow: () => now,
        maxTextLayouts: 2,
      );
      controller.setViewport(width: 600, height: 400);
      controller.add(const [
        LiveDanmakuEvent(id: 'one', text: '1'),
        LiveDanmakuEvent(id: 'one', text: '1'),
        LiveDanmakuEvent(id: 'empty', text: ''),
      ]);
      expect(controller.frame(), hasLength(1));
      now = const Duration(seconds: 1);
      controller.add(const [
        LiveDanmakuEvent(id: 'two', text: '2'),
        LiveDanmakuEvent(id: 'three', text: '3'),
      ]);
      controller.frame();
      expect(controller.textLayoutCount, lessThanOrEqualTo(2));
      controller.dispose();
    },
  );
}
