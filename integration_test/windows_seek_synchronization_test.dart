import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Inspect the pinned renderer only in native integration tests.
// ignore: depend_on_referenced_packages
import 'package:media_kit_video/media_kit_video.dart' as mkv;

void main() => registerMediaKitSeekSynchronizationTests();

void registerMediaKitSeekSynchronizationTests({
  String? mediaDirectory,
  AndroidVideoOutputMode androidVideoOutput =
      AndroidVideoOutputMode.renderedTexture,
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final scenario in [
    'playing',
    'paused',
    'immediatePause',
    'pauseRequested',
    'stop',
    'superseded',
    'supersededAgain',
    'supersededAgainPaused',
    'supersededAgainStopped',
  ]) {
    final playing = scenario != 'paused';
    final label =
        'seek waits for delayed video before resuming audio: $scenario, ${androidVideoOutput.name}';
    testWidgets(label, (tester) async {
      initializePlayerBackend();
      final fixtures =
          mediaDirectory ?? Platform.environment['BILI_TEST_MEDIA_DIR']!;
      final video = await File('$fixtures/video.mp4').readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final blocked = Completer<void>();
      final resumeVideo = Completer<void>();
      final secondBlocked = Completer<void>();
      var blockedRequests = 0;
      var delayVideo = false;
      server.listen((request) async {
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final start = range == null
            ? 0
            : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
        final response = request.response;
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        response.contentLength = video.length - start;
        if (range != null) {
          response.statusCode = 206;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-${video.length - 1}/${video.length}',
          );
        }
        if (delayVideo) {
          blockedRequests++;
          if (blockedRequests == 2) secondBlocked.complete();
          if (!blocked.isCompleted) blocked.complete();
          await resumeVideo.future;
        }
        try {
          response.add(video.sublist(start));
          await response.close();
        } on SocketException {
          // Cancelled seeks and teardown close the old range request.
        }
      });
      final backend = MediaKitEngine();
      final engine = ConfigurablePlayerEngine(
        createEngine: () async => backend,
      );
      final failures = <PlayerFailure>[];
      final subscription = engine.failures.listen(failures.add);
      final boundaryKey = GlobalKey();
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: RepaintBoundary(
              key: boundaryKey,
              child: VideoSurface(engine: engine),
            ),
          ),
        );
        await _withFrames(
          tester,
          engine.open(
            DashPairSource(
              video: MediaTrack(
                uri: Uri.parse('http://127.0.0.1:${server.port}/video.mp4'),
                requestPolicy: MediaRequestPolicy(),
              ),
              audio: MediaTrack(
                uri: File('$fixtures/audio.m4a').uri,
                requestPolicy: MediaRequestPolicy(),
              ),
            ),
            OpenOptions(
              play: playing,
              androidVideoOutput: androidVideoOutput,
              volume: 0,
              maxBufferAhead: const Duration(seconds: 1),
            ),
          ),
        );
        final generation = engine.currentSnapshot.generation;
        final readiness = engine.videoOutput as VideoFrameReadiness;
        final firstFrameWait = Stopwatch()..start();
        while (!readiness.frameReady.value &&
            firstFrameWait.elapsed < const Duration(seconds: 5)) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(readiness.frameReady.value, isTrue);
        // Readiness is published after paint; let its mask removal paint too.
        await tester.pump();
        await tester.pump();
        final initialFrame = await _pixels(boundaryKey);
        final native = tester
            .widget<mkv.Video>(find.byType(mkv.Video))
            .controller
            .player;
        delayVideo = true;
        var seekCompleted = false;
        final seeking = engine.seek(const Duration(seconds: 9)).then((_) {
          seekCompleted = true;
        });
        final immediatePause = scenario == 'immediatePause'
            ? engine.pause()
            : null;
        await _withFrames(
          tester,
          blocked.future.timeout(const Duration(seconds: 5)),
        );
        await tester.pump(const Duration(milliseconds: 200));
        final audioBefore = double.tryParse(
          await native.getPropertyAsync('audio-pts'),
        );
        await tester.pump(const Duration(milliseconds: 1500));
        final audioAfter = double.tryParse(
          await native.getPropertyAsync('audio-pts'),
        );
        expect(
          seekCompleted,
          isFalse,
          reason: 'Position alone cannot finish a seek',
        );
        expect(engine.currentSnapshot.isSeeking, isTrue);
        expect(
          await native.getPropertyAsync('pause'),
          !playing || scenario == 'immediatePause' ? 'yes' : 'no',
          reason: 'Native seeking preserves the user pause intent',
        );
        if (audioBefore != null && audioAfter != null) {
          expect((audioAfter - audioBefore).abs(), lessThan(.1));
        }
        if (scenario == 'stop') {
          await _withFrames(tester, engine.stop());
          await _withFrames(tester, seeking);
          expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(failures, isEmpty);
          return;
        }
        if (scenario == 'superseded') delayVideo = false;
        Future<void>? next = switch (scenario) {
          'immediatePause' => immediatePause,
          'pauseRequested' => engine.pause(),
          'superseded' ||
          'supersededAgain' ||
          'supersededAgainPaused' ||
          'supersededAgainStopped' => engine.seek(const Duration(seconds: 2)),
          _ => null,
        };
        if (scenario.startsWith('supersededAgain')) {
          await _withFrames(
            tester,
            secondBlocked.future.timeout(const Duration(seconds: 3)),
          );
          // Android's decoder Surface is flushed during a native source
          // replacement. Check the decoded final frame below; retaining the
          // old texture's pixels while reloading is a desktop guarantee.
          if (!Platform.isAndroid) await _pixels(boundaryKey);
          if (scenario.endsWith('Stopped')) {
            await _withFrames(tester, engine.stop());
            await _withFrames(tester, Future.wait([seeking, next!]));
            expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
            expect(failures, isEmpty);
            return;
          }
          delayVideo = false;
          next = Future.wait([
            next!,
            engine.seek(const Duration(seconds: 1)),
            if (scenario.endsWith('Paused')) engine.pause(),
          ]);
        }
        if (scenario.startsWith('superseded')) {
          // A newer target cancels the obsolete wait before video refills.
          await _withFrames(
            tester,
            seeking.timeout(const Duration(milliseconds: 500)),
          );
          await _withFrames(tester, next!.timeout(const Duration(seconds: 3)));
          expect(resumeVideo.isCompleted, false);
        }
        resumeVideo.complete();
        await _withFrames(tester, Future.wait([seeking, ?next]));
        final shouldPlay =
            playing &&
            scenario != 'pauseRequested' &&
            scenario != 'immediatePause' &&
            !scenario.endsWith('Paused');
        expect(engine.currentSnapshot.isSeeking, isFalse);
        expect(engine.currentSnapshot.desiredPlaying, shouldPlay);
        expect(engine.currentSnapshot.generation, generation);
        expect(failures, isEmpty);
        expect(
          await native.getPropertyAsync('pause'),
          shouldPlay ? 'no' : 'yes',
        );
        final target = scenario == 'superseded'
            ? 2
            : scenario.startsWith('supersededAgain')
            ? 1
            : 9;
        expect(
          (engine.currentSnapshot.position - Duration(seconds: target)).abs(),
          lessThan(const Duration(milliseconds: 300)),
        );
        await tester.pump(const Duration(milliseconds: 300));
        expect(
          await _pixels(boundaryKey),
          isNot(orderedEquals(initialFrame)),
          reason:
              'The target video must replace the old frame when audio resumes',
        );
        final timing = await backend.inspectNativePlaybackTiming();
        if (shouldPlay) {
          expect(timing.avsyncSeconds, isNotNull);
          expect(timing.avsyncSeconds?.abs(), lessThan(.15));
          debugPrint(
            'SEEK_SYNC scenario=$scenario avsyncSeconds=${timing.avsyncSeconds}',
          );
        }
        expect(tester.takeException(), isNull);
      } finally {
        if (!resumeVideo.isCompleted) resumeVideo.complete();
        await subscription.cancel();
        await _withFrames(tester, engine.dispose());
        await tester.pumpWidget(const SizedBox.shrink());
        await server.close(force: true);
        if (Platform.isAndroid) {
          // Separate source teardown stress from the same-player seek burst.
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
    });
  }
}

Future<List<int>> _pixels(GlobalKey key) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: .1);
  try {
    final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final samples = <int>[];
    for (var i = 0; i < data.lengthInBytes; i += 16) {
      samples.add(
        data.getUint8(i) + data.getUint8(i + 1) + data.getUint8(i + 2),
      );
    }
    expect(
      samples.where((value) => value > 100).length,
      greaterThan(samples.length ~/ 10),
    );
    return samples;
  } finally {
    image.dispose();
  }
}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  StackTrace? stack;
  final result = operation.then<void>(
    (_) => done = true,
    onError: (Object error, StackTrace trace) {
      failure = error;
      stack = trace;
      done = true;
    },
  );
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
}
