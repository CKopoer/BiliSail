import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('dense window trimming preserves visible progress until expiry', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 800, height: 400);
    const visible = DanmakuEvent(
      id: 'visible',
      at: Duration.zero,
      text: 'still scrolling',
    );
    controller.replaceEvents(const [visible]);
    void sync() => controller.sync(
      confirmedPosition: now,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    sync();
    controller.frame();
    for (var tick = 1; tick <= 8; tick++) {
      now = Duration(milliseconds: tick * 500);
      sync();
    }
    final halfway = controller.frame().single;
    expect(halfway.x, inExclusiveRange(0, 800));
    final dense = [
      visible,
      for (var i = 0; i < 600; i++)
        DanmakuEvent(
          id: 'burst-$i',
          at: const Duration(seconds: 3),
          text: 'burst $i',
        ),
    ];
    for (var refresh = 0; refresh < 3; refresh++) {
      controller.replaceEvents(dense);
      final frame = controller.frame();
      final retained = frame.where((p) => p.event.id == visible.id).toList();
      expect(retained, hasLength(1));
      expect(retained.single.x, halfway.x);
      expect(retained.single.y, halfway.y);
      expect(controller.pendingCount, lessThanOrEqualTo(500));
      expect(controller.visibleCount, lessThanOrEqualTo(120));
    }
    // Re-entering the pending window keeps the same active instance, not a
    // newly admitted copy with a reconstructed age.
    controller.replaceEvents(const [visible]);
    expect(controller.frame().single.x, halfway.x);
    for (var tick = 9; tick <= 16; tick++) {
      now = Duration(milliseconds: tick * 500);
      sync();
      controller.replaceEvents(dense);
      expect(
        controller.frame().where((p) => p.event.id == visible.id),
        tick < 16 ? hasLength(1) : isEmpty,
      );
    }
  });

  test(
    'authoritative removal and content changes still replace active items',
    () {
      final controller = DanmakuController(monotonicNow: () => Duration.zero);
      addTearDown(controller.dispose);
      controller.setViewport(width: 800, height: 400);
      const original = DanmakuEvent(id: 'same', at: Duration.zero, text: 'old');
      controller.replaceEvents(const [original]);
      expect(controller.frame().single.event.text, 'old');
      controller.replaceEvents(const [
        DanmakuEvent(id: 'same', at: Duration.zero, text: 'changed'),
      ]);
      expect(controller.frame().single.event.text, 'changed');
      controller.replaceEvents(const []);
      expect(controller.frame(), isEmpty);
    },
  );

  for (final mode in DanmakuMode.values) {
    test('larger ${mode.name} arrivals cannot evict occupied rows', () {
      var now = Duration.zero;
      final vod = DanmakuController(monotonicNow: () => now);
      final live = LiveDanmakuController(monotonicNow: () => now);
      addTearDown(vod.dispose);
      addTearDown(live.dispose);
      vod.setViewport(width: 800, height: 240);
      live.setViewport(width: 800, height: 240);
      live.configure(area: 1, speed: 1, maxPerSecond: 0);
      final events = [
        for (var i = 0; i < 8; i++)
          DanmakuEvent(
            id: 'small-$i',
            at: Duration.zero,
            text: 'small',
            mode: mode,
            fontSize: 12,
          ),
        DanmakuEvent(
          id: 'large',
          at: const Duration(seconds: 2),
          text: 'large',
          mode: mode,
          fontSize: 54,
        ),
        DanmakuEvent(
          id: 'later-large',
          at: const Duration(seconds: 9),
          text: 'large',
          mode: mode,
          fontSize: 54,
        ),
      ];
      vod.replaceEvents(events);
      live.add([
        for (final event in events.take(8))
          LiveDanmakuEvent(
            id: event.id,
            text: event.text,
            mode: mode,
            fontSize: event.fontSize,
          ),
      ]);
      void sync() => vod.sync(
        confirmedPosition: now,
        playing: true,
        buffering: false,
        seeking: false,
        rate: 1,
      );
      sync();
      expect(vod.frame(), hasLength(8));
      expect(live.frame(), hasLength(8));
      for (var tick = 1; tick <= 3; tick++) {
        now = Duration(milliseconds: tick * 500);
        sync();
      }
      now = const Duration(seconds: 2);
      final before = live.frame();
      live.add([
        LiveDanmakuEvent(id: 'large', text: 'large', mode: mode, fontSize: 54),
      ]);
      sync();
      final vf = vod.frame();
      final lf = live.frame();
      final originalIds = events.take(8).map((e) => e.id).toList();
      expect(vf.map((p) => p.event.id), originalIds);
      expect(lf.map((p) => p.event.id), originalIds);
      for (var i = 0; i < before.length; i++) {
        expect(vf[i].x, before[i].x);
        expect(lf[i].x, before[i].x);
        expect(vf[i].y, before[i].y);
        expect(lf[i].y, before[i].y);
      }
      expect(vod.dropped, 1);
      expect(live.dropped, 1);
      // Once the original rows expire, subsequent large text can use the area.
      for (var tick = 5; tick <= 18; tick++) {
        now = Duration(milliseconds: tick * 500);
        sync();
        vod.frame();
        live.frame();
      }
      live.add([
        LiveDanmakuEvent(
          id: 'later-large',
          text: 'large',
          mode: mode,
          fontSize: 54,
        ),
      ]);
      expect(vod.frame().single.event.id, 'later-large');
      expect(live.frame().single.event.id, 'later-large');
    });
  }
}
