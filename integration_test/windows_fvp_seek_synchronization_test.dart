import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() => registerFvpSeekSynchronizationTests();

void registerFvpSeekSynchronizationTests({
  String? mediaDirectory,
  String delayedTrack = 'video',
  int targetMilliseconds = 9375,
  List<String>? scenarios,
  AndroidVideoOutputMode androidVideoOutput =
      AndroidVideoOutputMode.renderedTexture,
}) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final scenario
      in scenarios ??
          [
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
    testWidgets(
      'fvp waits for decoded $delayedTrack target before resuming both tracks: $scenario, ${androidVideoOutput.name}',
      (tester) async {
        initializePlayerBackend();
        final fixtures =
            mediaDirectory ?? Platform.environment['BILI_TEST_MEDIA_DIR']!;
        final video = await File('$fixtures/video.mp4').readAsBytes();
        final audio = await File('$fixtures/audio.m4a').readAsBytes();
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final blocked = Completer<void>();
        final resumeVideo = Completer<void>();
        final secondBlocked = Completer<void>();
        var blockedRequests = 0;
        var delayVideo = false;
        server.listen((request) async {
          final bytes = request.uri.path == '/audio.m4a' ? audio : video;
          final range = request.headers.value(HttpHeaders.rangeHeader);
          final start = range == null
              ? 0
              : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
          final response = request.response;
          response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
          response.contentLength = bytes.length - start;
          if (range != null) {
            response.statusCode = 206;
            response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes $start-${bytes.length - 1}/${bytes.length}',
            );
          }
          if (delayVideo && request.uri.path.startsWith('/$delayedTrack.')) {
            blockedRequests++;
            if (blockedRequests == 2) secondBlocked.complete();
            if (!blocked.isCompleted) blocked.complete();
            await resumeVideo.future;
          }
          try {
            response.add(bytes.sublist(start));
            await response.close();
          } on SocketException {
            // Cancelled seeks and teardown close the old range request.
          }
        });
        late _ObservedPlayer native;
        final engine = ConfigurablePlayerEngine(
          createEngine: () async => FvpEngine(
            createPlayer: () async =>
                native = _ObservedPlayer(await createFvpNativePlayer()),
          ),
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
                  uri: Uri.parse('http://127.0.0.1:${server.port}/audio.m4a'),
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
          delayVideo = true;
          var seekCompleted = false;
          final seeking = engine
              .seek(Duration(milliseconds: targetMilliseconds))
              .then((_) {
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
          final clockBefore = native.positionMilliseconds;
          await tester.pump(const Duration(milliseconds: 1500));
          final clockAfter = native.positionMilliseconds;
          expect(
            seekCompleted,
            isFalse,
            reason: 'Position alone cannot finish a seek',
          );
          expect(engine.currentSnapshot.isSeeking, isTrue);
          expect(
            native.playing,
            isFalse,
            reason: 'Wait for video with both tracks paused',
          );
          final clockSettled = (clockAfter - clockBefore).abs() < 100;
          // The Android worker reports positions asynchronously. Its first
          // target-position sample may arrive after clockBefore was captured;
          // allow that discrete seek jump, but no playback beyond the target.
          expect(
            clockSettled ||
                Platform.isAndroid &&
                    (clockAfter - targetMilliseconds).abs() < 100,
            isTrue,
            reason: 'The paused clock may jump to the target, not play past it',
          );
          await _pixels(boundaryKey);
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
            // Direct decoder Surfaces on Android can clear their old image
            // while media is unloaded. The final target stays pixel-checked.
            if (!Platform.isAndroid) await _pixels(boundaryKey);
            if (scenario.endsWith('Stopped')) {
              await _withFrames(tester, engine.stop());
              await _withFrames(tester, Future.wait([seeking, next!]));
              expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
              expect(engine.currentSnapshot.desiredPlaying, false);
              expect(failures, isEmpty);
              return;
            }
            delayVideo = false;
            final intermediate = next!;
            next = Future.wait([
              intermediate,
              engine.seek(const Duration(milliseconds: 375)),
              if (scenario.endsWith('Paused')) engine.pause(),
            ]);
          }
          if (scenario.startsWith('superseded')) {
            // The old response stays blocked while the new target prepares.
            await _withFrames(
              tester,
              seeking.timeout(const Duration(milliseconds: 500)),
            );
            await _withFrames(
              tester,
              next!.timeout(const Duration(seconds: 3)),
            );
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
          expect(native.playing, shouldPlay);
          final target = switch (scenario) {
            'superseded' => 2000,
            'supersededAgain' || 'supersededAgainPaused' => 375,
            _ => targetMilliseconds,
          };
          expect(
            (engine.currentSnapshot.position - Duration(milliseconds: target))
                .abs(),
            lessThan(const Duration(milliseconds: 300)),
          );
          await tester.pump(const Duration(milliseconds: 300));
          expect(
            native.positionMilliseconds,
            closeTo(target + (shouldPlay ? 300 : 0), 300),
            reason:
                'The MDK clock must not include time spent waiting for video',
          );
          final audioPosition = native.audioPositionMilliseconds;
          expect(audioPosition, isNotNull);
          expect(
            (native.positionMilliseconds - audioPosition!).abs(),
            lessThanOrEqualTo(120),
            reason: 'The target video must follow the actual audio clock',
          );
          expect(
            await _pixels(boundaryKey),
            isNot(orderedEquals(initialFrame)),
            reason: 'The target video must replace the old frame when audio resumes',
          );
          expect(native.maxPendingSeeks, 1);
          expect(native.textureCreations, 1);
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
      },
    );
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

// Observe the real port's commands without replacing MDK decoding or its seek
// callback. No additional native player or playback clock is introduced.
final class _ObservedPlayer implements FvpPlayerPort, FvpAudioClockPort {
  _ObservedPlayer(this.delegate);
  final FvpPlayerPort delegate;
  bool playing = false;
  @override
  int? get audioPositionMilliseconds => delegate is FvpAudioClockPort
      ? (delegate as FvpAudioClockPort).audioPositionMilliseconds
      : null;
  int pendingSeeks = 0;
  int maxPendingSeeks = 0;
  int textureCreations = 0;
  @override
  Stream<FvpNativeStatus> get statuses => delegate.statuses;
  @override
  int get positionMilliseconds => delegate.positionMilliseconds;
  @override
  int get bufferedMilliseconds => delegate.bufferedMilliseconds;
  @override
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    bool isLive = false,
  }) => delegate.prepare(media, audio, options, silent: silent, isLive: isLive);
  @override
  Future<int> createTexture() {
    textureCreations++;
    return delegate.createTexture();
  }

  @override
  Future<bool> confirmVideoFrame() => delegate.confirmVideoFrame();
  @override
  Future<bool> confirmAudio() => delegate.confirmAudio();
  @override
  void play() {
    playing = true;
    delegate.play();
  }

  @override
  void pause() {
    playing = false;
    delegate.pause();
  }

  @override
  Future<void> pauseAndWait() {
    playing = false;
    return delegate.pauseAndWait();
  }

  @override
  void interrupt() {
    playing = false;
    delegate.interrupt();
  }

  @override
  Future<int> seek(Duration target) async {
    // The port owns seek's native pause. Clock/pixel assertions above verify
    // that pause independently of this command ledger.
    playing = false;
    pendingSeeks++;
    if (pendingSeeks > maxPendingSeeks) maxPendingSeeks = pendingSeeks;
    try {
      return await delegate.seek(target);
    } finally {
      pendingSeeks--;
    }
  }

  @override
  Future<void> cancelSeek() => delegate.cancelSeek();

  @override
  void setRate(double rate) => delegate.setRate(rate);
  @override
  void setVolume(double volume, double gainDb) =>
      delegate.setVolume(volume, gainDb);
  @override
  Future<void> dispose() => delegate.dispose();
}
