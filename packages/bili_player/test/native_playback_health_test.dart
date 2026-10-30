import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_playback_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    phase: PlaybackPhase.playing,
    generation: 1,
    desiredPlaying: true,
    duration: Duration(seconds: 60),
    position: Duration(seconds: 10),
    buffered: Duration(seconds: 10),
  );
  late NativePlaybackHealth health;
  setUp(() => health = NativePlaybackHealth());

  test('video EOF pauses the surviving audio within one sample', () {
    health.update(playing, Duration.zero, paired: true);
    final result = health.update(
      playing.copyWith(position: const Duration(milliseconds: 10300)),
      const Duration(milliseconds: 300),
      paired: true,
    );
    expect(result?.kind, PlayerFailureKind.videoInterrupted);
    expect(result?.position, const Duration(seconds: 10));
  });

  for (final missing in [false, true]) {
    test(
      'external audio EOF cannot be hidden by video progress ($missing)',
      () {
        final buffered = playing.copyWith(
          buffered: const Duration(seconds: 50),
        );
        health.update(
          buffered,
          Duration.zero,
          paired: true,
          audioPosition: const Duration(seconds: 10),
        );
        final result = health.update(
          buffered.copyWith(position: const Duration(seconds: 11)),
          const Duration(seconds: 1),
          paired: true,
          audioPosition: missing ? null : const Duration(seconds: 10),
        );
        expect(result?.kind, PlayerFailureKind.nativePlayback);
        expect(result?.position, const Duration(seconds: 10));
      },
    );
  }

  for (final buffering in [false, true]) {
    test(
      'silent stall has a deadline without any native error ($buffering)',
      () {
        final snapshot = playing.copyWith(
          isBuffering: buffering,
          phase: buffering ? PlaybackPhase.buffering : PlaybackPhase.playing,
        );
        health.update(snapshot, Duration.zero, paired: false);
        expect(
          health.update(snapshot, const Duration(seconds: 7), paired: false),
          isNull,
        );
        expect(
          health
              .update(snapshot, const Duration(seconds: 8), paired: false)
              ?.kind,
          PlayerFailureKind.nativePlayback,
        );
      },
    );
  }

  test('normal progress and a refilling buffer do not fail', () {
    for (var i = 0; i < 100; i++) {
      final position = Duration(seconds: i);
      expect(
        health.update(
          playing.copyWith(
            position: position,
            duration: const Duration(seconds: 200),
            buffered: position + const Duration(seconds: 5),
          ),
          position,
          paired: true,
          audioPosition: position,
        ),
        isNull,
      );
    }
  });

  for (final snapshot in [
    playing.copyWith(phase: PlaybackPhase.opening),
    playing.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
    playing.copyWith(desiredPlaying: false),
    playing.copyWith(isSeeking: true),
    playing.copyWith(phase: PlaybackPhase.ended),
    playing.copyWith(phase: PlaybackPhase.failed),
  ]) {
    test('inactive state does not fail: ${snapshot.phase}', () {
      health.update(playing, Duration.zero, paired: true);
      expect(
        health.update(snapshot, const Duration(seconds: 20), paired: true),
        isNull,
      );
    });
  }

  test('normal video tail and unknown buffer do not imply premature EOF', () {
    for (final buffer in [Duration.zero, const Duration(milliseconds: 59800)]) {
      health.reset();
      final snapshot = playing.copyWith(
        buffered: buffer,
        position: const Duration(milliseconds: 59900),
      );
      health.update(snapshot, Duration.zero, paired: true);
      expect(
        health.update(
          snapshot,
          const Duration(milliseconds: 250),
          paired: true,
        ),
        isNull,
      );
    }
  });

  test('an unknown duration cannot hide a single surviving track', () {
    final snapshot = playing.copyWith(duration: Duration.zero);
    health.update(snapshot, Duration.zero, paired: true);
    expect(
      health
          .update(
            snapshot.copyWith(position: const Duration(seconds: 11)),
            const Duration(seconds: 1),
            paired: true,
          )
          ?.kind,
      PlayerFailureKind.videoInterrupted,
    );
  });

  test(
    'negative device startup audio clocks do not become recovery positions',
    () {
      final snapshot = playing.copyWith(buffered: const Duration(seconds: 60));
      health.update(
        snapshot,
        Duration.zero,
        paired: true,
        audioPosition: const Duration(seconds: -1),
      );
      expect(
        health.update(
          snapshot,
          const Duration(milliseconds: 250),
          paired: true,
          audioPosition: const Duration(milliseconds: -500),
        ),
        isNull,
      );
    },
  );

  test(
    'seek, replacement and reset discard the old audio clock and deadline',
    () {
      health.update(
        playing,
        Duration.zero,
        paired: true,
        audioPosition: const Duration(seconds: 10),
      );
      for (final snapshot in [
        playing.copyWith(generation: 2, position: const Duration(seconds: 40)),
        playing.copyWith(position: const Duration(seconds: 2)),
      ]) {
        expect(
          health.update(snapshot, const Duration(seconds: 20), paired: true),
          isNull,
        );
      }
      health.reset();
      expect(
        health.update(playing, const Duration(seconds: 40), paired: true),
        isNull,
      );
    },
  );
}
