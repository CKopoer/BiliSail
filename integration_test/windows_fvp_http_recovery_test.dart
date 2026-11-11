import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final scenario in [
    (rate: 1.0, hang: false, permanent: false, cancel: false),
    (rate: 2.0, hang: false, permanent: false, cancel: false),
    (rate: 1.0, hang: true, permanent: false, cancel: false),
    (rate: 2.0, hang: true, permanent: false, cancel: false),
    (rate: 1.0, hang: false, permanent: true, cancel: false),
    (rate: 1.0, hang: true, permanent: false, cancel: true),
  ]) {
    final rate = scenario.rate;
    testWidgets('fvp HTTP audio recovery $scenario', (tester) async {
      final directory = Platform.environment['BILI_FVP_LIVE_MEDIA_DIR']!;
      final files = {
        '/video.mp4': await File('$directory/long-video.mp4').readAsBytes(),
        '/audio.m4a': await File('$directory/long-audio.m4a').readAsBytes(),
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final sockets = <Socket>[];
      final audioRequests = <int>[];
      var disconnected = false;
      server.listen((request) async {
        try {
          final bytes = files[request.uri.path]!;
          final range = RegExp(r'^bytes=(\d+)-(\d*)$')
              .firstMatch(request.headers.value('range') ?? '');
          final start = int.parse(range?[1] ?? '0');
          if (start >= bytes.length) {
            request.response
              ..statusCode = 416
              ..headers.set('Content-Range', 'bytes */${bytes.length}');
            await request.response.close();
            return;
          }
          final end = math.min(
            int.tryParse(range?[2] ?? '') ?? bytes.length - 1,
            bytes.length - 1,
          );
          final audio = request.uri.path == '/audio.m4a';
          if (audio) audioRequests.add(start);
          request.response
            ..bufferOutput = false
            ..statusCode = 206
            ..headers.set('Accept-Ranges', 'bytes')
            ..headers.set('Content-Range', 'bytes $start-$end/${bytes.length}')
            ..contentLength = end - start + 1;
          if (audio && (!disconnected && start == 0 || scenario.permanent)) {
            final initial = !disconnected;
            disconnected = true;
            final socket = await request.response.detachSocket();
            sockets.add(socket);
            if (initial) socket.add(bytes.sublist(start, 60000));
            await socket.flush();
            if (!scenario.hang) socket.destroy();
          } else {
            request.response.add(bytes.sublist(start, end + 1));
            await request.response.close();
          }
        } on SocketException {
          // Native cancellation closes outstanding Range requests.
        } on HttpException {
          // Native cancellation closes outstanding Range requests.
        }
      });
      final events = <PlayerDiagnosticEvent>[];
      final engine = FvpEngine(onDiagnostic: events.add);
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        MediaTrack track(String file) => MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}/$file'),
          requestPolicy: MediaRequestPolicy(),
        );
        final opening = engine.open(
          DashPairSource(video: track('video.mp4'), audio: track('audio.m4a')),
          OpenOptions(play: true, volume: 0, rate: rate),
        );
        if (scenario.cancel) {
          unawaited(opening.then<void>((_) {}, onError: (Object _) {}));
          final requestDeadline = Stopwatch()..start();
          while (audioRequests.isEmpty &&
              requestDeadline.elapsed < const Duration(seconds: 3)) {
            await tester.pump(const Duration(milliseconds: 10));
          }
          expect(audioRequests, [0]);
          final release = Stopwatch()..start();
          await engine.dispose();
          expect(release.elapsed, lessThan(const Duration(seconds: 2)));
          await tester.pump(const Duration(milliseconds: 300));
          expect(audioRequests, [0]);
          return;
        }
        await opening;
        final watch = Stopwatch()..start();
        while (engine.currentSnapshot.position < const Duration(seconds: 12) &&
            engine.currentSnapshot.phase != PlaybackPhase.failed &&
            watch.elapsed < const Duration(seconds: 18)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        debugPrint(
          'HTTP_RECOVERY scenario=$scenario ranges=$audioRequests '
          'position=${engine.currentSnapshot.position.inMilliseconds} '
          'phase=${engine.currentSnapshot.phase} '
          'events=${events.where((e) => e.kind == PlayerDiagnosticKind.playbackStalled).map((e) => e.toJson()).toList()}',
        );
        expect(disconnected, isTrue);
        expect(audioRequests, contains(60000));
        if (scenario.permanent) {
          // FFmpeg bounds each failing read, and the demuxer can perform a
          // second read at the same offset. Verify the actual finite boundary.
          expect(audioRequests, [0, 60000, 60000]);
          expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
          expect(
            events.where((e) => e.kind == PlayerDiagnosticKind.failed),
            hasLength(1),
          );
          return;
        }
        expect(audioRequests, hasLength(2));
        expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
        expect(
          engine.currentSnapshot.position,
          greaterThan(const Duration(seconds: 11)),
        );
        expect(
          events.where((e) => e.kind == PlayerDiagnosticKind.failed),
          isEmpty,
        );
        if (!scenario.hang && rate == 2) {
          final endDeadline = Stopwatch()..start();
          while (engine.currentSnapshot.phase != PlaybackPhase.ended &&
              endDeadline.elapsed < const Duration(seconds: 14)) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          debugPrint(
            'HTTP_EOF position=${engine.currentSnapshot.position.inMilliseconds} phase=${engine.currentSnapshot.phase}',
          );
          expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
          final requestsAtEnd = audioRequests.length;
          await tester.pump(const Duration(milliseconds: 500));
          expect(audioRequests, hasLength(requestsAtEnd));
        }
      } finally {
        await engine.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
        await server.close(force: true);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  }
}
