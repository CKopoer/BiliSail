import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final mode in ['equalHttp', 'unequalHttp', 'unequalFile', 'longHttp']) {
    testWidgets('complete DASH input reaches playback end: $mode', (
      tester,
    ) async {
      initializePlayerBackend();
      final directory = Platform.environment['BILI_TEST_BUFFER_DIR'];
      expect(directory, isNotNull, reason: 'Use tool/test-windows-buffer.ps1');
      final root = Directory(directory!);
      final complete = <String>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final serving = server.listen((request) async {
        final name = request.uri.pathSegments.single;
        final bytes = await File('${root.path}/$name').readAsBytes();
        final match = RegExp(r'^bytes=(\d+)-(\d*)$')
            .firstMatch(request.headers.value('range') ?? '');
        final start = int.tryParse(match?[1] ?? '') ?? 0;
        final end = (int.tryParse(match?[2] ?? '') ?? bytes.length - 1).clamp(
          start,
          bytes.length - 1,
        );
        final response = request.response;
        response.headers.set('Accept-Ranges', 'bytes');
        response.contentLength = end - start + 1;
        if (match != null) {
          response.statusCode = 206;
          response.headers.set(
            'Content-Range',
            'bytes $start-$end/${bytes.length}',
          );
        }
        response.add(bytes.sublist(start, end + 1));
        await response.close();
        complete.add('$name:$start-$end/${bytes.length}');
      });
      final failures = <PlayerFailure>[];
      final engine = MediaKitEngine();
      final subscription = engine.failures.listen(failures.add);
      final long = mode == 'longHttp';
      MediaTrack track(String name) => MediaTrack(
        uri: mode == 'unequalFile'
            ? File('${root.path}/$name').uri
            : Uri.parse('http://127.0.0.1:${server.port}/$name'),
        requestPolicy: MediaRequestPolicy(),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        await _frames(
          tester,
          engine.open(
            DashPairSource(
              video: track(long ? 'eof_video_long.mp4' : 'eof_video.mp4'),
              audio: track(
                long
                    ? 'eof_audio_long.m4a'
                    : mode == 'equalHttp'
                    ? 'eof_audio_equal.m4a'
                    : 'eof_audio_short.m4a',
              ),
            ),
            const OpenOptions(
              play: false,
              volume: 0,
              rate: 2,
              maxBufferAhead: Duration(seconds: 120),
            ),
          ),
        );
        await _frames(tester, engine.play());
        final watch = Stopwatch()..start();
        while (watch.elapsed < Duration(seconds: long ? 17 : 7) &&
            failures.isEmpty &&
            engine.currentSnapshot.phase != PlaybackPhase.ended &&
            (!long || engine.currentSnapshot.position.inSeconds < 25)) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        final snapshot = engine.currentSnapshot;
        debugPrint(
          'DASH_EOF mode=$mode phase=${snapshot.phase.name} '
          'positionMs=${snapshot.position.inMilliseconds} '
          'durationMs=${snapshot.duration.inMilliseconds} '
          'bufferedMs=${snapshot.buffered.inMilliseconds} '
          'failures=${failures.length} complete=$complete',
        );
        expect(failures, isEmpty);
        expect(engine.inspectDiagnostics().hasDecodedAudio, true);
        expect(engine.inspectDiagnostics().hasDecodedVideo, true);
        if (long) {
          // The two tracks end at different timestamps. Native prefetch can
          // stop at its hysteresis threshold before this explicit late seek.
          expect(snapshot.position, greaterThan(const Duration(seconds: 24)));
          expect(snapshot.duration, const Duration(milliseconds: 140500));
          expect(snapshot.buffered, greaterThan(snapshot.position));
          await _frames(tester, engine.seek(const Duration(seconds: 130)));
          watch.reset();
          while (watch.elapsed < const Duration(seconds: 8) &&
              failures.isEmpty &&
              engine.currentSnapshot.phase != PlaybackPhase.ended) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(engine.currentSnapshot.position.inSeconds, greaterThan(139));
        } else {
          expect(snapshot.position, greaterThan(const Duration(seconds: 8)));
        }
        expect(failures, isEmpty);
        expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
        // A seek outside the cached window can fetch new byte ranges. Only
        // offset-zero requests indicate the playlist was opened from scratch.
        expect(
          complete.where((r) => r.contains(':0-')),
          hasLength(mode == 'unequalFile' ? 0 : 2),
        );
        expect(tester.takeException(), isNull);
      } finally {
        await subscription.cancel();
        await _frames(tester, engine.dispose());
        await tester.pumpWidget(const SizedBox.shrink());
        await serving.cancel();
        await server.close(force: true);
      }
    });
  }
}

Future<void> _frames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}
