import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
// Native fault injection inspects the player's pinned transitive renderer.
// ignore: depend_on_referenced_packages
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import '../test/support/window_service_fake.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'temporary video underrun waits with audio then resumes together',
    (tester) => _runBuffering(tester),
  );
  testWidgets(
    'temporary video underrun retains its frame with a lagging buffer event',
    (tester) => _runBuffering(tester, laggingBuffer: true),
  );
  testWidgets(
    'repeated forward and backward network seeks retain the native pair',
    (tester) async {
      initializePlayerBackend();
      final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixtures, isNotNull);
      final engine = MediaKitEngine();
      final failures = <PlayerFailure>[];
      final subscription = engine.failures.listen(failures.add);
      final media = {
        '/video.mp4': await File('$fixtures/video.mp4').readAsBytes(),
        '/audio.m4a': await File('$fixtures/audio.m4a').readAsBytes(),
      };
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var requests = 0;
      server.listen((request) async {
        requests++;
        final bytes = media[request.uri.path]!;
        final range = request.headers.value(HttpHeaders.rangeHeader);
        final match = RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range ?? '');
        final start = int.parse(match?[1] ?? '0');
        final end = (int.tryParse(match?[2] ?? '') ?? bytes.length - 1).clamp(
          start,
          bytes.length - 1,
        );
        final response = request.response;
        response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
        response.contentLength = end - start + 1;
        if (range != null) {
          response.statusCode = 206;
          response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes $start-$end/${bytes.length}',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 350));
        try {
          response.add(bytes.sublist(start, end + 1));
          await response.close();
        } on SocketException {
          // Seeking can cancel an older range request.
        }
      });
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
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
            const OpenOptions(
              play: true,
              volume: 0,
              maxBufferAhead: Duration(seconds: 1),
            ),
          ),
        );
        final generation = engine.currentSnapshot.generation;
        for (final rate in [1.0, 2.0, 4.0, 8.0]) {
          await _withFrames(tester, engine.setRate(rate));
          for (final second in [1, 4, 7, 2, 5, 8]) {
            await _withFrames(tester, engine.seek(Duration(seconds: second)));
            await tester.pump(const Duration(milliseconds: 300));
            expect(engine.currentSnapshot.isSeeking, isFalse);
            expect(engine.currentSnapshot.generation, generation);
            expect(failures, isEmpty);
          }
        }
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
        expect(
          requests,
          greaterThan(2),
          reason: 'Exercise uncached HTTP seeks',
        );
        expect(tester.takeException(), isNull);
      } finally {
        await subscription.cancel();
        await _withFrames(tester, engine.dispose());
        await tester.pumpWidget(const SizedBox.shrink());
        await server.close(force: true);
      }
    },
  );

  for (final audioFault in [false, true]) {
    for (final automatic in [false, true]) {
      testWidgets(
        'truncated DASH ${audioFault ? 'audio' : 'video'} stops pair; automatic=$automatic',
        (tester) => _runStall(tester, automatic, audioFault),
      );
    }
  }

  for (final automatic in [false, true]) {
    testWidgets(
      'silent buffered clock freeze; automatic=$automatic',
      (tester) => _runSilentStall(tester, automatic: automatic),
    );
  }
}

