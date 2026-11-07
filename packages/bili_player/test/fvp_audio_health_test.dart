import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_audio_health.dart';
import 'package:bili_player/src/native_playback_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    phase: PlaybackPhase.playing,
    generation: 1,
    desiredPlaying: true,
    duration: Duration(minutes: 1),
    position: Duration(seconds: 10),
    buffered: Duration(seconds: 50),
  );
  late FvpAudioHealth health;
  setUp(() => health = FvpAudioHealth());

  test('advancing video cannot hide audio that stops halfway', () {
    health.update(playing, Duration.zero, 100);
    for (var i = 1; i < 8; i++) {
      expect(
        health.update(
          playing.copyWith(position: Duration(seconds: 10 + i)),
          Duration(seconds: i),
          100,
        ),
        isNull,
      );
    }
    final failure = health.update(
      playing.copyWith(position: const Duration(seconds: 18)),
      NativePlaybackHealth.stallTimeout,
      100,
    );
    expect(failure?.reason, PlaybackStallReason.audioFrames);
    expect(failure?.position, const Duration(seconds: 18));
    expect(failure?.stalledFor, NativePlaybackHealth.stallTimeout);
  });

  for (final rate in [.25, 1.0, 4.0, 8.0]) {
    test('decoded silence and muted audio remain healthy at $rate', () {
      for (var i = 0; i < 100; i++) {
        expect(
          health.update(
            playing.copyWith(rate: rate, volume: 0),
            Duration(milliseconds: 250 * i),
            i,
          ),
          isNull,
        );
      }
    });
  }

  for (final waiting in [
    playing.copyWith(desiredPlaying: false, phase: PlaybackPhase.paused),
    playing.copyWith(isSeeking: true),
    playing.copyWith(isBuffering: true, phase: PlaybackPhase.buffering),
  ]) {
    test(
      'pause, seek, and refill give audio a fresh progress window ($waiting)',
      () {
        health.update(playing, Duration.zero, 100);
        expect(
          health.update(waiting, const Duration(seconds: 30), 100),
          isNull,
        );
        expect(
          health.update(playing, const Duration(seconds: 31), 101),
          isNull,
        );
        expect(
          health.update(playing, const Duration(seconds: 38), 101),
          isNull,
        );
        expect(
          health.update(playing, const Duration(seconds: 39), 101),
          isNotNull,
        );
      },
    );
  }

  test(
    'source changes, counter restarts, and explicit reset retire old stalls',
    () {
      health.update(playing, Duration.zero, 100);
      final next = playing.copyWith(generation: 2);
      expect(health.update(next, const Duration(seconds: 30), 0), isNull);
      expect(health.update(next, const Duration(seconds: 37), 0), isNull);
      expect(health.update(next, const Duration(seconds: 38), 1), isNull);
      health.reset();
      expect(health.update(next, const Duration(seconds: 60), 1), isNull);
    },
  );

  test('normal audio tail does not restart a nearly complete video', () {
    health.update(playing, Duration.zero, 100);
    expect(
      health.update(
        playing.copyWith(position: const Duration(milliseconds: 59700)),
        const Duration(seconds: 20),
        100,
      ),
      isNull,
    );
  });
}
