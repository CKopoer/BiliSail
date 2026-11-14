import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/logging/playback_diagnostic_log.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('corrupt live video automatically reopens a healthy fresh stream', (
    tester,
  ) async {
    initializePlayerBackend();
    final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR'];
    expect(directory, isNotNull, reason: 'Use tool/test-windows-content.ps1');
    final good = await File('$directory/live.flv').readAsBytes();
    final bad = Uint8List.fromList(good);
    var corrupted = 0;
    for (var offset = 13; offset + 16 < bad.length;) {
      final size =
          bad[offset + 1] << 16 | bad[offset + 2] << 8 | bad[offset + 3];
      final timestamp =
          bad[offset + 7] << 24 |
          bad[offset + 4] << 16 |
          bad[offset + 5] << 8 |
          bad[offset + 6];
      if (bad[offset] == 9 &&
          size > 9 &&
          (bad[offset + 11] & 15) == 7 &&
          bad[offset + 12] == 1 &&
          timestamp >= 4500) {
        // Corrupt the AVCC NAL length, preserving FLV tag boundaries and AAC.
        // Startup is valid; real FFmpeg video errors begin during playback.
        ByteData.sublistView(bad)
            .setUint32(offset + 16, 0x7ffffff0, Endian.big);
        corrupted++;
      }
      offset += 11 + size + 4;
    }
    expect(corrupted, greaterThan(10));
    final finish = Completer<void>();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var badRequests = 0, goodRequests = 0;
    server.listen((request) async {
      final broken = request.uri.path == '/bad.flv';
      if (broken) {
        badRequests++;
      } else {
        goodRequests++;
      }
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType('video', 'x-flv');
      try {
        request.response.add(broken ? bad : good);
        await request.response.flush();
        // Keep the bad live connection open: natural EOF must not trigger recovery.
        if (broken) await finish.future;
        await request.response.close();
      } on SocketException {
        // A recovered/closed player cancels the retired HTTP reader.
      } on HttpException {
        // Cleanup can retire an in-flight response.
      }
    });
    final repository = _LiveRepository(server.port);
    final events = <PlayerDiagnosticEvent>[];
    final output = Directory(
      '${Directory.current.path}/build/validation/live-buffering-2026-11-14/native-recovery',
    );
    final log = PlaybackDiagnosticLog(output);
    final engine = MediaKitEngine(
      onDiagnostic: (event) {
        events.add(event);
        log.record(event);
      },
    );
    final failures = <PlayerFailure>[];
    final subscription = engine.failures.listen(failures.add);
    final session = PlaybackSession(
      engine: engine,
      repository: _UnusedRepository(),
      contentRepository: repository,
      progress: _UnusedProgress(),
      accountScope: () => 'guest',
    );
    session.configureSettings(
      AppSettings(autoPlay: true, resumePlayback: false),
    );
    try {
      await tester.pumpWidget(MaterialApp(home: VideoSurface(engine: engine)));
      await _withFrames(
        tester,
        session.open(
          null,
          null,
          target: const LivePlaybackTarget('1'),
          volume: 0,
        ),
      );
      final generation = engine.currentSnapshot.generation;
      final watch = Stopwatch()..start();
      while ((engine.currentSnapshot.generation == generation ||
              engine.currentSnapshot.phase != PlaybackPhase.playing ||
              engine.currentSnapshot.position < const Duration(seconds: 2)) &&
          watch.elapsed < const Duration(seconds: 45)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        events.any(
          (e) =>
              e.nativeError?.component == 'ffmpeg/video' &&
              e.severity == NativeLogSeverity.error,
        ),
        isTrue,
        reason: 'Exercise the real SDK log path',
      );
      expect(failures, hasLength(1));
      expect(repository.resolutions, 2);
      expect(badRequests, 1);
      expect(goodRequests, 1);
      expect(engine.currentSnapshot.generation, greaterThan(generation));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(
        engine.currentSnapshot.position,
        greaterThanOrEqualTo(const Duration(seconds: 2)),
      );
      expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
      expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
      expect(session.error, isNull);
      final text = jsonEncode(events.map((e) => e.toJson()).toList());
      expect(text, isNot(contains('synthetic-secret')));
      expect(text, isNot(contains('127.0.0.1')));
      debugPrint(
        'LIVE_DECODER_RECOVERY errors=${events.where((e) => e.nativeError?.component == 'ffmpeg/video').length} '
        'failures=${failures.length} resolutions=${repository.resolutions} '
        'badRequests=$badRequests goodRequests=$goodRequests elapsedMs=${watch.elapsedMilliseconds} '
        'reopened=${engine.currentSnapshot.generation > generation}',
      );
    } finally {
      if (!finish.isCompleted) finish.complete();
      await subscription.cancel();
      await _withFrames(tester, session.close());
      await tester.pumpWidget(const SizedBox.shrink());
      await log.close();
      await server.close(force: true);
    }
  });
}

final class _LiveRepository implements ContentPlaybackRepository {
  _LiveRepository(this.port);
  final int port;
  int resolutions = 0;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    final path = ++resolutions == 1 ? 'bad' : 'good';
    return PlaybackMedia(
      video: PlaybackTrack(
        urls: [
          Uri.parse('http://127.0.0.1:$port/$path.flv?token=synthetic-secret'),
        ],
        codec: 'avc1',
        bandwidth: 0,
      ),
      audio: null,
      quality: 80,
      qualities: const [80],
      duration: Duration.zero,
      headers: const {},
      kind: PlaybackMediaKind.liveFlv,
    );
  }
}

final class _UnusedRepository extends Fake implements PlaybackRepository {}

final class _UnusedProgress extends Fake implements PlaybackProgressStore {}

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  final result = operation.whenComplete(() => done = true);
  while (!done) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  await result;
}
