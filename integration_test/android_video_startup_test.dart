import 'dart:convert';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Android never presents an uninitialized video frame', (
    tester,
  ) async {
    const base = String.fromEnvironment('STARTUP_FIXTURE_BASE');
    expect(base, isNotEmpty);
    final engine = MediaKitEngine();
    final key = GlobalKey();
    final results = <Map<String, Object?>>[];
    binding.reportData = {'startup': results};
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: SizedBox(
                  width: 320,
                  height: 180,
                  child: VideoSurface(engine: engine),
                ),
              ),
            ),
          ),
        ),
      );
      final policy = MediaRequestPolicy();
      // Include repeated opens, both decoders and paused startup. These use
      // generated SDR color bars and a separate sine-wave audio track.
      for (final decoding in VideoDecodingMode.values) {
        for (final play in [false, true]) {
          final row = <String, Object?>{'mode': '${decoding.name}-$play'};
          results.add(row);
          final watch = Stopwatch()..start();
          Object? failure;
          var opened = false;
          final opening = engine
              .open(
                DashPairSource(
                  video: MediaTrack(
                    uri: Uri.parse('$base/sdr.mp4'),
                    requestPolicy: policy,
                  ),
                  audio: MediaTrack(
                    uri: Uri.parse('$base/audio.m4a'),
                    requestPolicy: policy,
                  ),
                ),
                OpenOptions(play: play, volume: 0, videoDecoding: decoding),
              )
              .then<void>(
                (_) {
                  row['openedMs'] = watch.elapsedMilliseconds;
                  opened = true;
                },
                onError: (Object error) {
                  failure = error;
                  opened = true;
                },
              );
          var coloredFrames = 0;
          var blankFrames = 0;
          final flashes = <int>[];
          while ((!opened || coloredFrames < 3) &&
              watch.elapsed < const Duration(seconds: 15)) {
            await tester.pump(const Duration(milliseconds: 16));
            await tester.runAsync(() async {
              final boundary =
                  key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary;
              final image = await boundary.toImage(pixelRatio: .1);
              try {
                final data = (await image.toByteData())!;
                var low = 255;
                var high = 0;
                var sum = 0;
                final colors = <int>{};
                // Ignore a two-pixel edge; test bars have a large range of
                // colors, whereas the initial undersized texture is uniform.
                for (var y = 2; y < image.height - 2; y++) {
                  for (var x = 2; x < image.width - 2; x++) {
                    final offset = (y * image.width + x) * 4;
                    var packed = 0;
                    for (var c = 0; c < 3; c++) {
                      final value = data.getUint8(offset + c);
                      low = value < low ? value : low;
                      high = value > high ? value : high;
                      sum += value;
                      packed = (packed << 4) | (value >> 4);
                    }
                    colors.add(packed);
                  }
                }
                final black = high <= 8;
                final colored = colors.length > 16 && high - low > 100;
                if (black) blankFrames++;
                if (colored) {
                  coloredFrames++;
                  row['firstVideoMs'] ??= watch.elapsedMilliseconds;
                } else if (!black) {
                  row['flashPhase'] = engine.currentSnapshot.phase.name;
                  flashes.add(watch.elapsedMilliseconds);
                  row['flashMean'] =
                      sum / ((image.width - 4) * (image.height - 4) * 3);
                  row['flashColors'] = colors.length;
                  row['flashPng'] ??= base64Encode(
                    (await image.toByteData(format: ui.ImageByteFormat.png))!
                        .buffer
                        .asUint8List(),
                  );
                }
              } finally {
                image.dispose();
              }
              await Future<void>.delayed(const Duration(milliseconds: 5));
            });
          }
          await opening;
          row.addAll({
            'blankFrames': blankFrames,
            'coloredFrames': coloredFrames,
            'flashesMs': flashes,
            'decoder': await engine.inspectHardwareDecoder(),
            'decodedAudio': engine.inspectDiagnostics().hasDecodedAudio,
          });
          expect(failure, isNull);
          expect(coloredFrames, greaterThanOrEqualTo(3));
          expect(engine.currentSnapshot.desiredPlaying, play);
          if (play) expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
          if (!const bool.fromEnvironment('ALLOW_STARTUP_FLASH')) {
            expect(
              flashes,
              isEmpty,
              reason: '${row['mode']} exposed a blank texture',
            );
          }
          await engine.stop();
          await tester.pump();
        }
      }
      final prepared = engine.snapshots.firstWhere(
        (value) => value.phase == PlaybackPhase.ready,
      );
      final cancelledOpen = engine.open(
        DashPairSource(
          video: MediaTrack(
            uri: Uri.parse('$base/sdr.mp4'),
            requestPolicy: policy,
          ),
          audio: MediaTrack(
            uri: Uri.parse('$base/audio.m4a'),
            requestPolicy: policy,
          ),
        ),
        const OpenOptions(
          play: false,
          volume: 0,
          videoDecoding: VideoDecodingMode.software,
        ),
      );
      var stopped = false;
      final stopping = prepared.then((_) async {
        // Leave the synchronous snapshot callback before cancelling the source.
        await Future<void>.delayed(Duration.zero);
        await engine.stop();
        stopped = true;
      });
      final cancellation = Stopwatch()..start();
      while (!stopped && cancellation.elapsed < const Duration(seconds: 15)) {
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      await stopping.timeout(const Duration(seconds: 1));
      await cancelledOpen.timeout(const Duration(seconds: 1));
      await tester.pump();
      expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
      binding.reportData!['cancelWhilePreparing'] = true;
      expect(tester.takeException(), isNull);
    } finally {
      await engine.dispose();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
