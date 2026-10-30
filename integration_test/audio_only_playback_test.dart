import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'listening requests only audio, then restores paused DASH video',
    (tester) async {
      initializePlayerBackend();
      final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixtures, isNotNull);
      final files = {
        '/video.mp4': await File('$fixtures/video.mp4').readAsBytes(),
        '/audio.m4a': await File('$fixtures/audio.m4a').readAsBytes(),
      };
      final observed = <String>[];
      var forbiddenHeaders = 0;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        observed.add(request.uri.path);
        final bytes = files[request.uri.path];
        if (request.headers.value('referer') != 'https://www.bilibili.com/') {
          forbiddenHeaders++;
          request.response.statusCode = 403;
        } else if (bytes == null) {
          request.response.statusCode = 404;
        } else {
          final range = RegExp(r'^bytes=(\d+)-(\d*)$')
              .firstMatch(request.headers.value('range') ?? '');
          final start = int.tryParse(range?.group(1) ?? '') ?? 0;
          final requestedEnd =
              int.tryParse(range?.group(2) ?? '') ?? bytes.length - 1;
          final end = requestedEnd.clamp(0, bytes.length - 1);
          if (start > end) {
            request.response.statusCode = 416;
          } else {
            request.response.headers.set('Accept-Ranges', 'bytes');
            request.response.headers.contentType = ContentType(
              request.uri.path == '/audio.m4a' ? 'audio' : 'video',
              'mp4',
            );
            if (range != null) {
              request.response.statusCode = 206;
              request.response.headers.set(
                'Content-Range',
                'bytes $start-$end/${bytes.length}',
              );
            }
            request.response.contentLength = end - start + 1;
            request.response.add(bytes.sublist(start, end + 1));
          }
        }
        await request.response.close();
      });
      final diagnostics = <PlayerDiagnosticEvent>[];
      final engine = MediaKitEngine(onDiagnostic: diagnostics.add);
      final session = PlaybackSession(
        engine: engine,
        repository: _Repository(server.port),
        progress: _Progress(),
        accountScope: () => 'guest',
      );
      session.configureSettings(
        AppSettings(autoPlay: true, resumePlayback: false),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ListenableBuilder(
              listenable: session,
              builder: (_, _) => session.audioOnly
                  ? const ColoredBox(color: Colors.black)
                  : VideoSurface(engine: engine),
            ),
          ),
        );
        await _withFrames(tester, session.open(_detail, _part));
        expect(session.error, isNull);
        expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
        await _withFrames(tester, session.pause());
        await _withFrames(tester, session.seek(const Duration(seconds: 2)));
        await _withFrames(tester, session.setRate(1.5));
        await _withFrames(tester, session.setVolume(3));
        observed.clear();
        await _withFrames(tester, session.setAudioOnly(true));
        expect(session.error, isNull);
        expect(session.audioOnly, isTrue);
        expect(observed, isNotEmpty);
        expect(observed.every((path) => path == '/audio.m4a'), isTrue);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        await _withFrames(tester, session.togglePlaying());
        for (
          var i = 0;
          i < 40 && !engine.inspectDiagnostics().hasDecodedAudio;
          i++
        ) {
          await tester.pump(const Duration(milliseconds: 25));
        }
        expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
        expect(engine.inspectDiagnostics().hasDecodedVideo, isFalse);
        expect(engine.inspectDiagnostics().hasVideoOutput, isFalse);
        expect(engine.currentSnapshot.rate, 1.5);
        expect(engine.currentSnapshot.volume, 3);
        expect(observed.every((path) => path == '/audio.m4a'), isTrue);
        await _withFrames(tester, session.pause());
        await _withFrames(tester, session.seek(const Duration(seconds: 2)));
        observed.clear();
        diagnostics.clear();
        final returningSnapshots = <PlaybackSnapshot>[];
        final returningSubscription = engine.snapshots.listen(
          returningSnapshots.add,
        );
        await _withFrames(tester, session.setAudioOnly(false));
        await returningSubscription.cancel();
        expect(session.error, isNull);
        expect(
          diagnostics.where(
            (event) => event.kind == PlayerDiagnosticKind.openStarted,
          ),
          hasLength(1),
        );
        expect(
          returningSnapshots.where((snapshot) => snapshot.isSeeking),
          isEmpty,
          reason: 'Returning must load at the listening position without a second seek',
        );
        expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(
          (engine.currentSnapshot.position - const Duration(seconds: 2))
              .inMilliseconds
              .abs(),
          lessThan(400),
        );
        expect(observed, containsAll(['/video.mp4', '/audio.m4a']));
        for (final paused in [false, true]) {
          await _withFrames(tester, session.setAudioOnly(true));
          await _withFrames(tester, session.seek(const Duration(seconds: 2)));
          if (!paused) await _withFrames(tester, session.play());
          diagnostics.clear();
          returningSnapshots.clear();
          final subscription = engine.snapshots.listen(returningSnapshots.add);
          try {
            await _withFrames(
              tester,
              Future.wait([
                session.setAudioOnly(false),
                session.setAudioOnly(false),
              ]).then((_) {}),
            );
            expect(session.error, isNull);
            expect(engine.currentSnapshot.desiredPlaying, !paused);
            expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
            expect(
              diagnostics.where(
                (event) => event.kind == PlayerDiagnosticKind.openStarted,
              ),
              hasLength(1),
            );
            expect(returningSnapshots.any((value) => value.isSeeking), isFalse);
          } finally {
            await subscription.cancel();
          }
          await _withFrames(tester, session.pause());
        }
        // Foreground intent can change before Android delivers resumed.
        // The effective source must stay audio until the overlay is removed.
        for (final paused in [false, true]) {
          await _withFrames(tester, session.setAudioOnly(true));
          await _withFrames(tester, session.seek(const Duration(seconds: 2)));
          await _withFrames(tester, paused ? session.pause() : session.play());
          await _withFrames(tester, session.setBackgroundAudio(true));
          final sourceGeneration = session.sourceGeneration;
          final nativeGeneration = engine.currentSnapshot.generation;
          await _withFrames(tester, session.setAudioOnly(false));
          await _withFrames(tester, session.setAudioOnly(false));
          expect(session.audioOnly, isTrue);
          expect(session.sourceGeneration, sourceGeneration);
          expect(engine.currentSnapshot.generation, nativeGeneration);
          await _withFrames(tester, session.setBackgroundAudio(false));
          expect(session.error, isNull);
          expect(session.audioOnly, isFalse);
          expect(session.sourceGeneration, sourceGeneration + 1);
          expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
          expect(engine.currentSnapshot.desiredPlaying, !paused);
          expect(engine.currentSnapshot.rate, 1.5);
          expect(engine.currentSnapshot.volume, 3);
          expect(
            engine.currentSnapshot.position,
            greaterThanOrEqualTo(const Duration(milliseconds: 1500)),
          );
          await _withFrames(tester, session.pause());
        }
        await _withFrames(tester, session.play());
        final framePolicy = binding.framePolicy;
        binding.framePolicy =
            LiveTestWidgetsFlutterBindingFramePolicy.benchmark;
        var renderedInBackground = false;
        binding.addPostFrameCallback((_) => renderedInBackground = true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        try {
          expect(tester.binding.framesEnabled, isFalse);
          await tester.runAsync(() async {
            // Deliver the outgoing Video widget's lifecycle callbacks without
            // rendering a frame, as on a real backgrounded Android Activity.
            await Future<void>.delayed(const Duration(milliseconds: 50));
            expect(engine.currentSnapshot.desiredPlaying, isTrue);
            observed.clear();
            await session
                .setBackgroundAudio(true)
                .timeout(const Duration(seconds: 8));
            expect(session.error, isNull);
            expect(session.audioOnly, isTrue);
            expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
            expect(engine.inspectDiagnostics().hasVideoOutput, isFalse);
            final position = engine.currentSnapshot.position;
            await Future<void>.delayed(const Duration(milliseconds: 350));
            expect(engine.currentSnapshot.position, greaterThan(position));
            expect(observed, isNotEmpty);
            expect(observed.every((path) => path == '/audio.m4a'), isTrue);
            observed.clear();
            await session
                .open(
                  _detail,
                  const VideoPart(
                    cid: '43',
                    page: 2,
                    title: '下一 P',
                    duration: Duration(seconds: 6),
                  ),
                )
                .timeout(const Duration(seconds: 8));
            expect(session.error, isNull);
            expect(session.audioOnly, isTrue);
            expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
            expect(engine.inspectDiagnostics().hasVideoOutput, isFalse);
            expect(observed, isNotEmpty);
            expect(observed.every((path) => path == '/audio.m4a'), isTrue);
            await session.pause();
            expect(renderedInBackground, isFalse);
          });
        } finally {
          binding.framePolicy = framePolicy;
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        }
        await _withFrames(tester, session.setBackgroundAudio(false));
        expect(session.audioOnly, isFalse);
        expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(forbiddenHeaders, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await _withFrames(tester, session.close());
        await tester.pumpWidget(const SizedBox.shrink());
        await server.close(force: true);
      }
    },
  );
}

const _part = VideoPart(
  cid: '42',
  page: 1,
  title: '音频模式验证',
  duration: Duration(seconds: 6),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '音频模式验证',
    coverUrl: '',
    author: 'fixture',
    duration: Duration(seconds: 6),
  ),
  description: '',
  parts: [_part],
);

class _Repository extends Fake implements PlaybackRepository {
  _Repository(this.port);
  final int port;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri.parse('http://127.0.0.1:$port/video.mp4')],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [Uri.parse('http://127.0.0.1:$port/audio.m4a')],
      codec: 'mp4a',
      bandwidth: 128,
    ),
    quality: 80,
    qualities: const [80],
    duration: const Duration(seconds: 6),
    headers: const {'Referer': 'https://www.bilibili.com/'},
  );
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
}

class _Progress extends Fake implements PlaybackProgressStore {
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
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
  final watch = Stopwatch()..start();
  while (!done && watch.elapsed < const Duration(seconds: 50)) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done, isTrue, reason: 'Native operation timed out');
  await completion;
  if (failure case final error?) throw error;
}
