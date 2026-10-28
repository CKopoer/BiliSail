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
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final automatic in [false, true]) {
    testWidgets(
      'truncated DASH video stops audio; automatic=$automatic',
      (tester) => _runStall(tester, automatic),
    );
  }
}

Future<void> _runStall(WidgetTester tester, bool automatic) async {
  initializePlayerBackend();
  final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
  expect(fixtures, isNotNull);
  final bytes = await File('$fixtures/video.mp4').readAsBytes();
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
      uri: Uri.parse('http://127.0.0.1:${server.port}/video.mp4'),
      requestPolicy: MediaRequestPolicy(),
    ),
    audio: MediaTrack(
      uri: File('$fixtures/audio.m4a').uri,
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
    while (watch.elapsed < const Duration(seconds: 12) && !done()) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    debugPrint(
      'TRUNCATED_VIDEO phase=${engine.currentSnapshot.phase.name} '
      'positionMs=${engine.currentSnapshot.position.inMilliseconds} '
      'bufferedMs=${engine.currentSnapshot.buffered.inMilliseconds} '
      'failures=${failures.length}',
    );
    expect(failures, hasLength(1));
    expect(failures.single.kind, PlayerFailureKind.videoInterrupted);
    expect(
      events.any((e) => e.kind == PlayerDiagnosticKind.videoInterrupted),
      true,
    );
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
    await tester.pump(const Duration(seconds: 1));
    expect(
      (engine.currentSnapshot.position - stoppedAt).inMilliseconds.abs(),
      lessThan(250),
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
