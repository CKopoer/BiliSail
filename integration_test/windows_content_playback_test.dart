import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_lite/core/network/api_requests.dart';
import 'package:bili_lite/features/playback/data/api_content_playback_repository.dart';
import 'package:bili_lite/features/playback/data/api_playback_repository.dart';

import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/features/playback/application/playback_session.dart';
import 'package:bili_lite/features/playback/domain/content_playback.dart';
import 'package:bili_lite/features/playback/domain/playback_repository.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows shared live session decodes HLS and FLV with native headers',
    (tester) async {
      initializePlayerBackend();
      final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR'];
      expect(directory, isNotNull, reason: 'Use tool/test-windows-content.ps1');
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>{};
      var rejectedHeaders = 0;
      server.listen((request) async {
        paths.add(request.uri.path);
        if (request.headers.value('referer') != 'https://live.bilibili.com/' ||
            request.headers.value('user-agent') !=
                'BiliLite-Content-Validation') {
          rejectedHeaders++;
          request.response.statusCode = 403;
        } else {
          final name = request.uri.pathSegments.last;
          final file = File('$directory/$name');
          if (!RegExp(r'^(live\.(m3u8|flv)|segment-[0-9]+\.ts)$')
                  .hasMatch(name) ||
              !await file.exists()) {
            request.response.statusCode = 404;
          } else {
            request.response.headers.contentType = name.endsWith('.m3u8')
                ? ContentType('application', 'vnd.apple.mpegurl')
                : ContentType(
                    'video',
                    name.endsWith('.flv') ? 'x-flv' : 'mp2t',
                  );
            request.response.add(await file.readAsBytes());
          }
        }
        await request.response.close();
      });
      final engine = MediaKitEngine();
      final repository = _ContentRepository(server.port);
      final progress = _Progress();
      final session = PlaybackSession(
        engine: engine,
        repository: _UnusedVideoRepository(),
        contentRepository: repository,
        progress: progress,
        accountScope: () => 'guest',
      );
      addTearDown(() async {
        await session.close();
        await server.close(force: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      final owner = Object();
      session.attach(owner);
      await session.activate(
        owner,
        null,
        null,
        target: const LivePlaybackTarget('1'),
      );
      await _decoded(tester, engine);
      expect(paths.contains('/live.m3u8'), isTrue);
      expect(paths.any((path) => path.endsWith('.ts')), isTrue);
      final generation = engine.currentSnapshot.generation;
      await session.seek(const Duration(seconds: 6));
      await session.setRate(2);
      expect(engine.currentSnapshot.generation, generation);
      expect(engine.currentSnapshot.rate, 1);
      await session.pause();
      final paused = engine.currentSnapshot.position;
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (engine.currentSnapshot.position - paused).inMilliseconds.abs(),
        lessThan(300),
      );
      await session.deactivate(owner);
      await session.activate(
        owner,
        null,
        null,
        target: const LivePlaybackTarget('1'),
      );
      expect(engine.currentSnapshot.generation, generation);
      await session.stop();
      repository.flv = true;
      await session.activate(
        owner,
        null,
        null,
        target: const LivePlaybackTarget('2'),
      );
      await _decoded(tester, engine);
      expect(paths.contains('/live.flv'), isTrue);
      expect(rejectedHeaders, 0);
      expect(progress.writes, 0);
      expect(session.error, isNull);
    },
  );
  testWidgets(
    'Windows guest PGC and live CDN decode through the shared resolver',
    (tester) async {
      if (!const bool.fromEnvironment('BILI_CONTENT_ONLINE')) return;
      initializePlayerBackend();
      final requests = ApiRequests();
      final api = BiliApiClient(sessionProvider: requests);
      final pgc = PgcClient(api), live = LiveClient(api);
      final season = await requests.run(
        (context) => pgc.getSeason(seasonId: '28747', context: context),
      );
      final episode = season.episodes.firstWhere((episode) => episode.playable);
      final room = await requests.run(
        (context) => live.getRoom('6', context: context),
      );
      expect(
        room.liveStatus,
        1,
        reason: 'The explicit online probe needs an on-air room',
      );
      final engine = MediaKitEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: ApiPlaybackRepository(api, requests),
        contentRepository: ApiContentPlaybackRepository(pgc, live, requests),
        progress: _Progress(),
        accountScope: () => 'guest',
      );
      addTearDown(() async {
        await session.close();
        api.close();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              fit: StackFit.expand,
              children: [
                VideoSurface(engine: engine),
                DanmakuOverlay(controller: session.danmaku),
              ],
            ),
          ),
        ),
      );
      final owner = Object();
      session.attach(owner);
      await session.activate(
        owner,
        null,
        null,
        target: PgcPlaybackTarget(episode.episodeId, cid: episode.cid),
      );
      expect(session.error, isNull);
      await _decoded(tester, engine);
      final danmakuDeadline = DateTime.now().add(const Duration(seconds: 15));
      while (session.danmaku.visibleCount == 0 &&
          DateTime.now().isBefore(danmakuDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        session.danmaku.visibleCount,
        greaterThan(0),
        reason: 'The selected public episode must render decoded comments',
      );
      debugPrint(
        'CONTENT_ONLINE_PGC: decoded video, audio and visible danmaku',
      );
      await session.activate(
        owner,
        null,
        null,
        target: LivePlaybackTarget(room.roomId),
      );
      expect(session.error, isNull);
      await _decoded(tester, engine);
      debugPrint('CONTENT_ONLINE_LIVE: decoded video and audio');
    },
  );
}

Future<void> _decoded(WidgetTester tester, MediaKitEngine engine) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (DateTime.now().isBefore(deadline)) {
    final diagnostic = engine.inspectDiagnostics();
    if (diagnostic.hasDecodedAudio &&
        diagnostic.hasDecodedVideo &&
        engine.currentSnapshot.position > const Duration(milliseconds: 400)) {
      return;
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
  fail('Native audio/video decoding did not advance within 20 seconds');
}

final class _ContentRepository implements ContentPlaybackRepository {
  _ContentRepository(this.port);
  final int port;
  bool flv = false;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri.parse('http://127.0.0.1:$port/live.${flv ? 'flv' : 'm3u8'}')],
      codec: 'avc',
      bandwidth: 0,
    ),
    audio: null,
    quality: quality,
    qualities: [quality],
    duration: Duration.zero,
    headers: const {
      'Referer': 'https://live.bilibili.com/',
      'User-Agent': 'BiliLite-Content-Validation',
    },
    kind: flv ? PlaybackMediaKind.liveFlv : PlaybackMediaKind.liveHls,
  );
}

final class _Progress implements PlaybackProgressStore {
  int writes = 0;
  @override
  Future<Duration> read(String scope, VideoId video, String cid) async =>
      Duration.zero;
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {
    writes++;
  }
}

final class _UnusedVideoRepository implements PlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => throw StateError('Live must use its content resolver');
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
