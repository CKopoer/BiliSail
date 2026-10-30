import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/native_playback_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('Windows resize and information toggle retain the live texture', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(
      fixtures,
      isNotNull,
      reason: 'Set BILI_TEST_MEDIA_DIR to local fixtures',
    );
    final engine = MediaKitEngine();
    final showInfo = ValueNotifier(true);
    final boundaryKey = GlobalKey();
    final surfaceKey = GlobalKey();
    final window = NativePlaybackWindow(0);
    final originalSize = window.outerSize;
    try {
      window.resize(1000, 700);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: FractionallySizedBox(
                widthFactor: .5,
                heightFactor: .5,
                child: ValueListenableBuilder<bool>(
                  valueListenable: showInfo,
                  builder: (context, visible, _) => Row(
                    children: [
                      Expanded(
                        child: RepaintBoundary(
                          key: boundaryKey,
                          child: VideoSurface(key: surfaceKey, engine: engine),
                        ),
                      ),
                      if (visible) const SizedBox(width: 180),
                    ],
                  ),
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton(
              tooltip: '切换视频信息',
              onPressed: () => showInfo.value = !showInfo.value,
              child: const Icon(Icons.info_outline),
            ),
          ),
        ),
      );
      final policy = MediaRequestPolicy();
      await _withFrames(
        tester,
        engine.open(
          DashPairSource(
            video: MediaTrack(
              uri: File('$fixtures/video.mp4').uri,
              requestPolicy: policy,
            ),
            audio: MediaTrack(
              uri: File('$fixtures/audio.m4a').uri,
              requestPolicy: policy,
            ),
          ),
          const OpenOptions(play: false, volume: 0),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      final generation = engine.currentSnapshot.generation;
      final state = tester.state(find.byType(VideoSurface));
      final textureId = tester.widget<Texture>(find.byType(Texture)).textureId;
      final outputWidths = <int?>{};

      Future<void> checkFrame() async {
        expect(tester.state(find.byType(VideoSurface)), same(state));
        expect(
          tester.widget<Texture>(find.byType(Texture)).textureId,
          textureId,
        );
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
        outputWidths.add(engine.inspectDiagnostics().outputWidth);
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        try {
          final pixels = await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          );
          expect(pixels, isNotNull);
          var colored = 0;
          for (var i = 0; i < pixels!.lengthInBytes; i += 16) {
            if (pixels.getUint8(i) +
                    pixels.getUint8(i + 1) +
                    pixels.getUint8(i + 2) >
                100) {
              colored++;
            }
          }
          expect(
            colored,
            greaterThan(100),
            reason: 'Video frame must not be black',
          );
        } finally {
          image.dispose();
        }
        expect(tester.takeException(), isNull);
      }

      Future<void> checkLayoutTransition() async {
        // Check the intervening Flutter frames as well as the settled cap.
        // Keeping only a final screenshot would miss a short black flash.
        for (var frame = 0; frame < 3; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          await checkFrame();
        }
        await tester.pump(const Duration(milliseconds: 350));
        await checkFrame();
      }

      for (final playing in [false, true]) {
        if (playing) await _withFrames(tester, engine.play());
        for (final width in [800, 1100, 900, 1200]) {
          window.resize(width, 700);
          await checkLayoutTransition();
          if (const bool.fromEnvironment('BILI_RESIZE_INSPECT') &&
              !playing &&
              width == 800) {
            debugPrint('VIDEO_RESIZE_INSPECT width=$width playing=$playing');
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(seconds: 15)),
            );
          }
          await tester.tap(find.byTooltip('切换视频信息'));
          await checkLayoutTransition();
          expect(engine.currentSnapshot.desiredPlaying, playing);
        }
      }
      expect(
        outputWidths.length,
        greaterThan(1),
        reason: 'Exercise native resize',
      );
      debugPrint(
        'VIDEO_RESIZE sameSurface=true sameTexture=true pixels=true '
        'pausedAndPlaying=true outputWidths=$outputWidths',
      );
    } finally {
      await tester.pumpWidget(const SizedBox());
      await _withFrames(tester, engine.dispose());
      showInfo.dispose();
      window.resize(originalSize.width.round(), originalSize.height.round());
    }
  });
}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  final completion = operation
      .timeout(const Duration(seconds: 40))
      .then<void>(
        (_) => done = true,
        onError: (Object error, StackTrace stack) {
          failure = error;
          done = true;
        },
      );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await completion;
  if (failure case final error?) throw error;
}
