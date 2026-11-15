import 'dart:async';

import 'package:bili_player/src/native_buffer_recovery.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late PlaybackSnapshot snapshot;
  late NativeBufferRecovery recovery;
  late List<NativeBufferRecoveryReason> failures;
  Duration? audio, video;
  var samples = 0;
  setUp(() {
    snapshot = const PlaybackSnapshot(
      generation: 1,
      phase: PlaybackPhase.playing,
      desiredPlaying: true,
      position: Duration(seconds: 10),
      buffered: Duration(seconds: 30),
      duration: Duration(minutes: 10),
      rate: 2,
    );
    audio = video = snapshot.position;
    samples = 0;
    failures = [];
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      playbackProgress: () async {
        samples++;
        return (audio: audio, video: video);
      },
      onRecoveryRequired: failures.add,
    );
  });
  tearDown(() => recovery.dispose());

  Future<void> advance(
    WidgetTester tester,
    int ticks, {
    bool freezeAudio = false,
    bool freezeVideo = false,
  }) async {
    for (var i = 0; i < ticks; i++) {
      if (!freezeAudio && audio != null) {
        audio = audio! + const Duration(seconds: 1);
      }
      if (!freezeVideo && video != null) {
        video = video! + const Duration(seconds: 1);
      }
      await tester.pump(const Duration(milliseconds: 500));
    }
  }

  for (final reason in NativeBufferRecoveryReason.values) {
    void report() {
      switch (reason) {
        case NativeBufferRecoveryReason.readError:
          recovery.reportNetworkError(confirmed: true);
        case NativeBufferRecoveryReason.stalledRead:
          recovery.reportNetworkError();
        case NativeBufferRecoveryReason.audioError:
        case NativeBufferRecoveryReason.videoError:
        case NativeBufferRecoveryReason.decoderError:
          recovery.reportDecoderError(reason);
      }
    }

    Future<void> begin(WidgetTester tester) async {
      report();
      await tester.pump();
    }

    testWidgets('$reason uses the same half window while both tracks advance', (
      tester,
    ) async {
      await begin(tester);
      await advance(tester, 9);
      expect(failures, isEmpty);
      report(); // Repeated faults never extend the original five-second window.
      await advance(tester, 1);
      expect(failures, [reason]);
      final sampled = samples;
      await advance(tester, 6);
      expect(samples, sampled);
      expect(failures, [reason]);
    });

    for (final freezeAudio in [false, true]) {
      testWidgets(
        '$reason ends grace when ${freezeAudio ? 'audio' : 'video'} alone freezes',
        (tester) async {
          await begin(tester);
          // Total position keeps advancing. It cannot clear a single-track fault.
          snapshot = snapshot.copyWith(position: const Duration(seconds: 11));
          await advance(
            tester,
            4,
            freezeAudio: freezeAudio,
            freezeVideo: !freezeAudio,
          );
          expect(failures, [reason]);
          expect(snapshot.position, lessThan(snapshot.buffered));
        },
      );
    }
  }

  testWidgets('cache growth alone cannot clear a decoder fault', (
    tester,
  ) async {
    recovery.reportDecoderError(NativeBufferRecoveryReason.audioError);
    await tester.pump();
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 120));
    recovery.update();
    await advance(tester, 10);
    expect(failures, [NativeBufferRecoveryReason.audioError]);
  });

  testWidgets(
    'decoder arriving during a read fault shares its original deadline',
    (tester) async {
      recovery.reportNetworkError(confirmed: true);
      await tester.pump();
      await advance(tester, 8);
      recovery.reportDecoderError(NativeBufferRecoveryReason.videoError);
      snapshot = snapshot.copyWith(buffered: const Duration(seconds: 120));
      recovery.update();
      await advance(tester, 2);
      expect(failures, [NativeBufferRecoveryReason.videoError]);
    },
  );

  testWidgets('componentless SDK duplicates retain a known failing track', (
    tester,
  ) async {
    recovery.reportDecoderError(NativeBufferRecoveryReason.audioError);
    await tester.pump();
    await advance(tester, 8);
    recovery.reportDecoderError(NativeBufferRecoveryReason.decoderError);
    await advance(tester, 2);
    expect(failures, [NativeBufferRecoveryReason.audioError]);
  });

  testWidgets('healthy cache growth retires a read fault and stops sampling', (
    tester,
  ) async {
    recovery.reportNetworkError(confirmed: true);
    await tester.pump();
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 32));
    await advance(tester, 2);
    final sampled = samples;
    await advance(tester, 10);
    expect(samples, sampled);
    expect(failures, isEmpty);
  });

  testWidgets(
    'missing audio is not masked by continuing video and cache growth',
    (tester) async {
      recovery.reportNetworkError(confirmed: true);
      await tester.pump();
      audio = null;
      snapshot = snapshot.copyWith(buffered: const Duration(seconds: 120));
      await advance(tester, 4);
      expect(failures, [NativeBufferRecoveryReason.readError]);
    },
  );

  testWidgets('cache events cannot reuse a stale healthy clock sample', (
    tester,
  ) async {
    recovery.reportNetworkError(confirmed: true);
    await tester.pump();
    await advance(tester, 2);
    audio = null;
    snapshot = snapshot.copyWith(buffered: const Duration(seconds: 120));
    recovery.update();
    await advance(tester, 4);
    expect(failures, [NativeBufferRecoveryReason.readError]);
  });

  for (final action in ['pause', 'seek', 'dispose', 'source']) {
    testWidgets('$action cancels late progress results and all grace timers', (
      tester,
    ) async {
      recovery.dispose();
      final result = Completer<NativeRecoveryProgress>();
      recovery = NativeBufferRecovery(
        snapshot: () => snapshot,
        playbackProgress: () => result.future,
        onRecoveryRequired: failures.add,
      );
      recovery.reportDecoderError(NativeBufferRecoveryReason.videoError);
      switch (action) {
        case 'pause':
          snapshot = snapshot.copyWith(desiredPlaying: false);
        case 'seek':
          snapshot = snapshot.copyWith(isSeeking: true);
        case 'dispose':
          recovery.dispose();
        case 'source':
          snapshot = snapshot.copyWith(generation: 2);
      }
      recovery.update();
      result.complete((audio: audio, video: video));
      await tester.pump(const Duration(seconds: 10));
      expect(failures, isEmpty);
    });
  }

  testWidgets('normal playback does not sample native clocks', (tester) async {
    recovery.update();
    await tester.pump(const Duration(seconds: 10));
    expect(samples, 0);
  });

  testWidgets('a hung clock sample cannot extend grace forever', (
    tester,
  ) async {
    recovery.dispose();
    recovery = NativeBufferRecovery(
      snapshot: () => snapshot,
      playbackProgress: () => Completer<NativeRecoveryProgress>().future,
      onRecoveryRequired: failures.add,
    );
    recovery.reportDecoderError(NativeBufferRecoveryReason.audioError);
    await tester.pump(const Duration(seconds: 2));
    expect(failures, [NativeBufferRecoveryReason.audioError]);
    await tester.pump(
      const Duration(seconds: 1),
    ); // Drain the bounded late query.
  });

  for (final audioOnly in [false, true]) {
    test(
      'intentional single-track playback does not require an absent clock: $audioOnly',
      () async {
        final reads = <String>[];
        final progress = await nativeRecoveryProgress(
          (name) async {
            reads.add(name);
            return name == 'video-format' ? 'h264' : '2.5';
          },
          audio: audioOnly,
          video: !audioOnly,
        );
        expect(
          audioOnly ? progress.audio : progress.video,
          const Duration(milliseconds: 2500),
        );
        expect(reads, audioOnly ? ['audio-pts'] : ['time-pos', 'video-format']);
      },
    );
  }

  for (final missing in ['audio-pts', 'video-format', 'avsync']) {
    test('native progress cannot disguise a missing track: $missing', () async {
      final progress = await nativeRecoveryProgress(
        (name) async => name == missing
            ? null
            : switch (name) {
                'audio-pts' || 'time-pos' => '12.5',
                'video-format' => 'h264',
                'avsync' => '0.02',
                _ => null,
              },
        audio: true,
        video: true,
      );
      expect(missing == 'audio-pts' ? progress.audio : progress.video, isNull);
    });
  }
}
