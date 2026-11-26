import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:bilisail/core/platform/playback_audio_focus.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final android in [false, true]) {
    test(
      'OS interruption mapping and headphone removal, android=$android',
      () async {
        final session = _AudioSession();
        final focus = PlaybackAudioFocus.fromSession(session, android: android);
        final received = <PlaybackAudioEvent>[];
        final listener = received.add;
        expect(await focus.request(listener), isTrue);
        for (final (begin, type) in [
          (true, AudioInterruptionType.unknown),
          (false, AudioInterruptionType.pause),
          (true, AudioInterruptionType.pause),
          (false, AudioInterruptionType.unknown),
          (true, AudioInterruptionType.duck),
          (false, AudioInterruptionType.duck),
        ]) {
          session.interruptions.add(AudioInterruptionEvent(begin, type));
        }
        session.noisy.add(null);
        await Future<void>.delayed(Duration.zero);
        expect(received, [
          android ? PlaybackAudioEvent.stop : PlaybackAudioEvent.interrupt,
          PlaybackAudioEvent.resume,
          PlaybackAudioEvent.interrupt,
          PlaybackAudioEvent.endWithoutResume,
          PlaybackAudioEvent.duck,
          PlaybackAudioEvent.unduck,
          PlaybackAudioEvent.stop,
        ]);
        await focus.release(listener);
        expect(session.activations, [true, false]);
        expect(session.interruptions.hasListener, isFalse);
        expect(session.noisy.hasListener, isFalse);
        await session.interruptions.close();
        await session.noisy.close();
      },
    );
  }

  test('loss during activation invalidates a late grant', () async {
    final events = StreamController<PlaybackAudioEvent>.broadcast(sync: true);
    final started = Completer<void>();
    final grant = Completer<bool>();
    final focus = PlaybackAudioFocus(
      events: events.stream,
      setActive: (active) async {
        if (!active) return true;
        started.complete();
        return grant.future;
      },
    );
    final listener = <PlaybackAudioEvent>[].add;
    final pending = focus.request(listener);
    await started.future;
    events.add(PlaybackAudioEvent.interrupt);
    grant.complete(true);
    expect(await pending, isFalse);
    await focus.release(listener);
    await events.close();
  });
}

class _AudioSession extends Fake implements AudioSession {
  final interruptions = StreamController<AudioInterruptionEvent>.broadcast(
    sync: true,
  );
  final noisy = StreamController<void>.broadcast(sync: true);
  final activations = <bool>[];
  @override
  Stream<AudioInterruptionEvent> get interruptionEventStream =>
      interruptions.stream;
  @override
  Stream<void> get becomingNoisyEventStream => noisy.stream;
  @override
  Future<bool> setActive(
    bool active, {
    AVAudioSessionSetActiveOptions? avAudioSessionSetActiveOptions,
    AndroidAudioFocusGainType? androidAudioFocusGainType,
    AndroidAudioAttributes? androidAudioAttributes,
    bool? androidWillPauseWhenDucked,
    AudioSessionConfiguration fallbackConfiguration =
        const AudioSessionConfiguration.music(),
  }) async {
    activations.add(active);
    return true;
  }
}
