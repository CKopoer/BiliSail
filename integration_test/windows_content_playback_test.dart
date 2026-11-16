import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:bili_api/bili_api.dart';
import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/features/playback/data/api_content_playback_repository.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';

import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/native_playback_window.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets(
    'Windows detached window reuses UGC, PGC and live native playback',
    (tester) async {
      initializePlayerBackend();
      final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR'];
      expect(directory, isNotNull, reason: 'Use tool/test-windows-content.ps1');
      final mainWindow = WindowService();
      await mainWindow.initialize();
      final primaryView = PlatformDispatcher.instance.implicitView;
      final viewCount = PlatformDispatcher.instance.views.length;
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final paths = <String>{};
      var rejectedHeaders = 0;
      server.listen((request) async {
        paths.add(request.uri.path);
        if (request.headers.value('referer') != 'https://live.bilibili.com/' ||
            request.headers.value('user-agent') !=
                'BiliSail-Content-Validation') {
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
      final repository = _ContentRepository(server.port, directory!);
      final progress = _Progress();
      final session = PlaybackSession(
        engine: engine,
        repository: _FixtureVideoRepository(directory),
        contentRepository: repository,
        progress: progress,
        accountScope: () => 'guest',
      );
      final owner = Object();
      session.attach(owner);
      final windowOpen = ValueNotifier(true);
      final activation = ValueNotifier('ugc');
      final windowErrors = <Object>[];
      void closePlayback() {
        session.detach(owner);
        windowOpen.value = false;
      }

      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await session.close();
        await server.close(force: true);
        windowOpen.dispose();
        activation.dispose();
      });
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder(
            valueListenable: windowOpen,
            builder: (context, open, _) => ValueListenableBuilder(
              valueListenable: activation,
              builder: (context, token, _) => DesktopPlaybackWindow(
                onCloseRequested: closePlayback,
                onError: windowErrors.add,
                activationToken: token,
                playback: !open
                    ? null
                    : WorkspacePlaybackWindow(
                        theme: BiliTheme.light(),
                        shortcuts: const AppSettings.defaults().shortcuts,
                        onBack: () {},
                        onClose: closePlayback,
                        onActivateBrowser: () =>
                            unawaited(mainWindow.activate()),
                        child: VideoSurface(engine: engine),
                      ),
                child: const Scaffold(body: Text('受控内容浏览窗口')),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(windowErrors, isEmpty);
      expect(PlatformDispatcher.instance.views.length, viewCount + 1);
      final playbackView = View.of(tester.element(find.byType(VideoSurface)));
      expect(playbackView.viewId, isNot(primaryView?.viewId));
      void expectSharedWindow() {
        expect(windowErrors, isEmpty);
        expect(PlatformDispatcher.instance.implicitView, same(primaryView));
        expect(PlatformDispatcher.instance.views.length, viewCount + 1);
        expect(find.byType(VideoSurface, skipOffstage: false), findsOneWidget);
        expect(
          View.of(tester.element(find.byType(VideoSurface))).viewId,
          playbackView.viewId,
        );
        expect(find.text('受控内容浏览窗口'), findsOneWidget);
      }

      const part = VideoPart(
        cid: 'controlled-on-demand',
        page: 1,
        title: '本地分轨',
        duration: Duration(seconds: 12),
      );
      const detail = VideoDetail(
        summary: VideoSummary(
          id: VideoId('BV1abc123456'),
          title: '独立播放窗受控内容',
          coverUrl: '',
          author: 'fixture',
          duration: Duration(seconds: 12),
        ),
        description: '',
        parts: [part],
      );
      await session.activate(owner, detail, part);
      await _decoded(tester, engine);
      await session.setVolume(0);
      expectSharedWindow();
      final ugcGeneration = engine.currentSnapshot.generation;
      activation.value = 'pgc';
      await tester.pump();
      await session.activate(
        owner,
        detail,
        part,
        target: const PgcPlaybackTarget(
          'controlled-episode',
          cid: 'controlled-on-demand',
        ),
      );
      await _decoded(tester, engine);
      expect(engine.currentSnapshot.generation, greaterThan(ugcGeneration));
      expect(session.contentTarget, isA<PgcPlaybackTarget>());
      expectSharedWindow();
      activation.value = 'live-hls';
      await tester.pump();
      await session.activate(
        owner,
        null,
        null,
        target: const LivePlaybackTarget('1'),
      );
      await _decoded(tester, engine);
      expectSharedWindow();
      final onDemandWrites = progress.writes;
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
      activation.value = 'live-flv';
      await tester.pump();
      await session.activate(
        owner,
        null,
        null,
        target: const LivePlaybackTarget('2'),
      );
      await _decoded(tester, engine);
      expectSharedWindow();
      expect(paths.contains('/live.flv'), isTrue);
      expect(rejectedHeaders, 0);
      expect(progress.writes, onDemandWrites);
      expect(session.error, isNull);
      NativePlaybackWindow(playbackView.viewId).close();
      final closeDeadline = DateTime.now().add(const Duration(seconds: 5));
      while ((engine.currentSnapshot.phase != PlaybackPhase.idle ||
              PlatformDispatcher.instance.views.length != viewCount) &&
          DateTime.now().isBefore(closeDeadline)) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
      expect(PlatformDispatcher.instance.views.length, viewCount);
      expect(find.byType(VideoSurface, skipOffstage: false), findsNothing);
      expect(find.text('受控内容浏览窗口'), findsOneWidget);
      expect(tester.takeException(), isNull);
      debugPrint(
        'NATIVE_DETACHED_CONTENT ugcDash=true pgcDash=true liveHls=true '
        'liveFlv=true oneSession=true reusedView=true closed=true',
      );
    },
  );
  testWidgets('Windows PGC and live CDN decode through the shared resolver', (
    tester,
  ) async {
    if (!const bool.fromEnvironment('BILI_CONTENT_ONLINE')) return;
    initializePlayerBackend();
    final requests = ApiRequests();
    final api = BiliApiClient(sessionProvider: requests);
    const savedSession = bool.fromEnvironment('BILI_CONTENT_SAVED_SESSION');
    if (savedSession) {
      final saved = await SystemCredentialStore().read();
      if (saved == null) throw StateError('No saved Web session');
      final Object? decoded = jsonDecode(saved);
      if (decoded is! Map<String, Object?> ||
          decoded['version'] != 1 ||
          decoded['cookies'] is! Map<String, Object?>) {
        throw StateError('Unsupported secure session snapshot');
      }
      api.cookieJar.restoreFromSecureStorage(
        decoded['cookies'] as Map<String, Object?>,
      );
    }
    final pgc = PgcClient(api), live = LiveClient(api);
    const episodeId = String.fromEnvironment('BILI_CONTENT_EPISODE');
    final season = await requests.run(
      (context) => pgc.getSeason(
        seasonId: episodeId.isEmpty ? '28747' : null,
        episodeId: episodeId.isEmpty ? null : episodeId,
        context: context,
      ),
    );
    final episode = season.episodes.firstWhere(
      (episode) =>
          episode.playable &&
          (episodeId.isEmpty || episode.episodeId == episodeId),
    );
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
    if (savedSession) {
      // Exercise dense pools with filtering and a smaller on-demand viewport.
      session.configureSettings(
        AppSettings(
          danmakuArea: .4,
          danmakuFontScale: .85,
          danmakuMinimumWeight: 3,
          danmakuMergeDuplicates: true,
        ),
      );
    }
    addTearDown(() async {
      await session.close();
      api.close();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: savedSession ? 640 : double.infinity,
              height: savedSession ? 360 : double.infinity,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoSurface(engine: engine),
                  DanmakuOverlay(
                    controller: session.danmaku,
                    bottomInset: savedSession ? 100 : 0,
                  ),
                ],
              ),
            ),
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
    debugPrint('CONTENT_ONLINE_PGC: decoded video, audio and visible danmaku');
    await session.activate(
      owner,
      null,
      null,
      target: LivePlaybackTarget(room.roomId),
    );
    expect(session.error, isNull);
    await _decoded(tester, engine);
    debugPrint('CONTENT_ONLINE_LIVE: decoded video and audio');
  });
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
  _ContentRepository(this.port, this.directory);
  final int port;
  final String directory;
  bool flv = false;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => target is PgcPlaybackTarget
      ? _onDemandMedia(directory, quality)
      : PlaybackMedia(
          video: PlaybackTrack(
            urls: [
              Uri.parse('http://127.0.0.1:$port/live.${flv ? 'flv' : 'm3u8'}'),
            ],
            codec: 'avc',
            bandwidth: 0,
          ),
          audio: null,
          quality: quality,
          qualities: [quality],
          duration: Duration.zero,
          headers: const {
            'Referer': 'https://live.bilibili.com/',
            'User-Agent': 'BiliSail-Content-Validation',
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

final class _FixtureVideoRepository implements PlaybackRepository {
  const _FixtureVideoRepository(this.directory);
  final String directory;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => _onDemandMedia(directory, quality);
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

PlaybackMedia _onDemandMedia(String directory, int quality) => PlaybackMedia(
  video: PlaybackTrack(
    urls: [File('$directory/video.mp4').uri],
    codec: 'avc1',
    bandwidth: 1000000,
  ),
  audio: PlaybackTrack(
    urls: [File('$directory/audio.m4a').uri],
    codec: 'mp4a',
    bandwidth: 64000,
  ),
  quality: quality,
  qualities: [quality],
  duration: const Duration(seconds: 12),
  headers: const {},
);