Future<void> _runSilentStall(
  WidgetTester tester, {
  required bool automatic,
}) async {
  initializePlayerBackend();
  final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
  expect(fixtures, isNotNull);
  final source = DashPairSource(
    video: MediaTrack(
      uri: File('$fixtures/video.mp4').uri,
      requestPolicy: MediaRequestPolicy(),
    ),
    audio: MediaTrack(
      uri: File('$fixtures/audio.m4a').uri,
      requestPolicy: MediaRequestPolicy(),
    ),
  );
  final events = <PlayerDiagnosticEvent>[];
  final failures = <PlayerFailure>[];
  final engine = MediaKitEngine(onDiagnostic: events.add);
  final subscription = engine.failures.listen(failures.add);
  final session = automatic
      ? PlaybackSession(
          engine: engine,
          repository: _FixtureRepository(source),
          progress: _MemoryProgress(),
          accountScope: () => 'guest',
        )
      : null;
  session?.configureSettings(
    AppSettings(autoPlay: true, resumePlayback: false),
  );
  try {
    await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
    await _withFrames(
      tester,
      session == null
          ? engine.open(source, const OpenOptions(play: true, volume: 0))
          : session.open(_detail, _part, volume: 0),
    );
    final watch = Stopwatch()..start();
    while (engine.currentSnapshot.position < const Duration(seconds: 1) &&
        watch.elapsed < const Duration(seconds: 5)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
      engine.currentSnapshot.position,
      greaterThanOrEqualTo(const Duration(seconds: 1)),
    );
    expect(
      engine.currentSnapshot.buffered - engine.currentSnapshot.position,
      greaterThan(const Duration(seconds: 8)),
    );
    final generation = engine.currentSnapshot.generation;
    final frozenAt = engine.currentSnapshot.position;
    // Fault injection outside the engine: retain its playback intent, emit no
    // error, and leave a full demuxer cache. This is not a GPU-driver repro.
    final native = tester
        .widget<mkv.Video>(find.byType(mkv.Video))
        .controller
        .player;
    // The pinned core maps core-idle to buffering, including an explicit
    // native pause. Suppress that one transition, as its pause adapter does,
    // to model this issue's buffering=false signature.
    native.native.isBufferingStateChangeAllowed = false;
    native.setProperty('pause', 'yes');
    watch.reset();
    while ((failures.isEmpty ||
            automatic &&
                (engine.currentSnapshot.generation == generation ||
                    engine.currentSnapshot.position <
                        frozenAt + const Duration(seconds: 1))) &&
        watch.elapsed < const Duration(seconds: 15)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'SILENT_STALL_FINAL ${PlayerDiagnosticEvent(kind: PlayerDiagnosticKind.nativeLog, snapshot: engine.currentSnapshot).toJson()} '
      'events=${events.map((e) => e.kind.name).toList()}',
    );
    expect(failures, hasLength(1));
    expect(failures.single.kind, PlayerFailureKind.nativePlayback);
    final stall = events.singleWhere(
      (e) => e.kind == PlayerDiagnosticKind.playbackStalled,
    );
    expect(stall.stallReason, PlaybackStallReason.playbackClock);
    expect(stall.snapshot.isBuffering, false);
    expect(stall.snapshot.desiredPlaying, true);
    expect(stall.stalledFor!.inMilliseconds, inInclusiveRange(2000, 2250));
    if (automatic) {
      expect(engine.currentSnapshot.generation, greaterThan(generation));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(
        engine.currentSnapshot.position,
        greaterThanOrEqualTo(frozenAt + const Duration(seconds: 1)),
      );
    } else {
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      final stoppedAt = engine.inspectDiagnostics().position;
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (engine.inspectDiagnostics().position - stoppedAt).abs(),
        lessThan(const Duration(milliseconds: 100)),
      );
    }
    debugPrint(
      'SILENT_STALL automatic=$automatic '
      'reason=${stall.stallReason?.name} elapsedMs=${stall.stalledFor?.inMilliseconds} '
      'reopened=${engine.currentSnapshot.generation > generation}',
    );
  } finally {
    session?.dispose();
    await subscription.cancel();
    await _withFrames(tester, engine.dispose());
    await tester.pumpWidget(const SizedBox.shrink());
  }
}

