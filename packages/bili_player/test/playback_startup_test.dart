import 'dart:async';

import 'package:bili_player/src/playback_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('stays paused until both tracks and presentation confirm', () async {
    final audio = Completer<void>(), video = Completer<void>();
    final calls = <String>[];
    final starting = finishSynchronizedStartup(
      shouldPlay: () => true,
      play: () => calls.add('play'),
      pause: () => calls.add('pause'),
      confirmReady: () => Future.wait([audio.future, video.future]),
      applyVolume: () => calls.add('volume'),
      checkActive: () {},
    );
    await Future<void>.delayed(Duration.zero);
    audio.complete();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['pause']);
    video.complete();
    await starting;
    expect(calls, ['pause', 'volume', 'play']);
  });

  for (final outcome in ['cancel', 'failure', 'pause']) {
    test('$outcome during confirmation cannot release playing audio', () async {
      final ready = Completer<void>();
      final calls = <String>[];
      var playing = true, active = true;
      final starting = finishSynchronizedStartup(
        shouldPlay: () => playing,
        play: () => calls.add('play'),
        pause: () => calls.add('pause'),
        confirmReady: () => ready.future,
        applyVolume: () => calls.add('volume'),
        checkActive: () {
          if (!active) throw StateError('cancelled');
        },
      );
      final result = outcome == 'pause'
          ? starting
          : expectLater(starting, throwsStateError);
      await Future<void>.delayed(Duration.zero);
      if (outcome == 'cancel') active = false;
      if (outcome == 'pause') playing = false;
      if (outcome == 'failure') {
        ready.completeError(StateError('decode failed'));
      } else {
        ready.complete();
      }
      await result;
      expect(
        calls,
        outcome == 'pause' ? ['pause', 'volume', 'pause'] : ['pause'],
      );
    });
  }
}
