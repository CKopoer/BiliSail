import 'dart:async';

import 'package:bili_player/src/fvp_surface_preroll.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'direct setup waits for a real image and native pause before resume seek',
    () async {
      final image = Completer<bool>();
      final paused = Completer<void>();
      final calls = <String>[];
      final opening = confirmFvpDirectSurface(
        startVideo: () => calls.add('video-only'),
        firstFrame: () => image.future,
        pauseAndWait: () {
          calls.add('pause');
          return paused.future;
        },
        checkActive: () {},
        seek: () async {
          calls.add('seek:5000');
          return 5000;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['video-only']);
      image.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['video-only', 'pause']);
      paused.complete();
      expect(await opening, true);
      expect(calls, ['video-only', 'pause', 'seek:5000']);
    },
  );

  test(
    'live direct setup pauses after its image without a network seek',
    () async {
      final calls = <String>[];
      expect(
        await confirmFvpDirectSurface(
          startVideo: () => calls.add('video-only'),
          firstFrame: () async => true,
          pauseAndWait: () async => calls.add('pause'),
          checkActive: () {},
        ),
        true,
      );
      expect(calls, ['video-only', 'pause']);
    },
  );

  for (final failed in ['image', 'seek']) {
    test(
      'direct setup propagates a failed $failed and leaves video paused',
      () async {
        var playing = false;
        var seeks = 0;
        expect(
          await confirmFvpDirectSurface(
            startVideo: () => playing = true,
            firstFrame: () async => failed != 'image',
            pauseAndWait: () async => playing = false,
            checkActive: () {},
            seek: () async {
              expect(playing, false);
              seeks++;
              return -3;
            },
          ),
          false,
        );
        expect(playing, false);
        expect(seeks, failed == 'image' ? 0 : 1);
      },
    );
  }

  for (final boundary in ['image', 'pause', 'seek']) {
    test(
      'cancellation during $boundary cannot publish a ready direct Surface',
      () async {
        var active = true;
        var playing = false;
        var seeks = 0;
        await expectLater(
          confirmFvpDirectSurface(
            startVideo: () => playing = true,
            firstFrame: () async {
              if (boundary == 'image') active = false;
              return true;
            },
            pauseAndWait: () async {
              playing = false;
              if (boundary == 'pause') active = false;
            },
            checkActive: () {
              if (!active) throw StateError('cancelled');
            },
            seek: () async {
              expect(playing, false);
              seeks++;
              active = false;
              return 5000;
            },
          ),
          throwsStateError,
        );
        expect(playing, false);
        expect(seeks, boundary == 'seek' ? 1 : 0);
      },
    );
  }

  test(
    'a frame error pauses the video pipe and preserves the failure',
    () async {
      final error = StateError('native image failed');
      var playing = false;
      await expectLater(
        confirmFvpDirectSurface(
          startVideo: () => playing = true,
          firstFrame: () => Future.error(error),
          pauseAndWait: () async => playing = false,
          checkActive: () {},
          seek: () async => fail('cannot seek after an image error'),
        ),
        throwsA(same(error)),
      );
      expect(playing, false);
    },
  );

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
}
