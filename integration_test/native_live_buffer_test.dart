import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final readTimeout in [false, true]) {
    testWidgets(
      readTimeout
          ? 'live FLV read timeout follows native EOF semantics'
          : 'live FLV media gap retains a responsive HTTP connection',
      (tester) async {
        initializePlayerBackend();
        final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR'];
        expect(
          directory,
          isNotNull,
          reason: 'Use tool/test-windows-content.ps1',
        );
        final bytes = await File('$directory/live.flv').readAsBytes();
        final firstEnd = _tagAt(bytes, 4500);
        final burstEnd = _tagAt(bytes, 6500);
        final heartbeat = _metadataTag(bytes);
        final burst = Completer<void>();
        final burstWritten = Completer<void>();
        final resume = Completer<void>();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        var requests = 0;
        server.listen((request) async {
          requests++;
          final response = request.response;
          response.bufferOutput = false;
          response.headers.contentType = ContentType('video', 'x-flv');
          Future<void> waitFor(Completer<void> gate) async {
            while (!gate.isCompleted) {
              await Future.any([
                gate.future,
                Future<void>.delayed(const Duration(seconds: 1)),
              ]);
              if (!gate.isCompleted && !readTimeout) {
                // FLV metadata keeps HTTP responsive without adding media packets.
                // A complete socket read outage is covered separately below.
                response.add(heartbeat);
                await response.flush();
              }
            }
          }

          try {
            response.add(bytes.sublist(0, firstEnd));
            await response.flush();
            await waitFor(burst);
            response.add(bytes.sublist(firstEnd, burstEnd));
            await response.flush();
            if (!burstWritten.isCompleted) burstWritten.complete();
            await waitFor(resume);
            response.add(bytes.sublist(burstEnd));
            await response.close();
          } on SocketException {
            // A stopped player intentionally cancels its HTTP reader.
          } on HttpException {
            // Cleanup may close the connection before its response completes.
          }
        });
        final failures = <PlayerFailure>[];
        final diagnostics = <PlayerDiagnosticEvent>[];
        final engine = MediaKitEngine(onDiagnostic: diagnostics.add);
        final subscription = engine.failures.listen(failures.add);
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          await _withFrames(
            tester,
            engine.open(
              ProgressiveSource(
                MediaTrack(
                  uri: Uri.parse('http://127.0.0.1:${server.port}/live.flv'),
                  requestPolicy: MediaRequestPolicy(),
                ),
                isLive: true,
              ),
              const OpenOptions(play: true, volume: 0),
            ),
          );
          await _until(
            tester,
            () =>
                engine.currentSnapshot.isBuffering &&
                engine.currentSnapshot.position > const Duration(seconds: 2),
          );
          final generation = engine.currentSnapshot.generation;
          if (readTimeout) {
            await _until(
              tester,
              () => engine.currentSnapshot.phase == PlaybackPhase.ended,
            );
            expect(engine.currentSnapshot.generation, generation);
            expect(requests, 1);
            expect(failures, isEmpty);
            return;
          }
          // Allow the already queued decoder/audio-device data to drain before
          // measuring whether the native playback clock stays stopped.
          await tester.pump(const Duration(seconds: 1));
          final waitingAt = engine.inspectDiagnostics().position;
          debugPrint('LIVE_BUFFER frozenAtMs=${waitingAt.inMilliseconds}');
          await tester.pump(const Duration(seconds: 9));
          expect(failures, isEmpty);
          final cacheSamples = diagnostics.where(
            (event) =>
                event.kind == PlayerDiagnosticKind.nativeState &&
                event.nativeState?.pausedForCache == true,
          );
          expect(cacheSamples, isNotEmpty);
          expect(
            diagnostics.any(
              (event) => event.kind == PlayerDiagnosticKind.bufferingStarted,
            ),
            isTrue,
          );
          debugPrint(
            'LIVE_BUFFER afterGapMs=${engine.inspectDiagnostics().position.inMilliseconds}',
          );
          expect(
            (engine.inspectDiagnostics().position - waitingAt).abs(),
            lessThan(const Duration(milliseconds: 250)),
          );
          burst.complete();
          // The unseekable FLV demuxer need not expose a buffered end timestamp.
          // Wait for the server's write and let mpv process the short burst.
          await _withFrames(
            tester,
            burstWritten.future.timeout(const Duration(seconds: 5)),
          );
          await tester.pump(const Duration(seconds: 1));
          expect(engine.currentSnapshot.generation, generation);
          resume.complete();
          await _until(
            tester,
            () =>
                !engine.currentSnapshot.isBuffering &&
                engine.currentSnapshot.position > const Duration(seconds: 6),
          );
          expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
          expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
          expect(engine.currentSnapshot.generation, generation);
          expect(requests, 1);
          expect(failures, isEmpty);
          expect(
            diagnostics.any(
              (event) => event.kind == PlayerDiagnosticKind.bufferingEnded,
            ),
            isTrue,
          );
          expect(
            diagnostics.map((event) => event.playerId).toSet(),
            hasLength(1),
          );
          expect(diagnostics.every((event) => event.playerId != null), isTrue);
          debugPrint(
            'LIVE_BUFFER waitedAtMs=${waitingAt.inMilliseconds} '
            'resumedAtMs=${engine.currentSnapshot.position.inMilliseconds} '
            'requests=$requests failures=0',
          );
        } finally {
          if (!burst.isCompleted) burst.complete();
          if (!resume.isCompleted) resume.complete();
          await subscription.cancel();
          await _withFrames(tester, engine.dispose());
          await tester.pumpWidget(const SizedBox.shrink());
          await server.close(force: true);
        }
      },
    );
  }
}

Uint8List _metadataTag(Uint8List bytes) {
  var offset = 13;
  while (offset + 11 < bytes.length) {
    final size =
        bytes[offset + 1] << 16 | bytes[offset + 2] << 8 | bytes[offset + 3];
    final end = offset + 11 + size + 4;
    if (bytes[offset] == 18) return Uint8List.sublistView(bytes, offset, end);
    offset = end;
  }
  throw StateError('FLV fixture has no metadata heartbeat.');
}

// FLV tags carry a millisecond timestamp; split at packet boundaries so a
// controlled short burst has known media duration regardless of bitrate.
int _tagAt(Uint8List bytes, int milliseconds) {
  var offset = 13; // FLV header and initial PreviousTagSize.
  while (offset + 11 < bytes.length) {
    final size =
        bytes[offset + 1] << 16 | bytes[offset + 2] << 8 | bytes[offset + 3];
    final timestamp =
        bytes[offset + 7] << 24 |
        bytes[offset + 4] << 16 |
        bytes[offset + 5] << 8 |
        bytes[offset + 6];
    if (timestamp >= milliseconds) return offset;
    offset += 11 + size + 4;
  }
  throw StateError('FLV fixture is too short for the buffering test.');
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 10)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: 'Native buffer did not reach expected state');
}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}
