import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'bottom inset changes preserve active comments and scheduling history',
    () {
      var now = Duration.zero;
      final controller = DanmakuController(monotonicNow: () => now);
      addTearDown(controller.dispose);
      controller.setViewport(width: 600, height: 384, bottomInset: 100);
      controller.configure(area: 1, speed: 1, maxOnScreen: 1);
      controller.replaceEvents(const [
        DanmakuEvent(
          id: 'warmup',
          at: Duration.zero,
          text: 'warmup',
          mode: DanmakuMode.top,
        ),
        DanmakuEvent(id: 'dropped', at: Duration(seconds: 1), text: 'dropped'),
        DanmakuEvent(id: 'visible', at: Duration(seconds: 4), text: 'visible'),
        DanmakuEvent(id: 'future', at: Duration(seconds: 14), text: 'future'),
      ]);
      for (var second = 0; second <= 5; second++) {
        controller.sync(
          confirmedPosition: Duration(seconds: second),
          playing: false,
          buffering: false,
          seeking: false,
          rate: 1,
        );
        controller.frame();
      }
      final before = controller.frame().single;
      expect(before.event.id, 'visible');
      final pending = controller.pendingCount;
      final dropped = controller.dropped;
      final layouts = controller.textLayoutCount;
      for (final inset in [48.0, 100.0, 48.0, 100.0]) {
        controller.setViewport(width: 600, height: 384, bottomInset: inset);
        expect(controller.visibleCount, 1);
        expect(controller.pendingCount, pending);
        expect(controller.textLayoutCount, layouts);
        final after = controller.frame().single;
        expect(after.event.id, before.event.id);
        expect(after.x, before.x);
        expect(after.y, before.y);
        expect(controller.dropped, dropped);
      }
      controller.sync(
        confirmedPosition: const Duration(seconds: 5),
        playing: true,
        buffering: false,
        seeking: false,
        rate: 1,
      );
      now = const Duration(milliseconds: 250);
      expect(controller.frame().single.x, lessThan(before.x));
      for (var second = 6; second <= 14; second++) {
        controller.sync(
          confirmedPosition: Duration(seconds: second),
          playing: false,
          buffering: false,
          seeking: false,
          rate: 1,
        );
        expect(
          controller.frame().map((p) => p.event.id),
          second < 12 ? ['visible'] : (second < 14 ? <String>[] : ['future']),
        );
      }
      controller.seekConfirmed(const Duration(seconds: 1));
      expect(controller.frame().single.event.id, 'warmup');
      controller.setViewport(width: 800, height: 384, bottomInset: 100);
      expect(controller.visibleCount, 0);
      expect(controller.frame().single.event.id, 'warmup');
    },
  );

  test(
    'inset changes only remove lanes outside the remaining display area',
    () {
      final controller = DanmakuController(monotonicNow: () => Duration.zero);
      addTearDown(controller.dispose);
      controller.setViewport(width: 600, height: 384, bottomInset: 48);
      controller.configure(area: .5, speed: 1, topInset: 40);
      controller.replaceEvents(const [
        DanmakuEvent(id: 'scroll-0', at: Duration.zero, text: 'scroll-0'),
        DanmakuEvent(id: 'scroll-1', at: Duration.zero, text: 'scroll-1'),
        DanmakuEvent(id: 'scroll-2', at: Duration.zero, text: 'scroll-2'),
        DanmakuEvent(
          id: 'top',
          at: Duration.zero,
          text: 'top',
          mode: DanmakuMode.top,
        ),
        DanmakuEvent(
          id: 'bottom',
          at: Duration.zero,
          text: 'bottom',
          mode: DanmakuMode.bottom,
        ),
      ]);
      final before = controller.frame();
      expect(before.map((p) => p.event.id), [
        'scroll-0',
        'scroll-1',
        'scroll-2',
        'top',
        'bottom',
      ]);
      controller.setViewport(width: 600, height: 384, bottomInset: 100);
      final after = controller.frame();
      expect(after.map((p) => p.event.id), [
        'scroll-0',
        'scroll-1',
        'top',
        'bottom',
      ]);
      expect(
        after.take(3).map((p) => p.y),
        before.take(2).map((p) => p.y).followedBy([40.0]),
      );
      expect(after.last.y, before.last.y - 26);
      controller.setViewport(width: 600, height: 384, bottomInset: 48);
      expect(
        controller.frame().map((p) => p.event.id),
        after.map((p) => p.event.id),
      );
      controller.setViewport(width: 600, height: 384, bottomInset: 1000);
      expect(controller.frame(), isEmpty);
    },
  );

  test('top inset offsets all modes inside the remaining display area', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 384, bottomInset: 64);
    controller.configure(area: .5, speed: 1, topInset: 40);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
      DanmakuEvent(
        id: 'top',
        at: Duration.zero,
        text: 'top',
        mode: DanmakuMode.top,
      ),
      DanmakuEvent(
        id: 'bottom',
        at: Duration.zero,
        text: 'bottom',
        mode: DanmakuMode.bottom,
      ),
    ]);
    final frame = controller.frame();
    expect(frame.map((item) => item.y), [40, 40, 132]);
    controller.configure(area: .5, speed: 1);
    expect(controller.frame().map((item) => item.y), [0, 0, 112]);
  });
  test('top inset clamps to the viewport without negative lanes', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.configure(area: 1, speed: 1, topInset: 200);
    controller.setViewport(width: 320, height: 160, bottomInset: 40);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'one', at: Duration.zero, text: 'one'),
    ]);
    expect(controller.frame(), isEmpty);
    controller.setViewport(width: 600, height: 384, bottomInset: 40);
    expect(controller.frame().single.y, 200);
    controller.configure(area: 1, speed: 1, topInset: double.nan);
    expect(controller.frame().single.y, 0);
  });
  test(
    'configured area limits lanes and faster speed shortens scroll lifetime',
    () {
      final controller = DanmakuController(monotonicNow: () => Duration.zero);
      controller.setViewport(width: 500, height: 384);
      controller.configure(area: .25, speed: 2);
      controller.replaceEvents(const [
        DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
        DanmakuEvent(
          id: 'bottom',
          at: Duration.zero,
          text: 'bottom',
          mode: DanmakuMode.bottom,
        ),
      ]);
      final initial = controller.frame();
      expect(initial, hasLength(2));
      expect(initial.every((placement) => placement.y < 96), isTrue);
      controller.seekConfirmed(const Duration(seconds: 5));
      expect(controller.frame(), isEmpty);
      controller.configure(area: 1, speed: .5);
      controller.seekConfirmed(const Duration(seconds: 5));
      expect(
        controller.frame().map((item) => item.event.id),
        contains('scroll'),
      );
      controller.dispose();
    },
  );
  test(
    'clock advances from confirmed position and freezes on pause or buffering',
    () {
      var now = Duration.zero;
      final controller = DanmakuController(monotonicNow: () => now);
      controller.sync(
        confirmedPosition: const Duration(seconds: 5),
        playing: true,
        buffering: false,
        seeking: false,
        rate: 2,
      );
      now = const Duration(milliseconds: 250);
      expect(controller.position, const Duration(milliseconds: 5500));
      now = const Duration(seconds: 2);
      expect(controller.position, const Duration(milliseconds: 6400));
      controller.sync(
        confirmedPosition: const Duration(milliseconds: 5550),
        playing: true,
        buffering: true,
        seeking: false,
        rate: 2,
      );
      now = const Duration(seconds: 3);
      expect(controller.position, const Duration(milliseconds: 5550));
      controller.sync(
        confirmedPosition: const Duration(milliseconds: 5550),
        playing: false,
        buffering: false,
        seeking: false,
        rate: 1,
      );
      now = const Duration(seconds: 4);
      expect(controller.position, const Duration(milliseconds: 5550));
      controller.dispose();
    },
  );

  test('confirmed seek rebuilds visible window and permits rewind replay', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    controller.setViewport(width: 500, height: 240);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'early', at: Duration(seconds: 1), text: 'early'),
      DanmakuEvent(id: 'late', at: Duration(seconds: 20), text: 'late'),
    ]);
    controller.seekConfirmed(const Duration(seconds: 20));
    expect(controller.frame().map((e) => e.event.id), contains('late'));
    controller.seekConfirmed(const Duration(seconds: 1));
    expect(controller.frame().map((e) => e.event.id), contains('early'));
    controller.dispose();
  });

  test('pending events, active comments, and text layouts stay bounded', () {
    final controller = DanmakuController(
      monotonicNow: () => Duration.zero,
      maxPending: 10,
      maxVisible: 2,
      maxTextLayouts: 2,
    );
    controller.setViewport(width: 400, height: 100);
    controller.replaceEvents(
      List.generate(
        30,
        (index) => DanmakuEvent(
          id: '$index',
          at: Duration.zero,
          text: 'comment $index',
        ),
      ),
    );
    final frame = controller.frame();
    expect(controller.pendingCount, lessThanOrEqualTo(10));
    expect(frame.length, lessThanOrEqualTo(2));
    expect(controller.textLayoutCount, lessThanOrEqualTo(2));
    expect(controller.dropped, greaterThan(0));
    controller.dispose();
  });

  test(
    'sliding window refresh keeps active comment without duplicating it',
    () {
      final controller = DanmakuController(monotonicNow: () => Duration.zero);
      controller.setViewport(width: 400, height: 200);
      const active = DanmakuEvent(id: 'same', at: Duration.zero, text: 'hello');
      controller.replaceEvents(const [active]);
      expect(controller.frame(), hasLength(1));
      controller.replaceEvents(const [
        active,
        DanmakuEvent(id: 'later', at: Duration(seconds: 10), text: 'later'),
      ]);
      expect(
        controller.frame().where((e) => e.event.id == 'same'),
        hasLength(1),
      );
      controller.dispose();
    },
  );
}
