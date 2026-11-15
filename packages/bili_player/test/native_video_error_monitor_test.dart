import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_video_error_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    generation: 1,
    phase: PlaybackPhase.playing,
    desiredPlaying: true,
    position: Duration(seconds: 352),
    buffered: Duration(seconds: 472),
    duration: Duration(seconds: 783),
    rate: 2,
  );
  final hardwareError = NativeErrorSummary.classify(
    'Error while decoding frame (hardware decoding)!',
    prefix: 'vd',
  );
  late PlaybackSnapshot snapshot;
  late NativeVideoErrorMonitor monitor;
  late int failures;
  setUp(() {
    snapshot = playing;
    failures = 0;
    monitor = NativeVideoErrorMonitor(
      snapshot: () => snapshot,
      onFailure: () => failures++,
    );
  });
  tearDown(() => monitor.dispose());

  for (final buffering in [false, true]) {
    test(
      'hardware WARN retires the pair despite audio progress: $buffering',
      () {
        snapshot = playing.copyWith(
          phase: buffering ? PlaybackPhase.buffering : PlaybackPhase.playing,
          isBuffering: buffering,
        );
        monitor.report(hardwareError, NativeLogSeverity.warning);
        expect(failures, 1);
        snapshot = snapshot.copyWith(position: const Duration(seconds: 356));
        monitor.update();
        monitor.report(hardwareError, NativeLogSeverity.warning);
        expect(failures, 1);
      },
    );
  }

  test(
    'nested VO failure is classified without retaining its prefix or URL',
    () {
      final error = NativeErrorSummary.classify(
        'Failed to map video frame https://private/?token=SECRET',
        prefix: 'vo/libmpv/d3d11va',
      );
      expect(error.component, 'vo');
      expect(error.cause, NativeErrorCause.videoOutput);
      monitor.report(error, NativeLogSeverity.error);
      expect(failures, 1);
    },
  );

  test(
    'bad frames, fallback, output warnings and advice retain native recovery',
    () {
      for (final (text, prefix, severity) in [
        ('Invalid NAL unit size', 'ffmpeg/video', NativeLogSeverity.error),
        ('Error while decoding frame!', 'vd', NativeLogSeverity.warning),
        (
          'Attempting next decoding method after failure of h264-d3d11va.',
          'vd',
          NativeLogSeverity.warning,
        ),
        (
          'Consider trying --hwdec=auto as they may help.',
          'cplayer',
          NativeLogSeverity.warning,
        ),
        (
          'Audio/Video desynchronisation detected! Possible reasons include too slow hardware.',
          'cplayer',
          NativeLogSeverity.warning,
        ),
        ('Unsupported texture', 'vo/libmpv', NativeLogSeverity.warning),
        ('HTTP error 403', 'ffmpeg', NativeLogSeverity.error),
      ]) {
        monitor.report(
          NativeErrorSummary.classify(text, prefix: prefix),
          severity,
        );
      }
      monitor.update();
      expect(failures, 0);
    },
  );

  test('paused hardware failure waits for explicit playback', () {
    snapshot = playing.copyWith(
      phase: PlaybackPhase.paused,
      desiredPlaying: false,
    );
    monitor.report(hardwareError, NativeLogSeverity.warning);
    expect(failures, 0);
    snapshot = playing;
    monitor.update();
    expect(failures, 1);
  });

  for (final action in ['seek', 'source', 'ended', 'dispose', 'reset']) {
    test('$action invalidates a pending paused video failure', () {
      snapshot = playing.copyWith(
        phase: PlaybackPhase.paused,
        desiredPlaying: false,
      );
      monitor.report(hardwareError, NativeLogSeverity.warning);
      switch (action) {
        case 'seek':
          snapshot = snapshot.copyWith(isSeeking: true);
        case 'source':
          snapshot = snapshot.copyWith(generation: 2);
        case 'ended':
          snapshot = snapshot.copyWith(phase: PlaybackPhase.ended);
        case 'dispose':
          monitor.dispose();
        case 'reset':
          monitor.reset();
      }
      monitor.update();
      snapshot = playing;
      monitor.update();
      expect(failures, 0);
    });
  }

  test('opening retains its native readiness deadline', () {
    snapshot = playing.copyWith(phase: PlaybackPhase.opening);
    monitor.report(hardwareError, NativeLogSeverity.warning);
    snapshot = playing;
    monitor.update();
    expect(failures, 0);
  });
}
