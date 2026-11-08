import 'dart:io';
import 'dart:math';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final fvp in [true, false]) {
    for (final playing in [true, false]) {
      testWidgets('HTTP DASH rapid seek: fvp=$fvp, playing=$playing', (
        tester,
      ) async {
        initializePlayerBackend();
        final directory =
            Platform.environment['BILI_TEST_BUFFER_DIR'] ??
            'build/validation/player-buffer-fixtures';
        final files = {
          '/video': await File('$directory/video.mp4').readAsBytes(),
          '/audio': await File('$directory/audio.m4a').readAsBytes(),
        };
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        server.listen((request) async {
          try {
            final bytes = files[request.uri.path]!;
            final range = RegExp(
              r'^bytes=(\d+)-(\d*)$',
            ).firstMatch(request.headers.value(HttpHeaders.rangeHeader) ?? '');
            final start = int.parse(range?[1] ?? '0');
            final end = min(
              int.tryParse(range?[2] ?? '') ?? bytes.length - 1,
              bytes.length - 1,
            );
            if (start > 4 * 1024 * 1024) {
              await Future<void>.delayed(const Duration(milliseconds: 150));
            }
            request.response
              ..bufferOutput = false
              ..statusCode = 206
              ..headers.set(
                'Content-Range',
                'bytes $start-$end/${bytes.length}',
              )
              ..contentLength = end - start + 1;
            for (var p = start; p <= end; p += 64 * 1024) {
              request.response.add(
                bytes.sublist(p, min(p + 64 * 1024, end + 1)),
              );
              await request.response.flush();
              await Future<void>.delayed(const Duration(milliseconds: 5));
            }
            await request.response.close();
          } on SocketException {
            /* Superseded range reader. */
          } on HttpException {
            /* Superseded range reader. */
          }
        });
        void diagnostic(PlayerDiagnosticEvent event) {
          if ({
            PlayerDiagnosticKind.nativeError,
            PlayerDiagnosticKind.failed,
            PlayerDiagnosticKind.playbackStalled,
          }.contains(event.kind)) {
            debugPrint(
              'RAPID ${event.kind} code=${event.nativeErrorCode} '
              'reason=${event.stallReason} position=${event.snapshot.position.inMilliseconds}',
            );
          }
        }

        final PlayerEngine engine = fvp
            ? FvpEngine(onDiagnostic: diagnostic)
            : MediaKitEngine(onDiagnostic: diagnostic);
        final failures = <PlayerFailure>[];
        final subscription = engine.failures.listen(failures.add);
        MediaTrack track(String name) => MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}/$name'),
          requestPolicy: MediaRequestPolicy(),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          await _withFrames(
            tester,
            engine.open(
              DashPairSource(video: track('video'), audio: track('audio')),
              OpenOptions(play: playing, volume: 0),
            ),
          );
          final generation = engine.currentSnapshot.generation;
          for (var round = 0; round < 3; round++) {
            // Start an uncached seek first, then supersede it while its data
            // may still be waiting. The remaining 20ms burst must coalesce.
            final pending = <Future<void>>[
              engine.seek(const Duration(seconds: 650)),
            ];
            await tester.pump(const Duration(milliseconds: 70));
            for (final seconds in [
              226,
              510,
              80,
              420,
              325,
              100,
              600,
              226,
              325,
            ]) {
              pending.add(engine.seek(Duration(seconds: seconds)));
              await tester.pump(const Duration(milliseconds: 20));
            }
            await _withFrames(tester, Future.wait(pending));
            debugPrint(
              'RAPID round=$round position=${engine.currentSnapshot.position.inMilliseconds} phase=${engine.currentSnapshot.phase}',
            );
            expect(failures, isEmpty);
            expect(engine.currentSnapshot.generation, generation);
            expect(engine.currentSnapshot.isSeeking, false);
            expect(engine.currentSnapshot.desiredPlaying, playing);
            expect(
              (engine.currentSnapshot.position.inSeconds - 325).abs(),
              lessThan(2),
            );
          }
          await _withFrames(tester, engine.play());
          final watch = Stopwatch()..start();
          while (watch.elapsed < const Duration(seconds: 4)) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          expect(failures, isEmpty);
          expect(
            engine.currentSnapshot.position,
            greaterThan(const Duration(seconds: 327)),
          );
          expect(
            engine.currentSnapshot.buffered,
            greaterThan(engine.currentSnapshot.position),
          );
          expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
        } finally {
          await _withFrames(tester, engine.dispose());
          await subscription.cancel();
          await server.close(force: true);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  StackTrace? stack;
  final observed = operation.then<void>(
    (_) => done = true,
    onError: (Object error, StackTrace trace) {
      failure = error;
      stack = trace;
      done = true;
    },
  );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 16));
  }
  await observed;
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
}