Future<void> _runBuffering(
  WidgetTester tester, {
  bool laggingBuffer = false,
}) async {
  initializePlayerBackend();
  final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
  expect(fixtures, isNotNull);
  final bytes = await File('$fixtures/video.mp4').readAsBytes();
  final cutoff = bytes.length ~/ 3;
  final resume = Completer<void>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final start = range == null
        ? 0
        : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    final response = request.response;
    response.bufferOutput = false;
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType('video', 'mp4');
    response.contentLength = bytes.length - start;
    if (range != null) {
      response.statusCode = 206;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }
    try {
      if (start < cutoff) response.add(bytes.sublist(start, cutoff));
      await response.flush();
      await resume.future;
      response.add(bytes.sublist(start < cutoff ? cutoff : start));
      await response.close();
    } on SocketException {
      // A cancelled player closes its HTTP request before fixture cleanup.
    }
  });
  final failures = <PlayerFailure>[];
  final engine = MediaKitEngine();
  final subscription = engine.failures.listen(failures.add);
  final boundaryKey = GlobalKey();
  final source = DashPairSource(
    video: MediaTrack(
      uri: Uri.parse('http://127.0.0.1:${server.port}/video.mp4'),
      requestPolicy: MediaRequestPolicy(),
    ),
    audio: MediaTrack(
      uri: File('$fixtures/audio.m4a').uri,
      requestPolicy: MediaRequestPolicy(),
    ),
  );
  final session = PlaybackSession(
    engine: engine,
    repository: _FixtureRepository(source),
    progress: _MemoryProgress(),
    accountScope: () => 'guest',
  );
  final window = FakePlaybackWindowService(
    viewId: 0,
    setFullScreen: (_) async {},
    activate: () async {},
  );
  try {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: MaterialApp(
          home: VideoCompositionScope(
            adapter: _FrameProbeComposition(boundaryKey),
            child: PlaybackPanel(
              detail: _detail,
              part: _part,
              settings: AppSettings(
                autoPlay: true,
                resumePlayback: false,
                defaultPlaybackRate: 2,
                defaultVolume: 0,
                danmakuEnabled: false,
                playerControlsMode: PlayerControlsMode.click,
              ),
              onToggleComments: () {},
              window: window,
            ),
          ),
        ),
      ),
    );
    final watch = Stopwatch()..start();
    while ((!engine.currentSnapshot.isBuffering ||
            engine.currentSnapshot.position < const Duration(seconds: 2)) &&
        watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(engine.currentSnapshot.isBuffering, true);
    expect(engine.currentSnapshot.position, greaterThan(Duration.zero));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('网络缓冲中…'), findsOneWidget);
    final surfaceState = tester.state(find.byType(VideoSurface));
    final textureId = tester.widget<Texture>(find.byType(Texture)).textureId;
    final generation = engine.currentSnapshot.generation;
    if (laggingBuffer) {
      // Position, cache and audio clocks arrive independently. Exercise a late
      // cache sample while the real native pair is already waiting for data.
      final native = tester
          .widget<mkv.Video>(find.byType(mkv.Video))
          .controller
          .player;
      // Fault injection only; production never writes the SDK event streams.
      // ignore: invalid_use_of_protected_member
      native.platform!.bufferController.add(
        engine.currentSnapshot.position - const Duration(seconds: 1),
      );
    }
    final readiness = engine.videoOutput as VideoFrameReadiness;
    Future<List<int>> readFrame() async {
      expect(tester.state(find.byType(VideoSurface)), same(surfaceState));
      expect(tester.widget<Texture>(find.byType(Texture)).textureId, textureId);
      expect(readiness.frameReady.value, isTrue);
      final boundary =
          boundaryKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: .25);
      try {
        final pixels = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final samples = <int>[];
        for (var i = 0; i < pixels.lengthInBytes; i += 16) {
          samples.add(
            pixels.getUint8(i) +
                pixels.getUint8(i + 1) +
                pixels.getUint8(i + 2),
          );
        }
        expect(
          samples.where((value) => value > 100).length,
          greaterThan(samples.length ~/ 10),
          reason: 'An underrun must retain the last video frame',
        );
        return samples;
      } finally {
        image.dispose();
      }
    }

    await tester.pump(const Duration(milliseconds: 500));
    final heldFrame = await readFrame();
    final waitingAt = engine.currentSnapshot.position;
    // A usable TCP connection may be quiet for more than the old 8s failure
    // threshold. Retain the already loaded pair and recover without a reopen.
    final nativeWaitingAt = engine.inspectDiagnostics().position;
    await tester.pump(const Duration(seconds: 9));
    expect(await readFrame(), orderedEquals(heldFrame));
    expect(
      (engine.currentSnapshot.position - waitingAt).abs(),
      lessThan(const Duration(milliseconds: 250)),
    );
    expect(failures, isEmpty);
    expect(
      (engine.inspectDiagnostics().position - nativeWaitingAt).abs(),
      lessThan(const Duration(milliseconds: 250)),
    );
    resume.complete();
    watch.reset();
    // A backend's position sample can land exactly on six seconds. Keep
    // waiting until it satisfies the strict progress assertion below.
    while (engine.currentSnapshot.position <= const Duration(seconds: 6) &&
        watch.elapsed < const Duration(seconds: 10)) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    expect(
      engine.currentSnapshot.position,
      greaterThan(const Duration(seconds: 6)),
    );
    expect(failures, isEmpty);
    expect(engine.currentSnapshot.generation, generation);
    expect(find.text('网络缓冲中…'), findsNothing);
    expect(await readFrame(), isNot(orderedEquals(heldFrame)));
    debugPrint(
      'TEMPORARY_VIDEO_BUFFER waitedAtMs=${waitingAt.inMilliseconds} '
      'resumedAtMs=${engine.currentSnapshot.position.inMilliseconds} '
      'laggingBuffer=$laggingBuffer failures=0',
    );
  } finally {
    if (!resume.isCompleted) resume.complete();
    await subscription.cancel();
    await tester.pumpWidget(const SizedBox.shrink());
    await _withFrames(tester, session.close());
    await server.close(force: true);
  }
}

