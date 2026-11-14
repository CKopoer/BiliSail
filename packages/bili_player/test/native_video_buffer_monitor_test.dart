import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_video_buffer_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var now = Duration.zero;
  late NativeVideoBufferMonitor monitor;
  late List<Duration> failures;
  late PlaybackSnapshot snapshot;
  setUp(() {
    now = Duration.zero;
    failures = [];
    snapshot = const PlaybackSnapshot(
      phase: PlaybackPhase.playing,
      generation: 1,
      desiredPlaying: true,
      rate: 1,
    );
    monitor = NativeVideoBufferMonitor(now: () => now, onStalled: failures.add);
    monitor.update(snapshot);
  });
  void stall({bool error = true, bool advances = false}) {
    snapshot = snapshot.copyWith(
      isBuffering: true,
      phase: PlaybackPhase.buffering,
    );
    monitor.update(snapshot);
    if (error) monitor.report(snapshot);
    now += const Duration(seconds: 2);
    snapshot = snapshot.copyWith(
      isBuffering: false,
      phase: PlaybackPhase.playing,
      position:
          snapshot.position +
          (advances ? const Duration(seconds: 2) : Duration.zero),
    );
    monitor.update(snapshot);
    snapshot = snapshot.copyWith(
      position: snapshot.position + const Duration(milliseconds: 100),
    );
    monitor.update(snapshot);
  }

  test('three error-associated frozen episodes recover once', () {
    stall();
    stall();
    expect(failures, isEmpty);
    stall();
    expect(failures, [const Duration(seconds: 6)]);
    stall();
    expect(failures, hasLength(1));
  });
  test('network waits and advancing buffering flags do not count as decoder stalls', () {
    for (var i = 0; i < 6; i++) {
      stall(error: false);
    }
    expect(failures, isEmpty);
    for (var i = 0; i < 6; i++) {
      stall(advances: true);
    }
    expect(failures, isEmpty);
  });
  test('isolated corrupt frames during advancing playback are recoverable', () {
    for (var i = 0; i < 40; i++) {
      monitor.report(snapshot);
      now += const Duration(seconds: 1);
      snapshot = snapshot.copyWith(position: now);
      monitor.update(snapshot);
    }
    expect(failures, isEmpty);
  });
  for (final boundary in ['pause', 'seek', 'generation']) {
    test('$boundary clears evidence from the previous playback intent', () {
      stall();
      stall();
      monitor.update(switch (boundary) {
        'pause' => snapshot.copyWith(
          desiredPlaying: false,
          phase: PlaybackPhase.paused,
        ),
        'seek' => snapshot.copyWith(isSeeking: true),
        _ => snapshot.copyWith(generation: 2),
      });
      if (boundary == 'generation') snapshot = snapshot.copyWith(generation: 2);
      monitor.update(snapshot);
      stall();
      expect(failures, isEmpty);
    });
  }
  test(
    'ten seconds of healthy playback and expired episodes clear the budget',
    () {
      stall();
      stall();
      now += const Duration(seconds: 10);
      snapshot = snapshot.copyWith(
        position: snapshot.position + const Duration(seconds: 10),
      );
      monitor.update(snapshot);
      stall();
      expect(failures, isEmpty);
      now += const Duration(seconds: 31);
      monitor.update(snapshot);
      stall();
      stall();
      expect(failures, isEmpty);
    },
  );
}
