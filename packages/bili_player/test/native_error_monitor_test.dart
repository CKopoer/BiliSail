import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_error_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    phase: PlaybackPhase.playing,
    generation: 1,
    desiredPlaying: true,
    position: Duration(seconds: 10),
  );
  late NativeErrorMonitor monitor;
  late List<int> failures;
  late List<int> recoveries;
  setUp(() {
    failures = [];
    recoveries = [];
    monitor = NativeErrorMonitor(
      onStalled: failures.add,
      onRecovered: recoveries.add,
    );
  });
  tearDown(() => monitor.reset());

  testWidgets('native log while playback advances never becomes a failure', (
    tester,
  ) async {
    monitor.report(playing);
    await tester.pump(const Duration(seconds: 1));
    monitor.update(playing.copyWith(position: const Duration(seconds: 11)));
    await tester.pump(const Duration(seconds: 10));
    expect(failures, isEmpty);
    expect(recoveries, [1]);
  });

  testWidgets('repeated errors cannot postpone a stalled playback deadline', (
    tester,
  ) async {
    monitor.report(playing);
    await tester.pump(const Duration(seconds: 7));
    monitor.report(playing);
    await tester.pump(const Duration(seconds: 1));
    expect(failures, [1]);
    expect(recoveries, isEmpty);
  });

  testWidgets('paused intent defers checking until playback resumes', (
    tester,
  ) async {
    monitor.report(playing);
    monitor.update(
      playing.copyWith(desiredPlaying: false, phase: PlaybackPhase.paused),
    );
    await tester.pump(const Duration(seconds: 20));
    expect(failures, isEmpty);
    monitor.update(playing);
    await tester.pump(const Duration(seconds: 8));
    expect(failures, [1]);
  });

  testWidgets('seek destination alone is not evidence of recovery', (
    tester,
  ) async {
    monitor.report(playing);
    monitor.update(playing.copyWith(isSeeking: true));
    await tester.pump(const Duration(seconds: 10));
    monitor.update(playing.copyWith(position: const Duration(seconds: 40)));
    expect(recoveries, isEmpty);
    await tester.pump(const Duration(seconds: 8));
    expect(failures, [1]);
  });

  testWidgets('source change, EOF and disposal cancel pending failure', (
    tester,
  ) async {
    monitor.report(playing);
    monitor.update(playing.copyWith(generation: 2));
    await tester.pump(const Duration(seconds: 10));
    monitor.report(playing);
    monitor.update(playing.copyWith(phase: PlaybackPhase.ended));
    await tester.pump(const Duration(seconds: 10));
    monitor.report(playing);
    monitor.reset();
    await tester.pump(const Duration(seconds: 10));
    expect(failures, isEmpty);
  });

  testWidgets('opening errors use the existing readiness deadline', (
    tester,
  ) async {
    monitor.report(playing.copyWith(phase: PlaybackPhase.opening));
    await tester.pump(const Duration(seconds: 10));
    expect(failures, isEmpty);
  });
}
