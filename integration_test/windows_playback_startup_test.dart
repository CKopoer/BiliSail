import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final action in ['stop', 'replace', 'dispose', 'timeout']) {
    testWidgets(
      'Windows stalled DASH audio permits $action and discards late events',
      (tester) async {
        initializePlayerBackend();
        final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
        expect(
          fixtures,
          isNotNull,
          reason: 'Set BILI_TEST_MEDIA_DIR to test/fixtures/media',
        );
        final video = await File('$fixtures/video.mp4').readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final requested = Completer<void>();
        final release = Completer<void>();
        String? audioQuery;
        server.listen((request) async {
          try {
            if (request.uri.path == '/audio') {
              audioQuery = request.uri.query;
              if (!requested.isCompleted) requested.complete();
              // Hold the response beyond cancellation/deadline. Cleanup releases
              // it to exercise late native/network completion after replacement.
              await release.future;
              request.response.statusCode = 404;
            } else {
              _serveRange(request, video);
            }
            await request.response.close();
          } on SocketException {
            // Cancellation can close the client's socket before this response.
          } on HttpException {
            // Same case after the response headers have already been written.
          }
        });
        final engine = MediaKitEngine();
        final failures = <PlayerFailure>[];
        final subscription = engine.failures.listen(failures.add);
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          final policy = MediaRequestPolicy();
          final source = DashPairSource(
            video: MediaTrack(
              uri: Uri.parse('http://127.0.0.1:${server.port}/video'),
              requestPolicy: policy,
            ),
            audio: MediaTrack(
              uri: Uri.parse(
                'http://127.0.0.1:${server.port}/audio?k=1;2&v=x:y%2Fz',
              ),
              requestPolicy: policy,
            ),
          );
          Object? openError;
          var openDone = false;
          final opening = engine
              .open(
                source,
                OpenOptions(
                  volume: 0,
                  openTimeout: action == 'timeout'
                      ? const Duration(seconds: 2)
                      : const Duration(seconds: 20),
                ),
              )
              .then<void>(
                (_) => openDone = true,
                onError: (Object error) {
                  openError = error;
                  openDone = true;
                },
              );
          await _until(tester, () => requested.isCompleted);
          expect(audioQuery, 'k=1;2&v=x:y%2Fz');
          final watch = Stopwatch()..start();
          final local = DashPairSource(
            video: MediaTrack(
              uri: File('$fixtures/video.mp4').uri,
              requestPolicy: policy,
            ),
            audio: MediaTrack(
              uri: File('$fixtures/audio.m4a').uri,
              requestPolicy: policy,
            ),
          );
          if (action == 'timeout') {
            await _until(tester, () => openDone);
            expect(openError, isA<PlayerFailure>());
            await _withFrames(
              tester,
              engine.open(local, const OpenOptions(play: true, volume: 0)),
            );
          } else if (action == 'stop') {
            await _withFrames(tester, engine.stop());
          } else if (action == 'dispose') {
            await _withFrames(tester, engine.dispose());
          } else {
            await _withFrames(
              tester,
              engine.open(local, const OpenOptions(play: true, volume: 0)),
            );
          }
          await opening;
          expect(watch.elapsed, lessThan(const Duration(seconds: 3)));
          if (action != 'timeout') {
            expect(openError, isNull);
            expect(failures, isEmpty);
          }
          final generation = engine.currentSnapshot.generation;
          release.complete();
          await tester.pump(const Duration(milliseconds: 250));
          expect(engine.currentSnapshot.generation, generation);
          if (action == 'replace' || action == 'timeout') {
            await _until(
              tester,
              () =>
                  engine.inspectDiagnostics().hasDecodedVideo &&
                  engine.inspectDiagnostics().hasDecodedAudio,
            );
            expect(engine.currentSnapshot.phase, isNot(PlaybackPhase.failed));
          }
          if (action == 'stop') {
            expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
          }
          debugPrint(
            'NATIVE_STARTUP action=$action elapsedMs=${watch.elapsedMilliseconds} signedAudioPreserved=true',
          );
          expect(tester.takeException(), isNull);
        } finally {
          if (!release.isCompleted) release.complete();
          await subscription.cancel();
          await _withFrames(tester, engine.dispose());
          await tester.pumpWidget(const SizedBox.shrink());
          await server.close(force: true);
        }
      },
    );
  }
}

void _serveRange(HttpRequest request, Uint8List bytes) {
  final match = RegExp(r'^bytes=(\d+)-(\d*)$')
      .firstMatch(request.headers.value('range') ?? '');
  final start = match == null ? 0 : int.parse(match.group(1)!);
  if (start >= bytes.length) {
    request.response.statusCode = 416;
    return;
  }
  final end = match == null || match.group(2)!.isEmpty
      ? bytes.length - 1
      : int.parse(match.group(2)!).clamp(start, bytes.length - 1);
  request.response.headers.set('Accept-Ranges', 'bytes');
  request.response.headers.contentType = ContentType('video', 'mp4');
  if (match != null) {
    request.response.statusCode = 206;
    request.response.headers.set(
      'Content-Range',
      'bytes $start-$end/${bytes.length}',
    );
  }
  request.response.contentLength = end - start + 1;
  request.response.add(bytes.sublist(start, end + 1));
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(ready(), isTrue, reason: 'Native startup state deadline');
}

// Replacement creates a new VideoController in a post-frame callback. The
// integration binding must keep pumping frames while native open/dispose waits.
Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  final completed = operation.then<void>(
    (_) => done = true,
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  await _until(tester, () => done);
  await completed;
  if (failure case final error?) throw error;
}
