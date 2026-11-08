import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  const configured = String.fromEnvironment('BILI_TEST_MEDIA_DIR');
  final directory = configured.isNotEmpty
      ? configured
      : Platform.environment['BILI_TEST_MEDIA_DIR'];
  for (final output
      in Platform.isAndroid
          ? AndroidVideoOutputMode.values
          : [AndroidVideoOutputMode.renderedTexture]) {
    for (final playing in [true, false]) {
      testWidgets(
        'fvp repeated seeks across EOF: ${output.name}, playing=$playing',
        (tester) async {
          if (directory == null) fail('BILI_TEST_MEDIA_DIR is required');
          final engine = FvpEngine(
            onDiagnostic: (event) {
              if (event.kind == PlayerDiagnosticKind.nativeError ||
                  event.kind == PlayerDiagnosticKind.playbackStalled ||
                  event.kind == PlayerDiagnosticKind.failed) {
                debugPrint(
                  'EOF ${event.kind} code=${event.nativeErrorCode} '
                  'reason=${event.stallReason} position=${event.snapshot.position.inMilliseconds}',
                );
              }
            },
          );
          final failures = <PlayerFailure>[];
          final subscription = engine.failures.listen(failures.add);
          try {
            await tester.pumpWidget(
              MaterialApp(home: VideoSurface(engine: engine)),
            );
            MediaTrack track(String name) => MediaTrack(
              uri: File('$directory/$name').uri,
              requestPolicy: MediaRequestPolicy(),
            );
            await _withFrames(
              tester,
              engine.open(
                DashPairSource(
                  video: track('video.mp4'),
                  audio: track('audio.m4a'),
                ),
                OpenOptions(
                  play: playing,
                  volume: 0,
                  androidVideoOutput: output,
                ),
              ),
            );
            final end = engine.currentSnapshot.duration.inMilliseconds;
            expect(end, greaterThan(3000));
            for (var round = 0; round < 3; round++) {
              final pending = <Future<void>>[];
              for (final ms in [end - 34, end, end - 20, 2000, end - 34]) {
                pending.add(engine.seek(Duration(milliseconds: ms)));
                await tester.pump(const Duration(milliseconds: 5));
              }
              await _withFrames(tester, Future.wait(pending));
              await _withFrames(
                tester,
                engine.seek(Duration(milliseconds: end)),
              );
              await _withFrames(
                tester,
                engine.seek(const Duration(seconds: 2)),
              );
              expect(failures, isEmpty);
              expect(engine.currentSnapshot.isSeeking, false);
              expect(
                (engine.currentSnapshot.position.inMilliseconds - 2000).abs(),
                lessThan(300),
              );
              if (!playing) {
                expect(engine.currentSnapshot.desiredPlaying, false);
                expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
              } else {
                await _withFrames(tester, engine.play());
              }
            }
            // Native re-preparation must preserve ordinary EOF and replay.
            if (playing) {
              await _withFrames(
                tester,
                engine.seek(Duration(milliseconds: end - 200)),
              );
              final watch = Stopwatch()..start();
              while (engine.currentSnapshot.phase != PlaybackPhase.ended &&
                  watch.elapsed < const Duration(seconds: 3)) {
                await tester.pump(const Duration(milliseconds: 20));
              }
              expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
              await _withFrames(tester, engine.seek(Duration.zero));
              expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
            }
          } finally {
            await _withFrames(tester, engine.dispose());
            await subscription.cancel();
            await tester.pumpWidget(const SizedBox.shrink());
            await Future<void>.delayed(const Duration(seconds: 2));
          }
        },
      );
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
