import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Windows preview keeps a rolling 5-second buffer and regular opens allow longer buffering',
    (tester) async {
      initializePlayerBackend();
      final fixturePath = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixturePath, isNotNull, reason: 'Use tool/test-windows-media.ps1');
      final video = await File('$fixturePath/video_preview.mp4').readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var rangeRequests = 0;
      server.listen((request) async {
        final range = request.headers.value('range');
        final match = range == null
            ? null
            : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
        final startText = match?.group(1);
        final start = startText == null ? 0 : int.parse(startText);
        final requestedEnd = match?.group(2);
        final end = requestedEnd == null || requestedEnd.isEmpty
            ? video.length - 1
            : int.parse(requestedEnd);
        request.response.headers.set('Accept-Ranges', 'bytes');
        request.response.headers.contentType = ContentType('video', 'mp4');
        if (start >= video.length || end < start) {
          request.response.statusCode = 416;
        } else {
          final safeEnd = end.clamp(start, video.length - 1);
          if (match != null) {
            ++rangeRequests;
            request.response.statusCode = 206;
            request.response.headers.set(
              'Content-Range',
              'bytes $start-$safeEnd/${video.length}',
            );
          }
          request.response.contentLength = safeEnd - start + 1;
          request.response.add(video.sublist(start, safeEnd + 1));
        }
        try {
          await request.response.close();
        } on SocketException {
          // Closing/replacing a preview intentionally cancels native reads.
        } on HttpException {
          // A stopped native reader can close the response before completion.
        }
      });
      final engine = MediaKitEngine();
      addTearDown(() async {
        await engine.dispose();
        await server.close(force: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      final source = DashVideoSource(
        MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}/video.mp4'),
          requestPolicy: MediaRequestPolicy(),
        ),
      );
      await engine.open(
        source,
        const OpenOptions(
          play: true,
          volume: 0,
          openTimeout: Duration(seconds: 3),
          maxBufferAhead: Duration(seconds: 5),
        ),
      );
      expect(engine.inspectDiagnostics().hasVideoOutput, isTrue);
      expect(engine.inspectDiagnostics().hasDecodedAudio, isFalse);
      await _until(
        tester,
        () =>
            engine.currentSnapshot.position >=
            const Duration(milliseconds: 500),
      );
      await engine.pause();

      Future<Duration> checkWindow(String stage) async {
        await _until(
          tester,
          () =>
              engine.currentSnapshot.buffered -
                  engine.currentSnapshot.position >=
              const Duration(seconds: 4),
        );
        await tester.pump(const Duration(milliseconds: 600));
        final snapshot = engine.currentSnapshot;
        final ahead = snapshot.buffered - snapshot.position;
        // mpv bounds demuxed packet timestamps, with decoder/frame rounding.
        expect(ahead, lessThanOrEqualTo(const Duration(milliseconds: 5500)));
        expect(snapshot.buffered, lessThan(snapshot.duration));
        debugPrint(
          'PREVIEW_BUFFER $stage positionMs=${snapshot.position.inMilliseconds} '
          'bufferedMs=${snapshot.buffered.inMilliseconds} aheadMs=${ahead.inMilliseconds}',
        );
        return snapshot.buffered;
      }

      final firstBuffer = await checkWindow('initial');
      await engine.play();
      await _until(
        tester,
        () => engine.currentSnapshot.position >= const Duration(seconds: 4),
      );
      await engine.pause();
      final advancedBuffer = await checkWindow('advanced');
      expect(
        advancedBuffer,
        greaterThan(firstBuffer + const Duration(seconds: 2)),
      );
      await engine.seek(const Duration(seconds: 35));
      await engine.play();
      await _until(
        tester,
        () =>
            engine.currentSnapshot.position >=
            const Duration(milliseconds: 35400),
      );
      await engine.pause();
      await checkWindow('seek');
      expect(rangeRequests, greaterThan(0));

      // A regular open restores the five-minute window, covering this short file.
      await engine.open(source, const OpenOptions(volume: 0));
      await _until(
        tester,
        () => engine.currentSnapshot.buffered >= const Duration(seconds: 58),
      );
      debugPrint(
        'PREVIEW_BUFFER regular bufferedMs=${engine.currentSnapshot.buffered.inMilliseconds}',
      );
      expect(tester.takeException(), isNull);
    },
  );
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(condition(), isTrue, reason: 'Native buffer did not reach its window');
}
