import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_audio_error_monitor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    generation: 1,
    phase: PlaybackPhase.playing,
    desiredPlaying: true,
    position: Duration(seconds: 10),
    buffered: Duration(seconds: 90),
    duration: Duration(minutes: 10),
    rate: 2,
  );
  final decoderError = NativeErrorSummary.classify(
    'Error decoding audio.',
    prefix: 'ad',
  );
  late PlaybackSnapshot snapshot;
  late NativeAudioErrorMonitor monitor;
  late int failures;
  setUp(() {
    snapshot = playing;
    failures = 0;
    monitor = NativeAudioErrorMonitor(
      snapshot: () => snapshot,
      onFailure: () => failures++,
    );
  });
  tearDown(() => monitor.dispose());

  for (final buffering in [false, true]) {
    test(
      'decoder errors recover immediately with cached video: $buffering',
      () {
        snapshot = snapshot.copyWith(
          phase: buffering ? PlaybackPhase.buffering : PlaybackPhase.playing,
          isBuffering: buffering,
        );
        monitor.report(decoderError, NativeLogSeverity.error);
        expect(failures, 1);
        expect(snapshot.position, lessThan(snapshot.buffered));
        snapshot = snapshot.copyWith(position: const Duration(seconds: 14));
        monitor.update();
        monitor.report(decoderError, NativeLogSeverity.error);
        expect(failures, 1, reason: 'one recovery request per native source');
      },
    );
  }

  test('warnings and unrelated errors do not become audio failures', () {
    monitor.report(decoderError, NativeLogSeverity.warning);
    for (final (message, prefix) in [
      ('Error decoding video.', 'vd'),
      ('HTTP error 403 Forbidden', 'ffmpeg'),
      ('Unknown warning', 'other'),
    ]) {
      monitor.report(
        NativeErrorSummary.classify(message, prefix: prefix),
        NativeLogSeverity.error,
      );
    }
    monitor.update();
    expect(failures, 0);
  });

  test('FFmpeg audio decoding errors also retire the pair', () {
    monitor.report(
      NativeErrorSummary.classify(
        'Error decoding frame',
        prefix: 'ffmpeg/audio',
      ),
      NativeLogSeverity.fatal,
    );
    expect(failures, 1);
  });

  test('paused audio errors preserve intent until explicit playback', () {
    snapshot = snapshot.copyWith(
      phase: PlaybackPhase.paused,
      desiredPlaying: false,
    );
    monitor.report(decoderError, NativeLogSeverity.error);
    expect(failures, 0);
    snapshot = playing;
    monitor.update();
    expect(failures, 1);
  });

  for (final action in ['seek', 'source', 'ended', 'dispose', 'reset']) {
    test('$action invalidates a pending paused decoder error', () {
      snapshot = snapshot.copyWith(
        phase: PlaybackPhase.paused,
        desiredPlaying: false,
      );
      monitor.report(decoderError, NativeLogSeverity.error);
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

  test('opening uses its existing decoder readiness deadline', () {
    snapshot = playing.copyWith(phase: PlaybackPhase.opening);
    monitor.report(decoderError, NativeLogSeverity.error);
    snapshot = playing;
    monitor.update();
    expect(failures, 0);
  });
}