final class _FrameProbeComposition implements VideoCompositionAdapter {
  const _FrameProbeComposition(this.key);
  final GlobalKey key;

  @override
  Widget buildVideoSurface(BuildContext context, VideoOutput output) =>
      RepaintBoundary(
        key: key,
        child: const FlutterVideoCompositionAdapter().buildVideoSurface(
          context,
          output,
        ),
      );

  @override
  Widget compose(BuildContext context, {required List<Widget> layers}) =>
      const FlutterVideoCompositionAdapter().compose(context, layers: layers);
}

Future<void> _runStall(
  WidgetTester tester,
  bool automatic,
  bool audioFault,
) async {
  initializePlayerBackend();
  final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
  expect(fixtures, isNotNull);
  final bytes = await File(
    '$fixtures/${audioFault ? 'audio.m4a' : 'video.mp4'}',
  ).readAsBytes();
  final cutoff = bytes.length ~/ 3;
  var broken = true;
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final range = request.headers.value(HttpHeaders.rangeHeader);
    final start = range == null
        ? 0
        : int.parse(RegExp(r'bytes=(\d+)-').firstMatch(range)!.group(1)!);
    final response = request.response;
    if (broken && start >= cutoff) {
      response.statusCode = 503;
      await response.close();
      return;
    }
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.contentType = ContentType('video', 'mp4');
    response.contentLength = bytes.length - start;
    if (range != null) {
      response.statusCode = 206;
      response.headers.set(
        HttpHeaders.contentRangeHeader,
        'bytes $start-${bytes.length - 1}/${bytes.length}',
      );
    }
    if (broken) {
      final socket = await response.detachSocket();
      socket.add(bytes.sublist(start, cutoff));
      await socket.flush();
      socket.destroy();
    } else {
      response.add(bytes.sublist(start));
      await response.close();
    }
  });
  final events = <PlayerDiagnosticEvent>[];
  final failures = <PlayerFailure>[];
  final engine = MediaKitEngine(onDiagnostic: events.add);
  final subscription = engine.failures.listen((failure) {
    failures.add(failure);
    // The replacement request succeeds, without changing the active URL.
    if (automatic) broken = false;
  });
  final source = DashPairSource(
    video: MediaTrack(
      uri: audioFault
          ? File('$fixtures/video.mp4').uri
          : Uri.parse('http://127.0.0.1:${server.port}/video.mp4'),
      requestPolicy: MediaRequestPolicy(),
    ),
    audio: MediaTrack(
      uri: audioFault
          ? Uri.parse('http://127.0.0.1:${server.port}/audio.m4a')
          : File('$fixtures/audio.m4a').uri,
      requestPolicy: MediaRequestPolicy(),
    ),
  );
  final session = automatic
      ? PlaybackSession(
          engine: engine,
          repository: _FixtureRepository(source),
          progress: _MemoryProgress(),
          accountScope: () => 'guest',
        )
      : null;
  session?.configureSettings(
    AppSettings(autoPlay: true, resumePlayback: false),
  );
  try {
    await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
    await _withFrames(
      tester,
      session == null
          ? engine.open(source, const OpenOptions(play: true, volume: 0))
          : session.open(_detail, _part, volume: 0),
    );
    final initialGeneration = engine.currentSnapshot.generation;
    final watch = Stopwatch()..start();
    bool done() =>
        failures.isNotEmpty &&
        (!automatic ||
            engine.currentSnapshot.phase == PlaybackPhase.playing &&
                engine.currentSnapshot.position > const Duration(seconds: 6));
    while (watch.elapsed < const Duration(seconds: 20) && !done()) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'TRUNCATED_VIDEO phase=${engine.currentSnapshot.phase.name} '
      'positionMs=${engine.currentSnapshot.position.inMilliseconds} '
      'bufferedMs=${engine.currentSnapshot.buffered.inMilliseconds} '
      'failures=${failures.length}',
    );
    expect(failures, hasLength(1));
    expect(
      failures.single.kind,
      audioFault
          ? PlayerFailureKind.nativePlayback
          : PlayerFailureKind.videoInterrupted,
    );
    if (!audioFault) {
      expect(
        events.any((e) => e.kind == PlayerDiagnosticKind.videoInterrupted),
        true,
      );
    }
    if (automatic) {
      expect(session?.error, isNull);
      expect(engine.currentSnapshot.generation, greaterThan(initialGeneration));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(
        engine.currentSnapshot.position,
        greaterThan(const Duration(seconds: 6)),
      );
      expect(engine.inspectDiagnostics().hasDecodedVideo, true);
      expect(tester.takeException(), isNull);
      return;
    }
    expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
    final stoppedAt = engine.currentSnapshot.position;
    // Failed snapshots deliberately freeze their checkpoint. Read media_kit's
    // independent native position as well, so that freeze cannot hide audio
    // continuing to play underneath a failed application snapshot.
    final nativeStoppedAt = engine.inspectDiagnostics().position;
    await tester.pump(const Duration(seconds: 1));
    expect(
      (engine.currentSnapshot.position - stoppedAt).inMilliseconds.abs(),
      lessThan(250),
    );
    expect(
      (engine.inspectDiagnostics().position - nativeStoppedAt).abs(),
      lessThan(const Duration(milliseconds: 250)),
    );

    broken = false;
    await _withFrames(
      tester,
      engine.open(
        source,
        const OpenOptions(
          play: true,
          volume: 0,
          startPosition: Duration(seconds: 2),
          rate: 2,
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    expect(engine.currentSnapshot.position, greaterThan(stoppedAt));
    expect(engine.inspectDiagnostics().hasDecodedVideo, true);
    expect(failures, hasLength(1));
    expect(tester.takeException(), isNull);
  } finally {
    await subscription.cancel();
    await _withFrames(
      tester,
      session == null ? engine.dispose() : session.close(),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await server.close(force: true);
  }
}

const _part = VideoPart(
  cid: 'fixture',
  page: 1,
  title: 'fixture',
  duration: Duration(seconds: 12),
);
final _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1234567890'),
    title: 'fixture',
    coverUrl: '',
    author: '',
    duration: const Duration(seconds: 12),
  ),
  description: '',
  parts: const [_part],
);

final class _FixtureRepository implements PlaybackRepository {
  _FixtureRepository(this.source);
  final DashPairSource source;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [source.video.uri],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [source.audio!.uri],
      codec: 'mp4a',
      bandwidth: 128,
    ),
    quality: quality,
    qualities: [quality],
    duration: _part.duration,
    headers: const {},
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
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => [];
}

final class _MemoryProgress implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;
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
  final result = operation.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}
