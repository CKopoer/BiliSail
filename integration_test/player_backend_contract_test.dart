import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/shared_player_engine.dart';
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
    for (final decoding in VideoDecodingMode.values) {
      testWidgets('media_kit shared contract: ${output.name}, ${decoding.name}', (
        tester,
      ) async {
        if (directory == null) fail('BILI_TEST_MEDIA_DIR is required');
        initializePlayerBackend();
        final children = <SharedPlayerEngine>[];
        final engine = ConfigurablePlayerEngine.select(
          selectEngine: () async =>
              PlayerEngineSelection('media_kit', () async {
                final child = MediaKitEngine();
                children.add(child);
                return child;
              }),
        );
        final failures = <PlayerFailure>[];
        final subscription = engine.failures.listen(failures.add);
        MediaTrack track(String file) => MediaTrack(
          uri: File('$directory/$file').uri,
          requestPolicy: MediaRequestPolicy(),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          await withFrames(
            tester,
            engine.open(
              DashPairSource(
                video: track('video.mp4'),
                audio: track('audio.m4a'),
              ),
              OpenOptions(
                volume: 0,
                videoDecoding: decoding,
                androidVideoOutput: output,
              ),
            ),
          );
          expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
          expect(engine.currentSnapshot.videoDimensions, isNotNull);
          var generation = engine.currentSnapshot.generation;
          await withFrames(tester, engine.play());
          await until(
            tester,
            () =>
                engine.currentSnapshot.position >
                const Duration(milliseconds: 300),
          );
          await withFrames(tester, engine.pause());
          final before = engine.currentSnapshot.position;
          final nativeBackend = children.single.activeBackend;
          await withFrames(
            tester,
            engine.open(
              DashPairSource(
                video: track('video.mp4'),
                audio: track('audio.m4a'),
              ),
              OpenOptions(
                startPosition: const Duration(seconds: 1),
                volume: 0,
                rate: 1.5,
                videoDecoding: decoding,
                androidVideoOutput: output,
              ),
            ),
          );
          expect(children, hasLength(1));
          expect(children.single.activeBackend, same(nativeBackend));
          expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
          expect(engine.currentSnapshot.generation, generation + 1);
          expect(
            (engine.currentSnapshot.position - const Duration(seconds: 1))
                .abs(),
            lessThan(const Duration(milliseconds: 300)),
          );
          generation = engine.currentSnapshot.generation;
          final end = engine.currentSnapshot.duration;
          final pending = engine.seek(end - const Duration(milliseconds: 34));
          await tester.pump(const Duration(milliseconds: 5));
          final latest = engine.seek(const Duration(seconds: 2));
          await withFrames(tester, Future.wait([pending, latest]));
          expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
          expect(engine.currentSnapshot.isSeeking, false);
          expect(
            (engine.currentSnapshot.position - const Duration(seconds: 2))
                .abs(),
            lessThan(const Duration(milliseconds: 300)),
          );
          await withFrames(tester, engine.setRate(1.5));
          await withFrames(tester, engine.setAudioGain(-3));
          final info = await engine.inspectPlaybackInformation();
          expect(info?.audioGainDb, closeTo(-3, 0.001));
          expect(engine.currentSnapshot.generation, generation);
          await withFrames(tester, engine.play());
          await until(
            tester,
            () =>
                engine.currentSnapshot.position >
                const Duration(milliseconds: 2400),
          );
          await withFrames(tester, engine.pause());
          await withFrames(
            tester,
            engine.seek(end - const Duration(milliseconds: 200)),
          );
          await withFrames(tester, engine.play());
          await until(
            tester,
            () => engine.currentSnapshot.phase == PlaybackPhase.ended,
          );
          await withFrames(tester, engine.seek(Duration.zero));
          await withFrames(tester, engine.play());
          await until(
            tester,
            () =>
                engine.currentSnapshot.position >
                const Duration(milliseconds: 300),
          );
          await withFrames(
            tester,
            engine.open(
              ProgressiveSource(track('audio.m4a'), isAudioOnly: true),
              const OpenOptions(volume: 0),
            ),
          );
          expect(engine.currentSnapshot.videoDimensions, isNull);
          await withFrames(tester, engine.play());
          await until(
            tester,
            () =>
                engine.currentSnapshot.position >
                const Duration(milliseconds: 300),
          );
          expect(failures, isEmpty);
          await withFrames(
            tester,
            engine.open(
              ProgressiveSource(track('audio.m4a')),
              const OpenOptions(volume: 0),
            ),
          );
          await withFrames(tester, engine.play());
          await until(
            tester,
            () =>
                engine.currentSnapshot.position >
                const Duration(milliseconds: 300),
          );
          expect(engine.currentSnapshot.videoDimensions, isNull);
          debugPrint(
            'SHARED_CONTRACT backend=media_kit output=${output.name} decoding=${decoding.name} '
            'startup=true pausedSeek=true replay=true audioOnly=true gain=true beforeMs=${before.inMilliseconds}',
          );
          expect(tester.takeException(), isNull);
        } finally {
          await withFrames(tester, engine.dispose());
          await subscription.cancel();
          await tester.pumpWidget(const SizedBox.shrink());
        }
      });
    }
  }
}

Future<void> withFrames(WidgetTester tester, Future<Object?> operation) async {
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

Future<void> until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 8)) {
    await tester.pump(const Duration(milliseconds: 30));
  }
  expect(ready(), true);
}
