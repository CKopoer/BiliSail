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

  for (final track in ['video', 'audio']) {
    test('a $track boundary mismatch while buffering waits for refill', () {
      health.update(
        playing,
        Duration.zero,
        paired: true,
        audioPosition: playing.position,
      );
      // At an underrun the demuxer endpoint and cached audio clock can trail
      // the final position sample. Neither proves that a track reached EOF.
      final buffering = playing.copyWith(
        phase: PlaybackPhase.buffering,
        isBuffering: true,
        position: const Duration(seconds: 11),
        buffered: Duration(seconds: track == 'video' ? 10 : 30),
      );
      for (final second in [1, 10, 29]) {
        expect(
          health.update(
            buffering,
            Duration(seconds: second),
            paired: true,
            audioPosition: Duration(seconds: track == 'audio' ? 10 : 11),
          ),
          isNull,
        );
      }
      expect(
        health.update(
          playing.copyWith(
            position: const Duration(seconds: 12),
            buffered: const Duration(seconds: 30),
          ),
          const Duration(seconds: 29),
          paired: true,
          audioPosition: const Duration(seconds: 12),
        ),
        isNull,
      );
    });
  }

  test('paired buffering with lagging track clocks still has a deadline', () {
    final buffering = playing.copyWith(
      phase: PlaybackPhase.buffering,
      isBuffering: true,
      position: const Duration(seconds: 11),
    );
    health.update(
      buffering,
      Duration.zero,
      paired: true,
      audioPosition: const Duration(seconds: 10),
    );
    final result = health.update(
      buffering,
      NativePlaybackHealth.bufferingTimeout,
      paired: true,
      audioPosition: const Duration(seconds: 10),
    );
    expect(result?.kind, PlayerFailureKind.nativePlayback);
    expect(result?.reason, PlaybackStallReason.playbackClock);
    expect(result?.stalledFor, NativePlaybackHealth.bufferingTimeout);
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
        final deadline = buffering
            ? NativePlaybackHealth.bufferingTimeout
            : NativePlaybackHealth.stallTimeout;
        health.update(snapshot, Duration.zero, paired: false);
        expect(
          health.update(
            snapshot,
            deadline - const Duration(milliseconds: 1),
            paired: false,
          ),
          isNull,
        );
        expect(
          health.update(snapshot, deadline, paired: false)?.kind,
          PlayerFailureKind.nativePlayback,
        );
      },
    );
  }

  test(
    'buffer refill has time to recover but events cannot renew its budget',
    () {
      final buffering = playing.copyWith(
        isBuffering: true,
        phase: PlaybackPhase.buffering,
      );
      health.update(buffering, Duration.zero, paired: false);
      for (var i = 1; i < 30; i++) {
        expect(
          health.update(
            buffering.copyWith(
              buffered: Duration(milliseconds: 10000 + i * 50),
            ),
            Duration(seconds: i),
            paired: false,
          ),
          isNull,
        );
      }
      expect(
        health
            .update(buffering, const Duration(seconds: 30), paired: false)
            ?.kind,
        PlayerFailureKind.nativePlayback,
      );
      expect(
        health.update(
          playing.copyWith(position: const Duration(seconds: 11)),
          const Duration(seconds: 31),
          paired: false,
        ),
        isNull,
      );
    },
  );

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

  for (final rate in [0.25, 1.0, 4.0, 8.0]) {
    test('cached clocks permit normal progress at rate $rate', () {
      for (var i = 0; i < 80; i++) {
        final position = Duration(
          milliseconds: (10000 + i * 250 * rate).round(),
        );
        final cached = position - Duration(milliseconds: (250 * rate).round());
        expect(
          health.update(
            playing.copyWith(
              position: position,
              rate: rate,
              buffered: const Duration(seconds: 300),
              duration: const Duration(seconds: 600),
            ),
            Duration(milliseconds: i * 250),
            paired: true,
            audioPosition: cached,
          ),
          isNull,
        );
      }
    });
  }

  test('ample and growing buffers cannot hide a frozen playback clock', () {
    for (var i = 0; i <= 2; i++) {
      final result = health.update(
        playing.copyWith(buffered: Duration(seconds: 40 + i)),
        Duration(seconds: i),
        paired: true,
        audioPosition: playing.position,
      );
      if (i < 2) {
        expect(result, isNull);
      } else {
        expect(result?.kind, PlayerFailureKind.nativePlayback);
        expect(result?.position, playing.position);
      }
    }
  });

  test('small position oscillations cannot renew a stalled clock deadline', () {
    for (var i = 0; i <= 8; i++) {
      final result = health.update(
        playing.copyWith(
          position: Duration(milliseconds: 10000 + (i.isEven ? 0 : 10)),
          buffered: const Duration(seconds: 50),
        ),
        Duration(milliseconds: i * 250),
        paired: false,
      );
      if (i < 8) {
        expect(result, isNull);
      } else {
        expect(result?.kind, PlayerFailureKind.nativePlayback);
      }
    }
  });

  test('buffer refill grants time to resume the silent playback clock', () {
    final snapshot = playing.copyWith(buffered: const Duration(seconds: 50));
    health.update(snapshot, Duration.zero, paired: false);
    expect(
      health.update(
        snapshot.copyWith(isBuffering: true),
        const Duration(seconds: 20),
        paired: false,
      ),
      isNull,
    );
    expect(
      health.update(snapshot, const Duration(seconds: 21), paired: false),
      isNull,
    );
    expect(
      health.update(
        snapshot.copyWith(position: const Duration(seconds: 11)),
        const Duration(seconds: 22),
        paired: false,
      ),
      isNull,
    );
  });

  test('buffering flag oscillations cannot keep renewing resume grace', () {
    final snapshot = playing.copyWith(buffered: const Duration(seconds: 50));
    health.update(snapshot, Duration.zero, paired: false);
    for (var second = 1; second <= 4; second++) {
      final result = health.update(
        snapshot.copyWith(isBuffering: second.isOdd),
        Duration(seconds: second),
        paired: false,
      );
      if (second < 4) {
        expect(result, isNull);
      } else {
        expect(result?.kind, PlayerFailureKind.nativePlayback);
      }
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
