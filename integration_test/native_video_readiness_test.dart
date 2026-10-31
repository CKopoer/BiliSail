import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('foreground follows a presentable video frame on each open', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(fixtures, isNotNull);
    final engine = MediaKitEngine();
    final readiness = engine.videoOutput as VideoFrameReadiness;
    final video = MediaTrack(
      uri: File('$fixtures/video.mp4').uri,
      requestPolicy: MediaRequestPolicy(),
    );
    final audio = MediaTrack(
      uri: File('$fixtures/audio.m4a').uri,
      requestPolicy: MediaRequestPolicy(),
    );
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            fit: StackFit.expand,
            children: [
              VideoSurface(engine: engine),
              ValueListenableBuilder<bool>(
                valueListenable: readiness.frameReady,
                builder: (context, ready, _) => ready
                    ? const Text('first-frame foreground')
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      );
      for (final source in [
        DashPairSource(video: video, audio: audio),
        ProgressiveSource(video),
      ]) {
        expect(readiness.frameReady.value, isFalse);
        expect(find.text('first-frame foreground'), findsNothing);
        final frame = Completer<void>();
        int? texturesAtReadiness;
        void onFrame() {
          if (readiness.frameReady.value && !frame.isCompleted) {
            // Readiness follows the frame that mounts the video texture.
            texturesAtReadiness = find.byType(Texture).evaluate().length;
            frame.complete();
          }
        }

        readiness.frameReady.addListener(onFrame);
        try {
          await _withFrames(
            tester,
            engine.open(source, const OpenOptions(play: false, volume: 0)),
          );
          await _withFrames(
            tester,
            frame.future.timeout(const Duration(seconds: 5)),
          );
          await tester.pump();
          expect(texturesAtReadiness, 1);
          expect(find.text('first-frame foreground'), findsOneWidget);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
        } finally {
          readiness.frameReady.removeListener(onFrame);
        }
        await _withFrames(tester, engine.stop());
        await tester.pump();
        expect(readiness.frameReady.value, isFalse);
        expect(find.text('first-frame foreground'), findsNothing);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await _withFrames(tester, engine.dispose());
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  for (final play in [false, true]) {
    testWidgets('undecodable DASH video cannot succeed on audio (play=$play)', (
      tester,
    ) async {
      initializePlayerBackend();
      final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixtures, isNotNull);
      final directory = await Directory.systemTemp.createTemp(
        'bili_bad_video_',
      );
      final bytes = await File('$fixtures/video.mp4').readAsBytes();
      // Keep the MP4 video track and samples, but make its decoder unavailable.
      // mpv can still select and play the valid external audio file.
      var replaced = 0;
      for (var i = 0; i + 4 <= bytes.length; i++) {
        if (bytes[i] == 0x61 &&
            bytes[i + 1] == 0x76 &&
            bytes[i + 2] == 0x63 &&
            bytes[i + 3] == 0x31) {
          bytes.setRange(i, i + 4, [0x7a, 0x7a, 0x7a, 0x7a]);
          replaced++;
        }
      }
      expect(replaced, greaterThan(0));
      final broken = await File('${directory.path}/video.mp4')
          .writeAsBytes(bytes);
      final events = <PlayerDiagnosticEvent>[];
      final failures = <PlayerFailure>[];
      final engine = MediaKitEngine(onDiagnostic: events.add);
      final subscription = engine.failures.listen(failures.add);
      final policy = MediaRequestPolicy();
      DashPairSource pair(Uri video) => DashPairSource(
        video: MediaTrack(uri: video, requestPolicy: policy),
        audio: MediaTrack(
          uri: File('$fixtures/audio.m4a').uri,
          requestPolicy: policy,
        ),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        Object? error;
        await _withFrames(
          tester,
          engine
              .open(
                pair(broken.uri),
                OpenOptions(
                  play: play,
                  volume: 0,
                  openTimeout: const Duration(seconds: 2),
                ),
              )
              .catchError((Object failure) {
                error = failure;
              }),
        );
        if (error == null) {
          await _withFrames(tester, engine.play());
          debugPrint('AUDIO_ONLY_FALSE_SUCCESS ${engine.inspectDiagnostics()}');
        }
        expect(error, isA<PlayerFailure>());
        expect(failures, hasLength(1));
        final failed = events.singleWhere(
          (e) => e.kind == PlayerDiagnosticKind.failed,
        );
        expect(failed.readinessStage, NativeReadinessStage.videoDecode);
        expect(failed.diagnostics?.hasDecodedVideo, false);
        expect(failed.diagnostics?.hasVideoOutput, false);
        expect(
          events.where((e) => e.kind == PlayerDiagnosticKind.openReady),
          isEmpty,
        );

        await _withFrames(
          tester,
          engine.open(
            pair(File('$fixtures/video.mp4').uri),
            const OpenOptions(play: false, volume: 0, rate: 1.5),
          ),
        );
        final ready = engine.inspectDiagnostics();
        expect(ready.hasDecodedVideo, true);
        expect(ready.hasVideoOutput, true);
        expect(
          events
              .singleWhere((e) => e.kind == PlayerDiagnosticKind.openReady)
              .diagnostics
              ?.hasVideoOutput,
          true,
        );
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(engine.currentSnapshot.desiredPlaying, false);
        expect(engine.currentSnapshot.rate, 1.5);
        await _withFrames(tester, engine.play());
        expect(engine.inspectDiagnostics().hasDecodedAudio, true);
        expect(failures, hasLength(1));
        expect(tester.takeException(), isNull);
      } finally {
        await subscription.cancel();
        await _withFrames(tester, engine.dispose());
        await tester.pumpWidget(const SizedBox.shrink());
        await directory.delete(recursive: true);
      }
    });
  }

  testWidgets('paused resume confirms position independently of video output', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(fixtures, isNotNull);
    final engine = MediaKitEngine();
    final policy = MediaRequestPolicy();
    final video = MediaTrack(
      uri: File('$fixtures/video.mp4').uri,
      requestPolicy: policy,
    );
    final audio = MediaTrack(
      uri: File('$fixtures/audio.m4a').uri,
      requestPolicy: policy,
    );
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      for (final source in [
        DashPairSource(video: video, audio: audio),
        ProgressiveSource(video),
        ProgressiveSource(audio),
      ]) {
        await _withFrames(
          tester,
          engine.open(
            source,
            const OpenOptions(
              play: false,
              volume: 0,
              startPosition: Duration(seconds: 3),
            ),
          ),
        );
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(engine.currentSnapshot.desiredPlaying, false);
        expect(engine.currentSnapshot.isSeeking, false);
        expect(
          (engine.currentSnapshot.position - const Duration(seconds: 3))
              .inMilliseconds
              .abs(),
          lessThan(400),
        );
        await _withFrames(tester, engine.seek(const Duration(seconds: 1)));
        expect(
          (engine.currentSnapshot.position - const Duration(seconds: 1))
              .inMilliseconds
              .abs(),
          lessThan(400),
        );
      }
      // A stale resume record may reach or exceed the current media duration.
      // Preserve the paused last frame instead of failing video readiness.
      final duration = engine.currentSnapshot.duration;
      for (final position in [
        duration,
        duration + const Duration(seconds: 5),
      ]) {
        await _withFrames(
          tester,
          engine.open(
            DashPairSource(video: video, audio: audio),
            OpenOptions(
              play: false,
              volume: 0,
              startPosition: position,
              openTimeout: const Duration(seconds: 8),
            ),
          ),
        );
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(
          (engine.currentSnapshot.position - duration).inMilliseconds.abs(),
          lessThan(400),
        );
        expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await _withFrames(tester, engine.dispose());
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('seek completion exposes the confirmed native position', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(fixtures, isNotNull);
    final engine = MediaKitEngine();
    final policy = MediaRequestPolicy();
    final video = MediaTrack(
      uri: File('$fixtures/video.mp4').uri,
      requestPolicy: policy,
    );
    final audio = MediaTrack(
      uri: File('$fixtures/audio.m4a').uri,
      requestPolicy: policy,
    );
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      for (final source in [
        DashPairSource(video: video, audio: audio),
        ProgressiveSource(video),
        ProgressiveSource(audio),
      ]) {
        await _withFrames(
          tester,
          engine.open(source, const OpenOptions(play: false, volume: 0)),
        );
        for (final playing in [false, true]) {
          if (playing) {
            await engine.setRate(3);
            await engine.play();
          }
          for (final milliseconds in [4700, 1700, 7200]) {
            await engine.seek(Duration(milliseconds: milliseconds));
            // No extra wait: callers save progress and rebuild danmaku as
            // soon as seek completes, including while paused or at 3x.
            expect(
              engine.currentSnapshot.position.inMilliseconds,
              closeTo(milliseconds, 250),
            );
            expect(engine.currentSnapshot.isSeeking, false);
            expect(engine.currentSnapshot.desiredPlaying, playing);
          }
        }
      }
      await engine.pause();
      final seeking = engine.snapshots.firstWhere((value) => value.isSeeking);
      final obsolete = engine.seek(const Duration(milliseconds: 2300));
      await seeking;
      // The snapshot stream is synchronous; issue stop from the next event
      // turn, as a user action would, rather than reentering its add callback.
      await Future<void>.delayed(Duration.zero);
      await Future.wait([obsolete, engine.stop()]);
      expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
      expect(engine.currentSnapshot.position, Duration.zero);
      expect(engine.currentSnapshot.isSeeking, false);
      expect(tester.takeException(), isNull);
    } finally {
      await _withFrames(tester, engine.dispose());
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'paused progressive video has output; audio needs no video output',
    (tester) async {
      initializePlayerBackend();
      final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixtures, isNotNull);
      final engine = MediaKitEngine();
      final policy = MediaRequestPolicy();
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
        for (final video in [true, false]) {
          await _withFrames(
            tester,
            engine.open(
              ProgressiveSource(
                MediaTrack(
                  uri: File('$fixtures/${video ? 'video.mp4' : 'audio.m4a'}')
                      .uri,
                  requestPolicy: policy,
                ),
              ),
              const OpenOptions(play: false, volume: 0),
            ),
          );
          expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
          if (video) {
            expect(engine.inspectDiagnostics().hasDecodedVideo, true);
            expect(engine.inspectDiagnostics().hasVideoOutput, true);
          } else {
            await _withFrames(tester, engine.play());
            expect(engine.inspectDiagnostics().hasDecodedAudio, true);
            expect(engine.inspectDiagnostics().hasDecodedVideo, false);
          }
        }
        expect(tester.takeException(), isNull);
      } finally {
        await _withFrames(tester, engine.dispose());
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
  );
}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  final completion = operation.then<void>(
    (_) => done = true,
    onError: (Object error, StackTrace stack) {
      failure = error;
      done = true;
    },
  );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  await completion;
  if (failure case final error?) throw error;
}
