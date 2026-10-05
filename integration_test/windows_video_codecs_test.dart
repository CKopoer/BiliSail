import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Windows H.264, HEVC and AV1 DASH in automatic and software modes',
    (tester) async {
      initializePlayerBackend();
      final directory = Platform.environment['BILI_TEST_CODEC_DIR'];
      expect(directory, isNotNull, reason: 'Use tool/test-windows-codecs.ps1');
      final engine = MediaKitEngine();
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      MediaTrack track(String file) => MediaTrack(
        uri: File('$directory/$file').uri,
        requestPolicy: MediaRequestPolicy(),
      );
      try {
        for (final mode in VideoDecodingMode.values) {
          for (final codec in ['h264', 'hevc', 'av1']) {
            var finished = false;
            Object? failure;
            final opening = engine
                .open(
                  DashPairSource(
                    video: track('$codec.mp4'),
                    audio: track('audio.m4a'),
                  ),
                  OpenOptions(play: true, volume: 0, videoDecoding: mode),
                )
                .then<void>(
                  (_) => finished = true,
                  onError: (Object error) {
                    failure = error;
                    finished = true;
                  },
                );
            final watch = Stopwatch()..start();
            while (!finished && watch.elapsed < const Duration(seconds: 40)) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(finished, isTrue, reason: '$codec $mode open deadline');
            await opening;
            expect(failure, isNull, reason: '$codec $mode');
            while ((!engine.inspectDiagnostics().hasDecodedVideo ||
                    !engine.inspectDiagnostics().hasDecodedAudio ||
                    engine.currentSnapshot.position <
                        const Duration(milliseconds: 300)) &&
                watch.elapsed < const Duration(seconds: 45)) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            final evidence = engine.inspectDiagnostics();
            expect(evidence.hasDecodedVideo, isTrue, reason: '$codec $mode');
            expect(evidence.hasDecodedAudio, isTrue, reason: '$codec $mode');
            expect(
              evidence.position,
              greaterThanOrEqualTo(const Duration(milliseconds: 300)),
            );
            final decoder = await engine.inspectHardwareDecoder();
            expect(decoder, isNotNull);
            if (mode == VideoDecodingMode.software) expect(decoder, 'no');
            debugPrint(
              'VIDEO_CODEC codec=$codec mode=${mode.name} hwdec=$decoder '
              'size=${evidence.videoWidth}x${evidence.videoHeight} audio=${evidence.audioChannels}ch',
            );
            await engine.pause();
            await engine.seek(const Duration(seconds: 1));
            await engine.stop();
            await tester.pump();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await engine.dispose();
      }
    },
  );
}
