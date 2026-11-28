import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/native_player_properties.dart';
// ignore: depend_on_referenced_packages
import 'package:media_kit_video/media_kit_video.dart' as mkv;
import 'package:bilisail/core/logging/playback_diagnostic_log.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('live decoder logs preserve the open connection', (tester) async {
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
      while (!events.any(
            (e) =>
                e.nativeError?.component == 'ffmpeg/video' &&
                e.severity == NativeLogSeverity.error,
          ) &&
          watch.elapsed < const Duration(seconds: 15)) {
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
      await tester.pump(const Duration(seconds: 4));
      expect(failures, isEmpty);
      expect(repository.resolutions, 1);
      expect(badRequests, 1);
      expect(goodRequests, 0);
      expect(engine.currentSnapshot.generation, generation);
      expect(session.error, isNull);
      final player = tester
          .widget<mkv.Video>(find.byType(mkv.Video))
          .controller
          .player;
      expect(await player.getPropertyAsync('demuxer-max-bytes'), '16777216');
      expect(await player.getPropertyAsync('demuxer-max-back-bytes'), '0');
      for (var n = 0; n < 2; n++) {
        // ignore: invalid_use_of_protected_member
        player.native.errorController.add(
          'tcp: ffurl_read returned 0xffffff99',
        );
      }
      watch.reset();
      while ((badRequests < 2 || session.isRecovering) &&
          watch.elapsed < const Duration(seconds: 12)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(failures.map((e) => e.kind), [PlayerFailureKind.networkRead]);
      expect(repository.resolutions, 1);
      expect(goodRequests, 0);
      expect(badRequests, 2);
      expect(engine.currentSnapshot.generation, greaterThan(generation));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
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

  testWidgets(
    'a disconnected live FLV reopens at the live edge after the room check',
    (tester) async {
      initializePlayerBackend();
      final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR']!;
      final flv = await File('$directory/live.flv').readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <Uri>[];
      final finish = Completer<void>();
      server.listen((request) async {
        requests.add(request.uri);
        final first = requests.length == 1;
        request.response.headers.contentType = ContentType('video', 'x-flv');
        try {
          request.response.add(flv);
          await request.response.flush();
          // Withhold the next bytes from this unbounded response. A fresh
          // reader of the same URL gets a new stream starting at timestamp zero.
          if (first) await finish.future;
          await request.response.close();
        } on IOException {
          // The native player can close a timed-out response before cleanup.
        }
      });
      final repository = _LiveRepository(server.port);
      final events = <PlayerDiagnosticEvent>[];
      final engine = MediaKitEngine(onDiagnostic: events.add);
      final outcomes = <(int, LiveRecoveryOutcome)>[];
      var roomChecks = 0;
      final session = PlaybackSession(
        engine: engine,
        repository: _UnusedRepository(),
        contentRepository: repository,
        progress: _UnusedProgress(),
        accountScope: () => 'guest',
        isRoomLive: (target, _) async {
          roomChecks++;
          return target.roomId == '1';
        },
        onLiveRecovery: (generation, decision) =>
            outcomes.add((generation, decision)),
      );
      try {
        await tester.pumpWidget(
          MaterialApp(home: VideoSurface(engine: engine)),
        );
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
        bool resumed() =>
            engine.currentSnapshot.generation > generation &&
            engine.currentSnapshot.phase == PlaybackPhase.playing &&
            engine.currentSnapshot.position > const Duration(seconds: 1);
        while (!resumed() && watch.elapsed < const Duration(seconds: 30)) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(resumed(), isTrue);
        expect(requests, hasLength(2));
        expect(requests.first, requests.last);
        expect(repository.resolutions, 1);
        expect(roomChecks, 1);
        expect(outcomes, [(generation, LiveRecoveryOutcome.roomLive)]);
        final eof = events.singleWhere(
          (event) => event.kind == PlayerDiagnosticKind.endOfFile,
        );
        expect(eof.snapshot.generation, generation);
        expect(eof.sourceKind, DiagnosticSourceKind.liveProgressive);
        expect(session.error, isNull);
      } finally {
        finish.complete();
        await _withFrames(tester, session.close());
        await tester.pumpWidget(const SizedBox.shrink());
        await server.close(force: true);
      }
    },
  );

  testWidgets('a failed live playlist reload reopens the same stream once', (
    tester,
  ) async {
    initializePlayerBackend();
    final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR']!;
    final playlist = await File('$directory/fragmented.m3u8').readAsString();
    final segments = RegExp(r'#EXTINF:[^\r\n]+\r?\nfrag-\d+\.m4s')
        .allMatches(playlist)
        .map((match) => match[0]!)
        .toList();
    final header = playlist.split('#EXTINF:').first;
    final broadcast = Stopwatch()..start();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final engine = MediaKitEngine();
    int? brokenGeneration;
    var rejectedReloads = 0, recoveredRequests = 0;
    var roomChecks = 0;
    final mediaHeaders = <(String?, String?)>{};
    server.listen((request) async {
      final name = request.uri.pathSegments.last;
      mediaHeaders.add((
        request.headers.value(HttpHeaders.userAgentHeader),
        request.headers.value(HttpHeaders.refererHeader),
      ));
      request.response.persistentConnection = false;
      List<int> body = const [];
      if (name == 'live.m3u8') {
        request.response.headers.contentType = ContentType(
          'application',
          'vnd.apple.mpegurl',
        );
        if (engine.currentSnapshot.generation == brokenGeneration) {
          rejectedReloads++;
          request.response.statusCode = HttpStatus.serviceUnavailable;
          body = utf8.encode('Service unavailable');
        } else {
          if (rejectedReloads > 0) recoveredRequests++;
          final sequence = (broadcast.elapsed.inSeconds ~/ 2).clamp(
            0,
            segments.length - 5,
          );
          final window = segments.skip(sequence).take(5).join('\n');
          body = utf8.encode(
            '${header.replaceFirst('#EXT-X-MEDIA-SEQUENCE:0', '#EXT-X-MEDIA-SEQUENCE:$sequence')}$window\n',
          );
        }
      } else if (name == 'init.mp4' ||
          RegExp(r'^frag-\d+\.m4s$').hasMatch(name)) {
        request.response.headers.contentType = ContentType('video', 'mp4');
        body = await File('$directory/$name').readAsBytes();
      } else {
        request.response.statusCode = HttpStatus.notFound;
      }
      request.response.contentLength = body.length;
      request.response.add(body);
      await request.response.close();
    });
    final repository = _LiveRepository(server.port, hls: true);
    final session = PlaybackSession(
      engine: engine,
      repository: _UnusedRepository(),
      contentRepository: repository,
      isRoomLive: (target, cancellation) async {
        roomChecks++;
        return target.roomId == '1';
      },
      progress: _UnusedProgress(),
      accountScope: () => 'guest',
    );
    final failures = <PlayerFailure>[];
    final subscription = engine.failures.listen(failures.add);
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
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      // Fail playlist refreshes on the original reader, including any native
      // retries. The same URL serves healthy media when the session reopens it.
      await tester.pump(const Duration(seconds: 3));
      brokenGeneration = generation;
      final watch = Stopwatch()..start();
      while (watch.elapsed < const Duration(seconds: 30) &&
          !(engine.currentSnapshot.generation > generation &&
              engine.currentSnapshot.phase == PlaybackPhase.playing &&
              engine.currentSnapshot.position > const Duration(seconds: 1))) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(rejectedReloads, greaterThan(0));
      expect(
        failures.every((f) => f.kind == PlayerFailureKind.liveReadTerminated),
        isTrue,
      );
      expect(failures.length, lessThanOrEqualTo(1));
      expect(roomChecks, 1);
      expect(mediaHeaders, {
        ('BiliSail-Live-Test', 'https://www.bilibili.com'),
      });
      expect(recoveredRequests, greaterThan(0));
      expect(repository.resolutions, 1);
      expect(engine.currentSnapshot.generation, greaterThan(generation));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(
        engine.currentSnapshot.position,
        greaterThan(const Duration(seconds: 1)),
      );
      expect(session.error, isNull);
      debugPrint(
        'LIVE_HLS_RECOVERY playlist503=$rejectedReloads '
        'roomChecks=$roomChecks reopened=${engine.currentSnapshot.generation > generation} '
        'positionMs=${engine.currentSnapshot.position.inMilliseconds}',
      );
    } finally {
      await subscription.cancel();
      await _withFrames(tester, session.close());
      await tester.pumpWidget(const SizedBox.shrink());
      await server.close(force: true);
    }
  });
}

final class _LiveRepository implements ContentPlaybackRepository {
  _LiveRepository(this.port, {this.hls = false});
  final int port;
  final bool hls;
  int resolutions = 0;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    resolutions++;
    final path = hls
        ? 'live.m3u8'
        : resolutions == 1
        ? 'bad.flv'
        : 'good.flv';
    return PlaybackMedia(
      video: PlaybackTrack(
        urls: [
          Uri.parse('http://127.0.0.1:$port/$path?token=synthetic-secret'),
        ],
        codec: 'avc1',
        bandwidth: 0,
      ),
      audio: null,
      quality: 80,
      qualities: const [80],
      duration: Duration.zero,
      headers: hls
          ? const {
              'User-Agent': 'BiliSail-Live-Test',
              'Referer': 'https://www.bilibili.com',
            }
          : const {},
      kind: hls ? PlaybackMediaKind.liveHls : PlaybackMediaKind.liveFlv,
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
