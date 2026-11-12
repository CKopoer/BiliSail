import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/playback/presentation/player_loading_indicator.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const selectedOutput = String.fromEnvironment(
    'BILI_TEST_OUTPUT',
    defaultValue: 'all',
  );
  final outputs = Platform.isAndroid
      ? AndroidVideoOutputMode.values.where(
          (mode) => selectedOutput == 'all' || mode.name == selectedOutput,
        )
      : [AndroidVideoOutputMode.renderedTexture];
  for (final output in outputs) {
    testWidgets(
      'media_kit cached seeks keep native data and skip preparation: ${output.name}',
      (tester) async {
        initializePlayerBackend();
        const definedDirectory = String.fromEnvironment('BILI_TEST_MEDIA_DIR');
        final directory = definedDirectory.isNotEmpty
            ? definedDirectory
            : Platform.environment['BILI_TEST_BUFFER_DIR']!;
        final media = {
          '/video': await File('$directory/video.mp4').readAsBytes(),
          '/audio': await File('$directory/audio.m4a').readAsBytes(),
        };
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final release = Completer<void>();
        var holdNetwork = false;
        server.listen((request) async {
          try {
            final bytes = media[request.uri.path]!;
            final range = RegExp(r'bytes=(\d+)-(\d*)')
                .firstMatch(request.headers.value('range') ?? '');
            final start = int.parse(range?[1] ?? '0');
            final end = math.min(
              int.tryParse(range?[2] ?? '') ?? bytes.length - 1,
              bytes.length - 1,
            );
            request.response
              ..bufferOutput = false
              ..statusCode = 206
              ..contentLength = end - start + 1
              ..headers.set(
                'Content-Range',
                'bytes $start-$end/${bytes.length}',
              );
            for (var offset = start; offset <= end; offset += 64 * 1024) {
              if (holdNetwork) await release.future;
              request.response.add(
                bytes.sublist(offset, math.min(offset + 64 * 1024, end + 1)),
              );
              await request.response.flush();
            }
            await request.response.close();
          } on SocketException {
            // A replaced native read closes its socket.
          } on HttpException {
            // Teardown can retire a response while it is being flushed.
          }
        });
        final PlayerEngine engine = MediaKitEngine();
        final failures = <PlayerFailure>[];
        final errors = engine.failures.listen(failures.add);
        MediaTrack track(String name) => MediaTrack(
          uri: Uri.parse('http://127.0.0.1:${server.port}/$name'),
          requestPolicy: MediaRequestPolicy(),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(
              home: Stack(
                children: [
                  VideoSurface(engine: engine),
                  StreamBuilder<PlaybackSnapshot>(
                    stream: engine.snapshots,
                    initialData: engine.currentSnapshot,
                    builder: (context, state) {
                      final snapshot = state.requireData;
                      return PlayerLoadingIndicator(
                        preparing: snapshot.phase == PlaybackPhase.opening,
                        recovering: false,
                        buffering:
                            snapshot.desiredPlaying && snapshot.isBuffering,
                      );
                    },
                  ),
                ],
              ),
            ),
          );
          await _withFrames(
            tester,
            engine.open(
              DashPairSource(video: track('video'), audio: track('audio')),
              OpenOptions(volume: 0, androidVideoOutput: output),
            ),
          );
          await _until(
            tester,
            () => engine.currentSnapshot.buffered > const Duration(seconds: 20),
          );
          final generation = engine.currentSnapshot.generation;
          holdNetwork = true;
          for (final playing in [false, true]) {
            if (playing) await _withFrames(tester, engine.play());
            final before = engine.currentSnapshot.buffered;
            final target =
                engine.currentSnapshot.position + const Duration(seconds: 3);
            final watch = Stopwatch()..start();
            await _withFrames(
              tester,
              engine.seek(target).timeout(const Duration(seconds: 3)),
              checkHints: true,
            );
            await tester.pump();
            expect(engine.currentSnapshot.generation, generation);
            expect(engine.currentSnapshot.desiredPlaying, playing);
            expect(engine.currentSnapshot.isSeeking, false);
            expect(
              engine.currentSnapshot.buffered,
              greaterThan(target + const Duration(seconds: 5)),
            );
            expect(find.text('正在准备音视频…'), findsNothing);
            debugPrint(
              'CACHE_SEEK backend=media_kit playing=$playing elapsedMs=${watch.elapsedMilliseconds} beforeMs=${before.inMilliseconds} afterMs=${engine.currentSnapshot.buffered.inMilliseconds}',
            );
          }
          release.complete();
          await _withFrames(tester, engine.pause());
          await _withFrames(tester, engine.seek(const Duration(seconds: 1)));
          expect(
            (engine.currentSnapshot.position - const Duration(seconds: 1))
                .abs(),
            lessThan(const Duration(milliseconds: 300)),
          );
          expect(engine.currentSnapshot.desiredPlaying, false);
          for (final playing in [true, false]) {
            if (playing) {
              await _withFrames(tester, engine.play());
            } else {
              await _withFrames(tester, engine.pause());
            }
            for (final seconds in [325, 38, 40, 600, 10, 280]) {
              final target = Duration(seconds: seconds);
              final watch = Stopwatch()..start();
              await _withFrames(
                tester,
                engine.seek(target).timeout(const Duration(seconds: 5)),
              );
              await tester.pump(const Duration(milliseconds: 400));
              expect(
                engine.currentSnapshot.position.inMilliseconds,
                closeTo(target.inMilliseconds + (playing ? 400 : 0), 500),
              );
              expect(engine.currentSnapshot.desiredPlaying, playing);
              expect(engine.currentSnapshot.generation, generation);
              debugPrint(
                'TIMELINE_SEEK backend=media_kit output=${output.name} playing=$playing targetMs=${target.inMilliseconds} elapsedMs=${watch.elapsedMilliseconds} positionMs=${engine.currentSnapshot.position.inMilliseconds}',
              );
            }
          }
          expect(failures, isEmpty);
        } finally {
          if (!release.isCompleted) release.complete();
          await _withFrames(tester, engine.dispose());
          await errors.cancel();
          await server.close(force: true);
          await tester.pumpWidget(const SizedBox.shrink());
        }
      },
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(ready(), true);
}

Future<void> _withFrames(
  WidgetTester tester,
  Future<void> work, {
  bool checkHints = false,
}) async {
  var done = false;
  Object? error;
  StackTrace? stack;
  final observed = work.then<void>(
    (_) => done = true,
    onError: (Object failure, StackTrace trace) {
      error = failure;
      stack = trace;
      done = true;
    },
  );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 16));
    if (checkHints) {
      expect(find.text('正在准备音视频…'), findsNothing);
      expect(find.text('网络缓冲中…'), findsNothing);
    }
  }
  await observed;
  if (error != null) Error.throwWithStackTrace(error!, stack!);
}
