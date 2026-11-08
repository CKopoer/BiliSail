import 'dart:async';

import 'package:bili_player/src/fvp_seek.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'audio target stays muted until its native pause is acknowledged',
    () async {
      final running = Completer<void>();
      final decoded = Completer<int>();
      final paused = Completer<bool>();
      final calls = <String>[];
      final seeking = seekFvpAudioTarget(
        isCancelled: () => false,
        setMuted: (muted) => calls.add('mute:$muted'),
        playAndWait: () {
          calls.add('play');
          return running.future;
        },
        seek: () {
          calls.add('seek');
          return decoded.future;
        },
        pauseAndConfirm: () {
          calls.add('pause');
          return paused.future;
        },
      );
      expect(calls, ['mute:true', 'play']);
      running.complete();
      await Future<void>.delayed(Duration.zero);
      expect(calls.last, 'seek');
      decoded.complete(9365);
      await Future<void>.delayed(Duration.zero);
      expect(calls.last, 'pause');
      expect(calls, isNot(contains('mute:false')));
      paused.complete(true);
      expect(await seeking, 9365);
      expect(calls.last, 'mute:false');
    },
  );

  for (final boundary in ['play', 'seek', 'pause']) {
    test(
      'retired audio target at $boundary never restores old volume',
      () async {
        var cancelled = false;
        var seeks = 0;
        final muted = <bool>[];
        final result = await seekFvpAudioTarget(
          isCancelled: () => cancelled,
          setMuted: muted.add,
          playAndWait: () async {
            if (boundary == 'play') cancelled = true;
          },
          seek: () async {
            seeks++;
            if (boundary == 'seek') cancelled = true;
            return 9365;
          },
          pauseAndConfirm: () async {
            if (boundary == 'pause') cancelled = true;
            return true;
          },
        );
        expect(result, -2);
        expect(muted, [true]);
        expect(seeks, boundary == 'play' ? 0 : 1);
      },
    );
  }

  test('unconfirmed audio pause fails with the pipe still muted', () async {
    final muted = <bool>[];
    expect(
      await seekFvpAudioTarget(
        isCancelled: () => false,
        setMuted: muted.add,
        playAndWait: () async {},
        seek: () async => 9365,
        pauseAndConfirm: () async => false,
      ),
      -3,
    );
    expect(muted, [true]);
  });

  test('audio decode error pauses before restoring volume', () async {
    final calls = <String>[];
    await expectLater(
      seekFvpAudioTarget(
        isCancelled: () => false,
        setMuted: (muted) => calls.add('mute:$muted'),
        playAndWait: () async {},
        seek: () async => throw StateError('decode failed'),
        pauseAndConfirm: () async {
          calls.add('pause');
          return true;
        },
      ),
      throwsStateError,
    );
    expect(calls, ['mute:true', 'pause', 'mute:false']);
  });

  for (final code in [-2, -3, -8]) {
    test('restores an EOF race ($code) before confirming the target', () async {
      final paused = Completer<bool>();
      final calls = <String>[];
      var seeks = 0;
      final result = seekFvpTarget(
        isCancelled: () => false,
        needsPrepare: () => false,
        prepare: () async {
          calls.add('prepare');
          return 9000;
        },
        pauseAndWait: () {
          calls.add('pause');
          return seeks == 0 ? Future.value(true) : paused.future;
        },
        seek: () async {
          calls.add('seek');
          return seeks++ == 0 ? code : 9375;
        },
      );
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['pause', 'seek', 'prepare', 'pause']);
      paused.complete(true);
      expect(await result, 9375);
      expect(calls.last, 'seek');
    });
  }

  test(
    'EOF during pause restores the source instead of waiting forever',
    () async {
      var prepared = false;
      expect(
        await seekFvpTarget(
          isCancelled: () => false,
          needsPrepare: () => false,
          prepare: () async {
            prepared = true;
            return 2000;
          },
          pauseAndWait: () async => prepared,
          seek: () async => 2000,
        ),
        2000,
      );
      expect(prepared, true);
    },
  );

  test(
    'an EOF during a restored seek receives a fresh bounded prepare',
    () async {
      var preparations = 0;
      var seeks = 0;
      expect(
        await seekFvpTarget(
          isCancelled: () => false,
          needsPrepare: () => true,
          prepare: () async {
            preparations++;
            return 2000;
          },
          pauseAndWait: () async => true,
          seek: () async => seeks++ == 0 ? -3 : 2000,
        ),
        2000,
      );
      expect(preparations, 2);
      expect(seeks, 2);
    },
  );

  for (final boundary in ['prepare', 'pause', 'seek']) {
    test(
      'superseding during $boundary cannot issue another native command',
      () async {
        var cancelled = false;
        var seeks = 0;
        expect(
          await seekFvpTarget(
            isCancelled: () => cancelled,
            needsPrepare: () => boundary == 'prepare',
            prepare: () async {
              cancelled = true;
              return 2000;
            },
            pauseAndWait: () async {
              if (boundary == 'pause') cancelled = true;
              return true;
            },
            seek: () async {
              seeks++;
              cancelled = true;
              return -3;
            },
          ),
          -2,
        );
        expect(seeks, boundary == 'seek' ? 1 : 0);
      },
    );
  }

  test('a rejected native seek restores the source once', () async {
    var seeks = 0;
    var preparations = 0;
    expect(
      await seekFvpTarget(
        isCancelled: () => false,
        needsPrepare: () => false,
        prepare: () async {
          preparations++;
          return 2000;
        },
        pauseAndWait: () async => true,
        seek: () async => seeks++ == 0 ? -10 : 2000,
      ),
      2000,
    );
    expect(preparations, 1);
    expect(seeks, 2);
  });

  test('an interrupted HTTP prepare is retired and retried once', () async {
    var preparations = 0;
    expect(
      await seekFvpTarget(
        isCancelled: () => false,
        needsPrepare: () => true,
        prepare: () async => preparations++ == 0 ? -8 : 325000,
        pauseAndWait: () async => true,
        seek: () async => 325000,
      ),
      325000,
    );
    expect(preparations, 2);
  });

  for (final code in [-1, -2, -3, -4, -8, -10]) {
    test('failure $code has a bounded recovery budget', () async {
      var preparations = 0;
      var seeks = 0;
      expect(
        await seekFvpTarget(
          isCancelled: () => false,
          needsPrepare: () => false,
          prepare: () async {
            preparations++;
            return 2000;
          },
          pauseAndWait: () async => true,
          seek: () async {
            seeks++;
            return code;
          },
        ),
        code,
      );
      expect(preparations, {-2, -3, -8, -10}.contains(code) ? 1 : 0);
      expect(seeks, preparations + 1);
    });
  }
}
