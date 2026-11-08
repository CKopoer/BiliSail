import 'dart:io';
import 'dart:math';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/mp4_buffer_index.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final fvp in [false, true]) {
    for (final stalled in ['audio', 'video']) {
      testWidgets(
        '${fvp ? 'fvp' : 'media_kit'} resumes stalled $stalled HTTP without reopening',
        (tester) async {
          initializePlayerBackend();
          final fixtures = Platform.environment['BILI_TEST_BUFFER_DIR']!;
          final files = {
            '/video': await File('$fixtures/video.mp4').readAsBytes(),
            '/audio': await File('$fixtures/audio.m4a').readAsBytes(),
          };
          var faultFloor = 0;
          if (fvp && stalled == 'audio') {
            final index = Mp4BufferIndex.parse(files['/audio']!);
            if (index == null) {
              fail('The audio fixture needs a byte/time index');
            }
            faultFloor = index.spans
                .firstWhere((span) => span.end > const Duration(seconds: 400))
                .offset;
          }
          final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
          var armed = false;
          int? missingByte;
          var resumed = false;
          server.listen((request) async {
            try {
              request.response.bufferOutput = false;
              final bytes = files[request.uri.path]!;
              final range = RegExp(r'^bytes=(\d+)-(\d*)$')
                  .firstMatch(request.headers.value('range') ?? '');
              final start = int.parse(range?[1] ?? '0');
              final end = min(
                int.tryParse(range?[2] ?? '') ?? bytes.length - 1,
                bytes.length - 1,
              );
              request.response
                ..statusCode = 206
                ..contentLength = end - start + 1
                ..headers.set(
                  'Content-Range',
                  'bytes $start-$end/${bytes.length}',
                )
                ..headers.set('ETag', '"${request.uri.path}-fixture"');
              if (request.uri.path == '/$stalled' && missingByte == start) {
                resumed = true;
              }
              for (var p = start; p <= end; p += 16 * 1024) {
                if (armed &&
                    p >= faultFloor &&
                    request.uri.path == '/$stalled' &&
                    missingByte == null) {
                  missingByte = p;
                  debugPrint(
                    'TRACK_STALL backend=${fvp ? 'fvp' : 'media_kit'} '
                    'track=$stalled byte=$p',
                  );
                  // Leave this response pending. The source-owned transport
                  // must replace only this request, retaining the native reader.
                  return;
                }
                request.response.add(
                  bytes.sublist(p, min(p + 16 * 1024, end + 1)),
                );
                await request.response.flush();
                await Future<void>.delayed(const Duration(milliseconds: 20));
              }
              await request.response.close();
            } on SocketException {
              // A cancelled native reader or resumed upstream retires its socket.
            } on HttpException {
              // The old response can be retired while its delayed flush finishes.
            }
          });
          final PlayerEngine engine = fvp ? FvpEngine() : MediaKitEngine();
          final snapshots = <PlaybackSnapshot>[];
          final failures = <PlayerFailure>[];
          final states = engine.snapshots.listen(snapshots.add);
          final errors = engine.failures.listen(failures.add);
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
                const OpenOptions(play: true, volume: 0),
              ),
            );
            if (fvp && stalled == 'audio') {
              // The existing decoder probe can warm the initial audio range.
              // Move to an uncached interval before arming the playback fault.
              await _withFrames(
                tester,
                engine.seek(const Duration(seconds: 400)),
              );
            }
            final generation = engine.currentSnapshot.generation;
            final before = engine.currentSnapshot.position;
            snapshots.clear();
            armed = true;
            await _until(tester, () => resumed);
            await _until(
              tester,
              () =>
                  engine.currentSnapshot.position >
                  before + const Duration(seconds: 1),
            );
            await _until(
              tester,
              () =>
                  engine.currentSnapshot.buffered >
                  engine.currentSnapshot.position + const Duration(seconds: 10),
            );
            expect(failures, isEmpty);
            expect(engine.currentSnapshot.generation, generation);
            expect(
              snapshots.every(
                (s) =>
                    s.generation == generation &&
                    s.phase != PlaybackPhase.opening &&
                    !s.isSeeking,
              ),
              isTrue,
            );
            for (var i = 1; i < snapshots.length; i++) {
              expect(
                snapshots[i].position,
                greaterThanOrEqualTo(snapshots[i - 1].position),
              );
            }
            debugPrint(
              'TRACK_REFILL backend=${fvp ? 'fvp' : 'media_kit'} '
              'track=$stalled resumeByte=$missingByte generation=$generation '
              'beforeMs=${before.inMilliseconds} '
              'afterMs=${engine.currentSnapshot.position.inMilliseconds} '
              'bufferMs=${engine.currentSnapshot.buffered.inMilliseconds}',
            );
            expect(tester.takeException(), isNull);
          } finally {
            await _withFrames(tester, engine.dispose());
            await states.cancel();
            await errors.cancel();
            await tester.pumpWidget(const SizedBox.shrink());
            await server.close(force: true);
          }
        },
      );
    }
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 25)) {
    await tester.pump(const Duration(milliseconds: 30));
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  expect(ready(), isTrue, reason: 'Native track refill deadline');
}

Future<void> _withFrames(WidgetTester tester, Future<void> work) async {
  var done = false;
  Object? failure;
  final waiting = work.then<void>(
    (_) => done = true,
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  await _until(tester, () => done);
  await waiting;
  if (failure != null) throw failure!;
}
