import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/dash_video_continuity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    phase: PlaybackPhase.playing,
    generation: 1,
    desiredPlaying: true,
    duration: Duration(seconds: 60),
    position: Duration(seconds: 11),
    buffered: Duration(seconds: 10),
  );
  late DashVideoContinuity monitor;
  setUp(() => monitor = DashVideoContinuity());
  Duration? sample(int milliseconds, {PlaybackSnapshot snapshot = playing}) =>
      monitor.update(snapshot, Duration(milliseconds: milliseconds));

  test(
    'audio progress beyond stalled video buffer reaches bounded failure',
    () {
      expect(sample(0), isNull);
      expect(sample(100), isNull);
      expect(sample(1000), isNull);
      expect(
        sample(
          1100,
          snapshot: playing.copyWith(position: const Duration(seconds: 13)),
        ),
        const Duration(seconds: 10),
      );
    },
  );

  for (final snapshot in [
    playing.copyWith(phase: PlaybackPhase.opening),
    playing.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
    playing.copyWith(desiredPlaying: false),
    playing.copyWith(isSeeking: true),
    playing.copyWith(isBuffering: true),
    playing.copyWith(phase: PlaybackPhase.ended),
    playing.copyWith(phase: PlaybackPhase.failed),
    playing.copyWith(buffered: Duration.zero),
    playing.copyWith(buffered: const Duration(seconds: 30)),
    playing.copyWith(duration: const Duration(seconds: 11)),
  ]) {
    test(
      'inactive, unknown, buffered or ending media does not fail: $snapshot',
      () {
        sample(0);
        sample(100);
        expect(sample(2000, snapshot: snapshot), isNull);
        expect(sample(3000, snapshot: snapshot), isNull);
      },
    );
  }

  test('refilling or seeking resets the grace period', () {
    sample(0);
    sample(100);
    expect(
      sample(
        1500,
        snapshot: playing.copyWith(
          buffered: const Duration(milliseconds: 10500),
        ),
      ),
      isNull,
    );
    expect(sample(2000), isNull);
    expect(sample(2500), isNull);
    expect(sample(3000, snapshot: playing.copyWith(isSeeking: true)), isNull);
    expect(
      sample(
        3500,
        snapshot: playing.copyWith(position: const Duration(seconds: 9)),
      ),
      isNull,
    );
    expect(sample(4000), isNull);
    expect(sample(4500), isNull);
    expect(sample(5000), const Duration(seconds: 10));
  });

  test('a replacement source or reset cannot inherit an interruption', () {
    sample(0);
    sample(100);
    expect(sample(2000, snapshot: playing.copyWith(generation: 2)), isNull);
    monitor.reset();
    expect(sample(4000), isNull);
    expect(sample(4100), isNull);
    expect(sample(5000), isNull);
    expect(sample(5100), const Duration(seconds: 10));
  });
}
