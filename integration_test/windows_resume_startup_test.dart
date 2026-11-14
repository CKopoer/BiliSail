import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final start in [Duration.zero, const Duration(seconds: 400)]) {
    testWidgets(
      'HTTP DASH opens at ${start.inSeconds}s without reading the intervening media',
      (tester) async {
        initializePlayerBackend();
        final directory = Platform.environment['BILI_TEST_BUFFER_DIR'];
        expect(directory, isNotNull);
        final files = {
          '/video': await File('$directory/video.mp4').readAsBytes(),
          '/audio': await File('$directory/audio.m4a').readAsBytes(),
        };
        final sockets = <Socket>{};
        final requests = <String>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final serving = server.listen((request) async {
          final bytes = files[request.uri.path]!;
          final match = RegExp(r'bytes=(\d+)-(\d*)')
              .firstMatch(request.headers.value('range') ?? '');
          final offset = int.tryParse(match?[1] ?? '') ?? 0;
          final end = (int.tryParse(match?[2] ?? '') ?? bytes.length - 1).clamp(
            offset,
            bytes.length - 1,
          );
          requests.add('${request.uri.path}:$offset');
          final response = request.response;
          response.headers.set('Accept-Ranges', 'bytes');
          response.contentLength = end - offset + 1;
          if (match != null) {
            response.statusCode = 206;
            response.headers.set(
              'Content-Range',
              'bytes $offset-$end/${bytes.length}',
            );
          }
          final socket = await response.detachSocket();
          sockets.add(socket);
          try {
            // The MP4 header and opening packets are available. Bytes between
            // the header and resume point are deliberately stalled: a correct
            // initial seek must request its target range rather than read them.
            final stop = offset == 0
                ? (256 * 1024).clamp(offset, end + 1)
                : end + 1;
            socket.add(bytes.sublist(offset, stop));
            await socket.flush();
            if (stop == end + 1) {
              await socket.close();
              sockets.remove(socket);
            }
          } on IOException {
            socket.destroy();
            sockets.remove(socket);
          }
        });
        final engine = MediaKitEngine(
          onDiagnostic: (event) {
            if (event.kind != PlayerDiagnosticKind.nativeLog) {
              debugPrint('RESUME_STAGE ${event.toJson()}');
            }
          },
        );
        MediaTrack track(String path) => MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}$path'),
          requestPolicy: MediaRequestPolicy(),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          final watch = Stopwatch()..start();
          await _frames(
            tester,
            engine.open(
              DashPairSource(
                video: track('/video'),
                audio: track('/audio'),
                duration: const Duration(minutes: 12),
              ),
              OpenOptions(
                startPosition: start,
                play: false,
                volume: 0,
                openTimeout: const Duration(seconds: 5),
              ),
            ),
          );
          expect(
            (engine.currentSnapshot.position - start).abs(),
            lessThan(const Duration(milliseconds: 250)),
          );
          expect(engine.inspectDiagnostics().hasDecodedVideo, true);
          if (start > Duration.zero) {
            for (final path in ['/video', '/audio']) {
              expect(
                requests.any(
                  (request) =>
                      request.startsWith('$path:') && request != '$path:0',
                ),
                isTrue,
                reason: 'Both tracks must request the resume range directly.',
              );
            }
          }
          await _frames(tester, engine.play());
          expect(engine.inspectDiagnostics().hasDecodedAudio, true);
          await engine.pause();
          debugPrint(
            'RESUME_OPEN start=${start.inSeconds} elapsedMs=${watch.elapsedMilliseconds} requests=$requests',
          );
          expect(tester.takeException(), isNull);
        } finally {
          debugPrint(
            'RESUME_REQUESTS start=${start.inSeconds} requests=$requests',
          );
          await _frames(tester, engine.dispose());
          await tester.pumpWidget(const SizedBox.shrink());
          for (final socket in sockets) {
            socket.destroy();
          }
          await serving.cancel();
          await server.close(force: true);
        }
      },
    );
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
