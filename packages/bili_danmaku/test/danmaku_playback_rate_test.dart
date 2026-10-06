import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final rate in [.5, 1.0, 2.0, 3.0]) {
    test('$rate x schedules by media time and scrolls by elapsed time', () {
      var now = Duration.zero;
      final controller = DanmakuController(monotonicNow: () => now);
      addTearDown(controller.dispose);
      controller.setViewport(width: 600, height: 384);
      controller.replaceEvents(const [
        DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
        DanmakuEvent(
          id: 'later',
          at: Duration(milliseconds: 750),
          text: 'later',
        ),
      ]);
      controller.sync(
        confirmedPosition: Duration.zero,
        playing: true,
        buffering: false,
        seeking: false,
        rate: rate,
      );
      expect(controller.frame().single.x, 600);
      now = const Duration(milliseconds: 500);
      final frame = controller.frame();
      // Flutter's test font measures six 24-pixel glyphs for "scroll".
      expect(frame.first.x, closeTo(600 - (600 + 144) / 16, .001));
      expect(controller.position.inMilliseconds, (500 * rate).round());
      expect(
        frame.map((p) => p.event.id),
        rate >= 2 ? ['scroll', 'later'] : ['scroll'],
      );
    });
  }

  test('rate changes and position corrections preserve scroll progress', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 384);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
    ]);
    controller.sync(
      confirmedPosition: Duration.zero,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 1,
    );
    controller.frame();
    var mediaPosition = Duration.zero;
    var previousRate = 1.0;
    for (final rate in [3.0, .5, 2.0, 1.0]) {
      now += const Duration(milliseconds: 250);
      mediaPosition += Duration(milliseconds: (250 * previousRate).round());
      final before = controller.frame().single;
      controller.sync(
        confirmedPosition: mediaPosition + const Duration(milliseconds: 20),
        playing: true,
        buffering: false,
        seeking: false,
        rate: rate,
      );
      expect(controller.frame().single.x, before.x);
      expect(before.x, closeTo(600 - 744 * now.inMilliseconds / 8000, .001));
      previousRate = rate;
    }
  });

  test('pause, buffering, seeking and stale samples freeze visual motion', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 384);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
    ]);
    controller.sync(
      confirmedPosition: Duration.zero,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 3,
    );
    controller.frame();
    now = const Duration(milliseconds: 250);
    var mediaPosition = controller.position;
    var x = controller.frame().single.x;
    for (final state in [
      (false, false, false),
      (true, true, false),
      (true, false, true),
    ]) {
      controller.sync(
        confirmedPosition: mediaPosition,
        playing: state.$1,
        buffering: state.$2,
        seeking: state.$3,
        rate: 3,
      );
      now += const Duration(seconds: 2);
      expect(controller.frame().single.x, x);
      expect(controller.position, mediaPosition);
      expect(controller.isAnimating, isFalse);
    }
    controller.sync(
      confirmedPosition: mediaPosition,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 3,
    );
    now += const Duration(milliseconds: 250);
    expect(x - controller.frame().single.x, closeTo(744 / 32, .001));
    now += const Duration(seconds: 2);
    x = controller.frame().single.x;
    mediaPosition = controller.position;
    expect(controller.isAnimating, isFalse);
    now += const Duration(seconds: 2);
    expect(controller.frame().single.x, x);
    expect(controller.position, mediaPosition);
  });

  test('visual lifetimes and window refreshes stay independent of rate', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 384);
    const events = [
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
    ];
    controller.replaceEvents(events);
    controller.sync(
      confirmedPosition: Duration.zero,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 3,
    );
    expect(controller.frame(), hasLength(3));
    for (var halfSecond = 1; halfSecond <= 16; halfSecond++) {
      now = Duration(milliseconds: halfSecond * 500);
      controller.sync(
        confirmedPosition: Duration(milliseconds: halfSecond * 1500),
        playing: true,
        buffering: false,
        seeking: false,
        rate: 3,
      );
      controller.replaceEvents(events);
      expect(
        controller.frame().map((p) => p.event.id),
        halfSecond < 8
            ? ['scroll', 'top', 'bottom']
            : halfSecond < 16
            ? ['scroll']
            : <String>[],
      );
    }
    controller.sync(
      confirmedPosition: const Duration(seconds: 24),
      playing: true,
      buffering: false,
      seeking: false,
      rate: 6,
    );
    controller.replaceEvents(events);
    expect(controller.frame(), isEmpty);
  });

  test('lane spacing uses visual time when media time runs faster', () {
    var now = Duration.zero;
    final controller = DanmakuController(monotonicNow: () => now);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 48);
    controller.replaceEvents(const [
      DanmakuEvent(id: 'first', at: Duration.zero, text: 'first'),
      DanmakuEvent(id: 'too-close', at: Duration(seconds: 2), text: 'next'),
      DanmakuEvent(id: 'spaced', at: Duration(seconds: 6), text: 'next'),
    ]);
    controller.sync(
      confirmedPosition: Duration.zero,
      playing: true,
      buffering: false,
      seeking: false,
      rate: 3,
    );
    controller.frame();
    for (var halfSecond = 1; halfSecond <= 4; halfSecond++) {
      now = Duration(milliseconds: halfSecond * 500);
      controller.sync(
        confirmedPosition: Duration(milliseconds: halfSecond * 1500),
        playing: true,
        buffering: false,
        seeking: false,
        rate: 3,
      );
      expect(
        controller.frame().map((p) => p.event.id),
        halfSecond < 4 ? ['first'] : ['first', 'spaced'],
      );
    }
    expect(controller.dropped, 1);
  });

  test('seek rebuilds the rate-adjusted history and permits rewind replay', () {
    final controller = DanmakuController(monotonicNow: () => Duration.zero);
    addTearDown(controller.dispose);
    controller.setViewport(width: 600, height: 384);
    controller.sync(
      confirmedPosition: Duration.zero,
      playing: false,
      buffering: false,
      seeking: false,
      rate: 3,
    );
    controller.replaceEvents(const [
      DanmakuEvent(id: 'scroll', at: Duration.zero, text: 'scroll'),
      DanmakuEvent(id: 'future', at: Duration(seconds: 30), text: 'future'),
    ]);
    controller.seekConfirmed(const Duration(seconds: 18));
    expect(controller.frame().single.x, closeTo(600 - 744 * 6 / 8, .001));
    controller.seekConfirmed(Duration.zero);
    expect(controller.frame().single.x, 600);
    expect(controller.pendingCount, 1);
  });
}
