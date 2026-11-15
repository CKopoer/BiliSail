import 'package:bili_player/src/native_buffer_recovery.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:bili_player/src/player_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const playing = PlaybackSnapshot(
    generation: 1,
    phase: PlaybackPhase.playing,
    desiredPlaying: true,
    position: Duration(seconds: 10),
    buffered: Duration(seconds: 90),
    duration: Duration(minutes: 10),
  );
  late PlaybackSnapshot snapshot;
  late NativeBufferRecovery recovery;
  late List<NativeBufferRecoveryReason> reasons;
  setUp(() {
    snapshot = playing;
    reasons = [];
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      onRecoveryRequired: reasons.add,
    );
  });
  tearDown(() => recovery.dispose());

  for (final message in [
    'stream 0, offset 0x1234: partial file',
    'root atom offset 0x1234: partial file',
    'Stream ends prematurely at 100, should be 200',
    'Failed to open segment 3 of playlist 0',
    'Failed to reload playlist 0',
    'TLS certificate verification failed',
    'HTTP error 403 Forbidden',
    'Connection reset by peer',
    'Connection timed out',
    'Input/output error',
    'Error in the pull function',
  ]) {
    testWidgets('read fault gets native grace before cache drain: $message', (
      tester,
    ) async {
      recovery.readingChanged(false, endOfInput: true);
      final error = NativeErrorSummary.classify(
        message,
        prefix: 'ffmpeg/demuxer',
      );
      recovery.reportError(error);
      expect(reasons, isEmpty);
      await tester.pump(const Duration(seconds: 39));
      recovery.reportError(error);
      expect(reasons, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(reasons, [NativeBufferRecoveryReason.readError]);
      expect(snapshot.position, lessThan(snapshot.buffered));
    });
  }

  for (final message in [
    'Packet corrupt (stream = 0)',
    'Non-monotonous DTS in output stream',
    'Consider trying --profile=fast and/or --hwdec=auto',
    'Property not found',
    'No such file',
    'Failed to open audio device',
    'Unrecognized diagnostic message',
  ]) {
    testWidgets('unrelated diagnostics do not become read faults: $message', (
      tester,
    ) async {
      recovery.reportError(NativeErrorSummary.classify(message));
      await tester.pump(const Duration(minutes: 1));
      expect(reasons, isEmpty);
    });
  }

  testWidgets(
    'silent read stall starts the same half window without an origin probe',
    (tester) async {
      recovery.readingChanged(true);
      await tester.pump(const Duration(seconds: 5));
      expect(reasons, isEmpty);
      // The half window starts at detection, irrespective of network reachability.
      await tester.pump(const Duration(seconds: 39));
      recovery.reportNetworkError();
      expect(reasons, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(reasons, [NativeBufferRecoveryReason.stalledRead]);
    },
  );

  for (final eof in [false, true]) {
    testWidgets('native idle/EOF cancels silent stall grace: eof=$eof', (
      tester,
    ) async {
      recovery.readingChanged(true);
      await tester.pump(const Duration(seconds: 5));
      recovery.readingChanged(false, endOfInput: eof);
      await tester.pump(const Duration(minutes: 1));
      expect(reasons, isEmpty);
    });
  }

  testWidgets(
    'idle and late tail packets cannot clear an explicit read fault',
    (tester) async {
      recovery.reportNetworkError(confirmed: true);
      snapshot = snapshot.copyWith(
        buffered: const Duration(milliseconds: 90200),
      );
      recovery.update();
      recovery.readingChanged(false, endOfInput: true);
      await tester.pump(const Duration(seconds: 40));
      expect(reasons, [NativeBufferRecoveryReason.readError]);
    },
  );

  testWidgets('real forward cache growth cancels read grace', (tester) async {
    recovery.reportNetworkError(confirmed: true);
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 92));
    recovery.update();
    await tester.pump(const Duration(minutes: 1));
    expect(reasons, isEmpty);
  });

  testWidgets('normal unequal DASH EOF tails do not request recovery', (
    tester,
  ) async {
    snapshot = playing.copyWith(
      position: const Duration(milliseconds: 19633),
      duration: const Duration(milliseconds: 140500),
      buffered: const Duration(milliseconds: 139853),
      rate: 2,
    );
    recovery.readingChanged(true, endOfInput: true);
    await tester.pump(const Duration(minutes: 2));
    expect(reasons, isEmpty);
  });

  testWidgets('full cache idle never becomes a blocked reader', (tester) async {
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 4));
    recovery.readingChanged(false);
    await tester.pump(const Duration(minutes: 1));
    expect(reasons, isEmpty);
  });

  testWidgets('backward seek discards the previous cache high-water mark', (
    tester,
  ) async {
    recovery.readingChanged(true);
    await tester.pump(const Duration(seconds: 4));
    snapshot = snapshot.copyWith(
      isSeeking: true,
      position: const Duration(seconds: 20),
      buffered: const Duration(seconds: 40),
    );
    recovery.update();
    snapshot = snapshot.copyWith(isSeeking: false);
    recovery.update();
    await tester.pump(const Duration(seconds: 3));
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 43));
    recovery.update();
    await tester.pump(const Duration(seconds: 4));
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 46));
    recovery.update();
    await tester.pump(const Duration(seconds: 4));
    expect(reasons, isEmpty);
    recovery.dispose();
  });

  for (final (ahead, rate, wait) in [(120, 3.0, 20), (8, 2.0, 2)]) {
    testWidgets('half actual native window: ahead=$ahead rate=$rate', (
      tester,
    ) async {
      snapshot = snapshot.copyWith(
        buffered: snapshot.position + Duration(seconds: ahead),
        rate: rate,
      );
      recovery.reportNetworkError(confirmed: true);
      await tester.pump(Duration(seconds: wait - 1));
      expect(reasons, isEmpty);
      await tester.pump(const Duration(seconds: 1));
      expect(reasons, [NativeBufferRecoveryReason.readError]);
    });
  }

  test('speed-up reaches the original media midpoint early', () {
    recovery.reportNetworkError(confirmed: true);
    snapshot = snapshot.copyWith(
      position: const Duration(seconds: 50),
      rate: 4,
    );
    recovery.update();
    expect(reasons, [NativeBufferRecoveryReason.readError]);
  });

  test('actual buffering interrupts grace before the half window', () {
    recovery.reportDecoderError(NativeBufferRecoveryReason.audioError);
    snapshot = snapshot.copyWith(
      phase: PlaybackPhase.buffering,
      isBuffering: true,
    );
    recovery.update();
    expect(reasons, [NativeBufferRecoveryReason.audioError]);
  });

  test('empty buffering has no silent opportunity', () {
    snapshot = snapshot.copyWith(
      phase: PlaybackPhase.buffering,
      isBuffering: true,
      buffered: snapshot.position,
    );
    recovery.reportNetworkError(confirmed: true);
    expect(reasons, [NativeBufferRecoveryReason.readError]);
  });

  for (final action in ['pause', 'seek', 'ended', 'full', 'dispose']) {
    testWidgets('inactive/full read source does not restart: $action', (
      tester,
    ) async {
      switch (action) {
        case 'pause':
          snapshot = snapshot.copyWith(desiredPlaying: false);
        case 'seek':
          snapshot = snapshot.copyWith(isSeeking: true);
        case 'ended':
          snapshot = snapshot.copyWith(phase: PlaybackPhase.ended);
        case 'full':
          snapshot = snapshot.copyWith(buffered: snapshot.duration);
        case 'dispose':
          recovery.dispose();
      }
      recovery.reportNetworkError(confirmed: true);
      await tester.pump(const Duration(minutes: 1));
      expect(reasons, isEmpty);
    });
  }
}
