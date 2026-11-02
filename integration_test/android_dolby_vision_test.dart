import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized()
    ..framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('Android Profile 5 color and decoder probe', (tester) async {
    const base = String.fromEnvironment('DOVI_FIXTURE_BASE');
    expect(base, isNotEmpty);
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    Future<Uint8List> download(String name) async {
      final response = await (await client.getUrl(Uri.parse('$base/$name')))
          .close()
          .timeout(const Duration(seconds: 15));
      expect(response.statusCode, 200);
      return Uint8List.fromList(await response.expand((x) => x).toList());
    }

    final engine = MediaKitEngine();
    final boundaryKey = GlobalKey();
    final mode = ValueNotifier('starting');
    final results = <Map<String, Object?>>[];
    binding.reportData = {'dovi': results};
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String>(
                    valueListenable: mode,
                    builder: (_, value, _) =>
                        Text('Dolby Vision Profile 5: $value'),
                  ),
                  RepaintBoundary(
                    key: boundaryKey,
                    child: SizedBox(
                      width: 320,
                      height: 180,
                      child: VideoSurface(engine: engine),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      final codec = await ui.instantiateImageCodec(
        await download('reference.png'),
        targetWidth: 320,
        targetHeight: 180,
      );
      final refFrame = await codec.getNextFrame();
      final reference = await refFrame.image.toByteData();
      refFrame.image.dispose();
      codec.dispose();
      expect(reference, isNotNull);
      final policy = MediaRequestPolicy();
      DashPairSource source(String file) => DashPairSource(
        video: MediaTrack(uri: Uri.parse('$base/$file'), requestPolicy: policy),
        audio: MediaTrack(
          uri: Uri.parse('$base/audio.m4a'),
          requestPolicy: policy,
        ),
      );

      for (final decoding in VideoDecodingMode.values) {
        mode.value = decoding.name;
        await withFrames(
          tester,
          engine.open(
            source('video.mp4'),
            OpenOptions(play: true, volume: 0, videoDecoding: decoding),
          ),
        );
        final startup = Stopwatch()..start();
        while (engine.currentSnapshot.position <
                const Duration(milliseconds: 500) &&
            startup.elapsed < const Duration(seconds: 10)) {
          await tester.pump(const Duration(milliseconds: 16));
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(
          engine.currentSnapshot.position,
          greaterThanOrEqualTo(const Duration(milliseconds: 500)),
        );
        await withFrames(tester, engine.pause());
        await tester.pump(const Duration(milliseconds: 700));
        final capturedPositionMs =
            engine.currentSnapshot.position.inMilliseconds;
        final decoder = await engine.inspectHardwareDecoder();
        final boundary =
            boundaryKey.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
        final image = await boundary.toImage();
        late double mae;
        late String png;
        try {
          final data = await image.toByteData();
          expect(image.width, 320);
          expect(image.height, 180);
          var sum = 0;
          for (var i = 0; i < data!.lengthInBytes; i += 4) {
            for (var c = 0; c < 3; c++) {
              sum += (data.getUint8(i + c) - reference!.getUint8(i + c)).abs();
            }
          }
          mae = sum / (320 * 180 * 3);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          png = base64Encode(bytes!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
        final response = await (await client.postUrl(
          Uri.parse('$base/capture/${decoding.name}'),
        )).close().timeout(const Duration(seconds: 20));
        await response.drain<void>();
        expect(response.statusCode, 200);
        final result = <String, Object?>{
          'mode': decoding.name,
          'capturedPositionMs': capturedPositionMs,
          'hwdec': decoder,
          'mae': mae,
          'colorCorrect': mae < 15,
          'texturePng': png,
        };
        results.add(result);
        debugPrint(
          'ANDROID_DOVI mode=${decoding.name} hwdec=$decoder MAE=$mae',
        );
        await withFrames(tester, engine.play());
        await tester.pump(const Duration(milliseconds: 700));
        result['audioDecoded'] = engine.inspectDiagnostics().hasDecodedAudio;
        result['playingPositionMs'] =
            engine.currentSnapshot.position.inMilliseconds;
        await withFrames(tester, engine.seek(const Duration(seconds: 2)));
        await withFrames(tester, engine.pause());
        await tester.pump(const Duration(milliseconds: 300));
        final paused = engine.currentSnapshot.position;
        await tester.pump(const Duration(milliseconds: 300));
        result['pauseClockDeltaMs'] =
            (engine.currentSnapshot.position - paused).inMilliseconds;
        result['desiredPlayingAfterPause'] =
            engine.currentSnapshot.desiredPlaying;
        expect(decoder, 'no', reason: 'Profile 5 must retain the Dolby RPU');
        expect(result['audioDecoded'], isTrue);
        expect((result['pauseClockDeltaMs']! as int).abs(), lessThan(150));
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
      }
      for (final decoding in VideoDecodingMode.values) {
        final label = decoding == VideoDecodingMode.automatic
            ? 'sdr'
            : 'sdr-software';
        mode.value = label;
        await withFrames(
          tester,
          engine.open(
            source('sdr.mp4'),
            OpenOptions(volume: 0, videoDecoding: decoding),
          ),
        );
        final decoder = await engine.inspectHardwareDecoder();
        binding.reportData!['${label}Decoder'] = decoder;
        expect(
          decoder,
          decoding == VideoDecodingMode.automatic ? 'mediacodec' : 'no',
        );
        expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
        final response = await (await client.postUrl(
          Uri.parse('$base/capture/$label'),
        )).close().timeout(const Duration(seconds: 20));
        await response.drain<void>();
        expect(response.statusCode, 200);
      }
      expect(
        results.every((r) => r['colorCorrect'] == true),
        isTrue,
        reason: 'Profile 5 must match the Dolby-aware SDR reference in both decode modes',
      );
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await engine.dispose();
      mode.dispose();
      client.close(force: true);
    }
  });
}

Future<void> withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  (Object, StackTrace)? failure;
  final completion = operation
      .timeout(const Duration(seconds: 45))
      .then<void>(
        (_) => done = true,
        onError: (Object e, StackTrace s) {
          failure = (e, s);
          done = true;
        },
      );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await completion;
  if (failure case final e?) Error.throwWithStackTrace(e.$1, e.$2);
}
