import 'dart:async';

import 'package:bili_player/src/fvp_surface_preroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a pre-binding renderer success cannot confirm the direct Surface',
    () async {
      final frame = FvpFirstVideoFrame()..rendered(true);
      var ready = false;
      final waiting = frame
          .ready(directSurface: true)
          .then((_) => ready = true);
      await Future<void>.delayed(Duration.zero);
      expect(ready, false);
      frame.surfaceConsumed();
      await waiting;
      expect(ready, true);
    },
  );

  test(
    'renderer failure and duplicate callbacks do not poison direct output',
    () async {
      final frame = FvpFirstVideoFrame()..rendered(false);
      frame.surfaceConsumed();
      frame.surfaceConsumed();
      frame.rendered(true);
      expect(await frame.ready(directSurface: true), true);
      expect(await frame.ready(directSurface: false), false);
    },
  );

  test('Surface consumption cannot replace renderer readiness', () async {
    final frame = FvpFirstVideoFrame()..surfaceConsumed();
    var ready = false;
    final waiting = frame.ready(directSurface: false).then((_) => ready = true);
    await Future<void>.delayed(Duration.zero);
    expect(ready, false);
    frame.rendered(true);
    await waiting;
    expect(ready, true);
  });

  test('seek waits for a real frame and acknowledged native pause', () async {
    final frame = Completer<bool>();
    final paused = Completer<void>();
    final calls = <String>[];
    final waiting = confirmFvpSurfacePreroll(
      firstFrame: frame.future,
      pauseAndWait: () {
        calls.add('pause');
        return paused.future;
      },
      seek: () async {
        calls.add('seek');
        return 5000;
      },
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, isEmpty);
    frame.complete(true);
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['pause']);
    paused.complete();
    expect(await waiting, true);
    expect(calls, ['pause', 'seek']);
  });

  test('live preroll never seeks', () async {
    expect(
      await confirmFvpSurfacePreroll(
        firstFrame: Future.value(true),
        pauseAndWait: () async => fail('live preroll must not seek'),
      ),
      true,
    );
  });

  test('failed or cancelled readiness never pauses or seeks', () async {
    Future<void> pause() async => fail('readiness did not succeed');
    Future<int> seek() async => fail('readiness did not succeed');
    expect(
      await confirmFvpSurfacePreroll(
        firstFrame: Future.value(false),
        pauseAndWait: pause,
        seek: seek,
      ),
      false,
    );
    await expectLater(
      confirmFvpSurfacePreroll(
        firstFrame: Future.error(StateError('cancelled')),
        pauseAndWait: pause,
        seek: seek,
      ),
      throwsStateError,
    );
  });

  test('native pause cancellation and seek rejection propagate', () async {
    await expectLater(
      confirmFvpSurfacePreroll(
        firstFrame: Future.value(true),
        pauseAndWait: () async => throw StateError('cancelled'),
        seek: () async => fail('pause did not finish'),
      ),
      throwsStateError,
    );
    expect(
      await confirmFvpSurfacePreroll(
        firstFrame: Future.value(true),
        pauseAndWait: () async {},
        seek: () async => -1,
      ),
      false,
    );
  });
}
