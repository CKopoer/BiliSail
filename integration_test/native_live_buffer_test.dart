import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('live FLV retains its connection through a long network gap', (
    tester,
  ) async {
    initializePlayerBackend();
    final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR'];
    expect(directory, isNotNull, reason: 'Use tool/test-windows-content.ps1');
    final bytes = await File('$directory/live.flv').readAsBytes();
    final firstEnd = _tagAt(bytes, 4500);
    final burstEnd = _tagAt(bytes, 6500);
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
      try {
        response.add(bytes.sublist(0, firstEnd));
        await response.flush();
        await burst.future;
        response.add(bytes.sublist(firstEnd, burstEnd));
        await response.flush();
        if (!burstWritten.isCompleted) burstWritten.complete();
        await resume.future;
        response.add(bytes.sublist(burstEnd));
        await response.close();
      } on SocketException {
        // A stopped player intentionally cancels its HTTP reader.
      } on HttpException {
        // Cleanup may close the connection before its response completes.
      }
    });
    final failures = <PlayerFailure>[];
    final engine = MediaKitEngine();
    final subscription = engine.failures.listen(failures.add);
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
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
      // Allow the already queued decoder/audio-device data to drain before
      // measuring whether the native playback clock stays stopped.
      await tester.pump(const Duration(seconds: 1));
      final waitingAt = engine.inspectDiagnostics().position;
      debugPrint('LIVE_BUFFER frozenAtMs=${waitingAt.inMilliseconds}');
      await tester.pump(const Duration(seconds: 9));
      expect(failures, isEmpty);
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
      // Two seconds exceeds the old 1s wait but cannot satisfy the live 3s
      // cushion. Keep waiting instead of resuming into another underrun.
      expect(engine.currentSnapshot.isBuffering, isTrue);
      expect(
        (engine.inspectDiagnostics().position - waitingAt).abs(),
        lessThan(const Duration(milliseconds: 250)),
      );
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
  });
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
