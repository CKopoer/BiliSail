import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final withoutVulkan =
      Platform.environment['BILI_TEST_DOVI_NO_VULKAN'] == 'true';

  testWidgets('unavailable Dolby converter reports incompatibility', (
    tester,
  ) async {
    final fixtures = Platform.environment['BILI_TEST_DOVI_DIR'];
    expect(fixtures, isNotNull);
    final engine = MediaKitEngine(
      onDiagnostic: (event) {
        debugPrint('DOVI_DIAGNOSTIC ${event.toJson()}');
      },
    );
    final policy = MediaRequestPolicy();
    DashPairSource source(Uri video) => DashPairSource(
      video: MediaTrack(uri: video, requestPolicy: policy),
      audio: MediaTrack(
        uri: File('test/fixtures/media/audio.m4a').absolute.uri,
        requestPolicy: policy,
      ),
    );
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      PlayerFailure? failure;
      final opening = Stopwatch()..start();
      try {
        await _withFrames(
          tester,
          engine.open(
            source(File('$fixtures/video.mp4').uri),
            const OpenOptions(play: false, volume: 0),
          ),
        );
      } on PlayerFailure catch (error) {
        failure = error;
      }
      expect(failure?.kind, PlayerFailureKind.unsupportedVideoColor);
      expect(
        opening.elapsed,
        lessThan(const Duration(seconds: 12)),
        reason: 'Leave startup time for the compatible stream',
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      await _withFrames(
        tester,
        engine.open(
          source(File('test/fixtures/media/video.mp4').absolute.uri),
          const OpenOptions(play: false, volume: 0),
        ),
      );
      expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
    }
  }, skip: !withoutVulkan);

  testWidgets('Profile 5 texture matches a Dolby-aware SDR reference', (
    tester,
  ) async {
    final fixtures = Platform.environment['BILI_TEST_DOVI_DIR'];
    expect(
      fixtures,
      isNotNull,
      reason: 'Use tool/test-windows-dolby-vision.ps1',
    );
    final engine = MediaKitEngine(
      onDiagnostic: (event) {
        debugPrint('DOVI_DIAGNOSTIC ${event.toJson()}');
      },
    );
    final boundaryKey = GlobalKey();
    final policy = MediaRequestPolicy();
    final audio = File('test/fixtures/media/audio.m4a').absolute.uri;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: boundaryKey,
                child: SizedBox(
                  width: 640,
                  height: 360,
                  child: VideoSurface(engine: engine),
                ),
              ),
            ),
          ),
        ),
      );
      final referenceCodec = await ui.instantiateImageCodec(
        await File('$fixtures/reference.png').readAsBytes(),
        targetWidth: 640,
        targetHeight: 360,
      );
      final referenceFrame = await referenceCodec.getNextFrame();
      final reference = await referenceFrame.image.toByteData();
      referenceFrame.image.dispose();
      referenceCodec.dispose();
      expect(reference, isNotNull);

      final sdrSource = DashPairSource(
        video: MediaTrack(
          uri: File('test/fixtures/media/video.mp4').absolute.uri,
          requestPolicy: policy,
        ),
        audio: MediaTrack(uri: audio, requestPolicy: policy),
      );
      await _withFrames(
        tester,
        engine.open(sdrSource, const OpenOptions(volume: 0)),
      );
      final sdrDecoder = await engine.inspectHardwareDecoder();

      for (final decoding in VideoDecodingMode.values) {
        await _withFrames(
          tester,
          engine.open(
            DashPairSource(
              video: MediaTrack(
                uri: File('$fixtures/video.mp4').uri,
                // Intentionally omit the codec: local/offline media must also
                // be recognized from its native DOVI configuration record.
                requestPolicy: policy,
              ),
              audio: MediaTrack(uri: audio, requestPolicy: policy),
            ),
            OpenOptions(play: false, volume: 0, videoDecoding: decoding),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));
        final decoder = await engine.inspectHardwareDecoder();
        debugPrint('DOVI_DECODER mode=${decoding.name} actual=$decoder');
        if (decoding == VideoDecodingMode.software) expect(decoder, 'no');
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final frame = await boundary.toImage();
        try {
          expect(frame.width, 640);
          expect(frame.height, 360);
          final pixels = await frame.toByteData();
          expect(pixels, isNotNull);
          var error = 0;
          for (var i = 0; i < pixels!.lengthInBytes; i += 4) {
            for (var channel = 0; channel < 3; channel++) {
              error +=
                  (pixels.getUint8(i + channel) -
                          reference!.getUint8(i + channel))
                      .abs();
            }
          }
          final meanError = error / (frame.width * frame.height * 3);
          final png = await frame.toByteData(format: ui.ImageByteFormat.png);
          await File('$fixtures/${decoding.name}.png')
              .writeAsBytes(png!.buffer.asUint8List());
          debugPrint('DOVI_COLOR decoding=${decoding.name} MAE=$meanError');
          // Allow scaling/renderer differences. The unconverted texture has
          // MAE > 40 on this fixture, including its strong green/purple cast.
          expect(meanError, lessThan(12), reason: 'Profile 5 color conversion');
        } finally {
          frame.dispose();
        }
        await _withFrames(tester, engine.play());
        await tester.pump(const Duration(milliseconds: 500));
        expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
        expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
        await _withFrames(tester, engine.seek(const Duration(seconds: 2)));
        await _withFrames(tester, engine.pause());
        await tester.pump(const Duration(milliseconds: 300));
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        // The snapshot can retain buffering=true when paused during a seek.
        // Verify the pause behavior through its intent and frozen media clock.
        final pausedPosition = engine.currentSnapshot.position;
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          (engine.currentSnapshot.position - pausedPosition).abs(),
          lessThan(const Duration(milliseconds: 100)),
        );
        expect(engine.currentSnapshot.phase, isNot(PlaybackPhase.failed));
      }

      // A new SDR source must not inherit the conversion or copy decoder.
      await _withFrames(
        tester,
        engine.open(sdrSource, const OpenOptions(play: true, volume: 0)),
      );
      expect(await engine.inspectHardwareDecoder(), sdrDecoder);
      debugPrint('DOVI_SDR_RESTORED decoder=$sdrDecoder');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
    }
  }, skip: withoutVulkan);
}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  (Object, StackTrace)? failure;
  final completion = operation
      .timeout(const Duration(seconds: 40))
      .then<void>(
        (_) => done = true,
        onError: (Object error, StackTrace stack) {
          failure = (error, stack);
          done = true;
        },
      );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await completion;
  if (failure case final error?) {
    Error.throwWithStackTrace(error.$1, error.$2);
  }
}
