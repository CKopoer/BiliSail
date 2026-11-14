import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_rebuffer_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PlaybackSnapshot snapshot;
  late NativeRebufferMonitor monitor;
  late List<Duration> failures;
  var now = Duration.zero;
  setUp(() {
    now = Duration.zero;
    failures = [];
    snapshot = const PlaybackSnapshot(
      phase: PlaybackPhase.playing,
      generation: 1,
      desiredPlaying: true,
      position: Duration(seconds: 10),
      buffered: Duration(seconds: 12),
      duration: Duration(minutes: 10),
      rate: 2,
    );
    monitor = NativeRebufferMonitor(
      snapshot: () => snapshot,
      onStalled: failures.add,
      now: () => now,
    );
    monitor.update();
  });
  tearDown(() => monitor.dispose());
  void wait(Duration duration, {Duration progress = Duration.zero}) {
    now += duration;
    snapshot = snapshot.copyWith(position: snapshot.position + progress);
    monitor.update();
  }

  void episode({int seconds = 6, bool advances = false}) {
    monitor.cachePauseChanged(true);
    wait(
      Duration(seconds: seconds),
      progress: advances ? Duration(seconds: seconds * 2) : Duration.zero,
    );
    monitor.cachePauseChanged(false);
  }

  test('small refills and 2x short playback do not erase repeated stalls', () {
    episode();
    expect(failures, isEmpty);
    wait(const Duration(seconds: 2), progress: const Duration(seconds: 4));
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 16));
    monitor.update();
    episode();
    expect(failures, [const Duration(seconds: 12)]);
    episode();
    expect(failures, hasLength(1));
  });

  testWidgets('second frozen pause recovers before it ends without errors', (
    tester,
  ) async {
    episode(seconds: 10);
    wait(const Duration(seconds: 2), progress: const Duration(seconds: 4));
    monitor.cachePauseChanged(true);
    now += const Duration(seconds: 2);
    await tester.pump(const Duration(seconds: 2));
    expect(failures, [const Duration(seconds: 12)]);
  });

  test('one long pause retains its original connection', () {
    episode(seconds: 40);
    expect(failures, isEmpty);
  });

  test('short pulses and advancing native flags cannot trigger recovery', () {
    for (var i = 0; i < 5; i++) {
      episode(advances: true);
    }
    for (var i = 0; i < 6; i++) {
      monitor.cachePauseChanged(true);
      wait(const Duration(milliseconds: 300));
      monitor.cachePauseChanged(false);
    }
    expect(failures, isEmpty);
  });

  test('SDK buffering without native cache pauses cannot trigger recovery', () {
    for (var i = 0; i < 4; i++) {
      snapshot = snapshot.copyWith(isBuffering: true);
      wait(const Duration(seconds: 10));
      snapshot = snapshot.copyWith(isBuffering: false);
      monitor.update();
    }
    expect(failures, isEmpty);
  });

  test('confirmed healthy playback clears old episodes at the actual rate', () {
    episode();
    wait(const Duration(seconds: 10), progress: const Duration(seconds: 20));
    episode();
    expect(failures, isEmpty);
  });

  test('quiet frozen time does not count as healthy playback', () {
    episode();
    wait(const Duration(seconds: 11));
    episode();
    expect(failures, hasLength(1));
  });

  test('expired episodes are evicted', () {
    episode();
    wait(const Duration(seconds: 91));
    episode();
    expect(failures, isEmpty);
  });

  for (final action in ['pause', 'seek', 'generation', 'opening', 'ended']) {
    testWidgets('$action cancels a pending check and clears evidence', (
      tester,
    ) async {
      episode(seconds: 10);
      monitor.cachePauseChanged(true);
      final before = snapshot;
      snapshot = switch (action) {
        'pause' => snapshot.copyWith(desiredPlaying: false),
        'seek' => snapshot.copyWith(isSeeking: true),
        'generation' => snapshot.copyWith(generation: 2),
        'opening' => snapshot.copyWith(phase: PlaybackPhase.opening),
        _ => snapshot.copyWith(phase: PlaybackPhase.ended),
      };
      monitor.update();
      now += const Duration(seconds: 20);
      await tester.pump(const Duration(seconds: 20));
      snapshot = before.copyWith(generation: snapshot.generation);
      episode();
      expect(failures, isEmpty);
    });
  }

  testWidgets('dispose cancels timers and late native notifications', (
    tester,
  ) async {
    episode(seconds: 10);
    monitor.cachePauseChanged(true);
    monitor.dispose();
    now += const Duration(seconds: 20);
    await tester.pump(const Duration(seconds: 20));
    monitor.cachePauseChanged(false);
    expect(failures, isEmpty);
  });
}
