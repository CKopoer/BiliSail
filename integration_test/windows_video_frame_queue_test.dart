import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final enabled in [false, true]) {
    for (final mode in VideoDecodingMode.values) {
      testWidgets('Windows frame queue=$enabled decoding=${mode.name}', (
        tester,
      ) async {
        initializePlayerBackend();
        final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
        expect(
          directory,
          isNotNull,
          reason: 'Use tool/test-windows-frame-queue.ps1',
        );
        final engine = MediaKitEngine(experimentalVideoFrameQueue: enabled);
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        MediaTrack track(String file) => MediaTrack(
          uri: File('$directory/$file').uri,
          requestPolicy: MediaRequestPolicy(),
        );
        final source = DashPairSource(
          video: track('video.mp4'),
          audio: track('audio.m4a'),
        );
        try {
          await engine.open(
            source,
            OpenOptions(play: true, rate: 2, volume: 0, videoDecoding: mode),
          );
          expect(engine.videoFrameQueueActive, enabled);
          await _until(
            tester,
            () =>
                engine.currentSnapshot.position >=
                    const Duration(milliseconds: 500) &&
                engine.inspectDiagnostics().hasVideoOutput,
          );
          expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
          final decoder = await engine.inspectHardwareDecoder();
          expect(decoder, isNotNull);
          if (mode == VideoDecodingMode.software) expect(decoder, 'no');

          for (final seconds in [6, 2, 8]) {
            await engine.seek(Duration(seconds: seconds));
            await _until(
              tester,
              () =>
                  engine.currentSnapshot.position >=
                  Duration(milliseconds: seconds * 1000 + 400),
            );
            expect(engine.currentSnapshot.rate, 2);
            expect(engine.currentSnapshot.desiredPlaying, isTrue);
            expect(engine.videoFrameQueueActive, enabled);
          }
          await engine.pause();
          await engine.seek(const Duration(seconds: 3));
          await _until(
            tester,
            () =>
                (engine.currentSnapshot.position - const Duration(seconds: 3))
                    .abs() <
                const Duration(milliseconds: 100),
          );
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          await engine.play();
          await _until(
            tester,
            () =>
                engine.currentSnapshot.position >=
                const Duration(milliseconds: 3500),
          );
          final timing = await engine.inspectNativePlaybackTiming();
          debugPrint(
            'VIDEO_FRAME_QUEUE enabled=$enabled mode=${mode.name} hwdec=$decoder '
            'rate=${engine.currentSnapshot.rate} avsync=${timing.avsyncSeconds} '
            'frameDrops=${timing.frameDrops} decoderDrops=${timing.decoderDrops}',
          );

          // Source replacement applies the same opt-in before decoder creation.
          await engine.open(
            source,
            OpenOptions(volume: 0, videoDecoding: mode),
          );
          expect(engine.videoFrameQueueActive, enabled);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);

          // Hover previews keep their existing decoder and five-second policy.
          await engine.open(
            DashVideoSource(track('video_preview.mp4')),
            const OpenOptions(
              play: true,
              volume: 0,
              maxBufferAhead: Duration(seconds: 5),
            ),
          );
          expect(engine.videoFrameQueueActive, isFalse);
          expect(engine.inspectDiagnostics().hasVideoOutput, isTrue);
          await engine.stop();
          expect(engine.videoFrameQueueActive, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await engine.dispose();
        }
      });
    }
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    ready(),
    isTrue,
    reason: 'Native frame queue playback did not recover',
  );
}
