import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/desktop_window_chrome.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/data/api_video_repository.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Windows native DASH pair: headers, redirects, ranges, seek and lifecycle',
    (tester) async {
      initializePlayerBackend();
      final fixturePath = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixturePath, isNotNull, reason: 'Use tool/test-windows-media.ps1');
      final video = await File('$fixturePath/video.mp4').readAsBytes();
      final audio = await File('$fixturePath/audio.m4a').readAsBytes();
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final observed = <String, List<String?>>{};
      server.listen((request) async {
        final path = request.uri.path;
        observed
            .putIfAbsent(path, () => [])
            .add(request.headers.value('range'));
        if (request.headers.value('referer') != 'https://www.bilibili.com/' ||
            request.headers.value('user-agent') !=
                'BiliSail-Native-Validation') {
          request.response.statusCode = 403;
        } else if (path.startsWith('/redirect-')) {
          request.response.statusCode = 302;
          request.response.headers.set(
            'Location',
            path == '/redirect-video' ? '/video.mp4' : '/audio.m4a',
          );
        } else {
          final bytes = path == '/video.mp4' ? video : audio;
          request.response.headers.set('Accept-Ranges', 'bytes');
          request.response.headers.contentType = ContentType('video', 'mp4');
          final range = request.headers.value('range');
          final match = range == null
              ? null
              : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
          final start = match == null ? 0 : int.parse(match.group(1)!);
          final requestedEnd = match?.group(2);
          final end = requestedEnd == null || requestedEnd.isEmpty
              ? bytes.length - 1
              : int.parse(requestedEnd);
          if (start >= bytes.length || end < start) {
            request.response.statusCode = 416;
          } else {
            final safeEnd = end.clamp(start, bytes.length - 1);
            if (match != null) {
              request.response.statusCode = 206;
              request.response.headers.set(
                'Content-Range',
                'bytes $start-$safeEnd/${bytes.length}',
              );
            }
            request.response.contentLength = safeEnd - start + 1;
            request.response.add(bytes.sublist(start, safeEnd + 1));
          }
        }
        await request.response.close();
      });
      final engine = MediaKitEngine();
      addTearDown(() async {
        await engine.dispose();
        await server.close(force: true);
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      final policy = MediaRequestPolicy(
        headers: {
          'Referer': 'https://www.bilibili.com/',
          'User-Agent': 'BiliSail-Native-Validation',
        },
      );
      final root = 'http://127.0.0.1:${server.port}';
      final source = DashPairSource(
        video: MediaTrack(
          uri: Uri.parse('$root/redirect-video'),
          requestPolicy: policy,
        ),
        audio: MediaTrack(
          uri: Uri.parse('$root/redirect-audio'),
          requestPolicy: policy,
        ),
      );
      await engine.open(source, const OpenOptions(play: true, volume: 5));
      debugPrint(
        'CONTROLLED_OPEN ${engine.inspectDiagnostics()} paths=${observed.keys.join(',')}',
      );
      await _until(
        tester,
        () =>
            engine.inspectDiagnostics().hasDecodedVideo &&
            engine.inspectDiagnostics().hasDecodedAudio &&
            engine.currentSnapshot.position > const Duration(seconds: 1),
        onTimeout: () => debugPrint(
          'CONTROLLED_TIMEOUT ${engine.inspectDiagnostics()} phase=${engine.currentSnapshot.phase} paths=$observed',
        ),
      );
      expect(observed.containsKey('/video.mp4'), isTrue);
      expect(observed.containsKey('/audio.m4a'), isTrue);
      expect(observed['/video.mp4']?.any((range) => range != null), isTrue);
      expect(observed['/audio.m4a']?.any((range) => range != null), isTrue);
      await engine.pause();
      final paused = engine.currentSnapshot.position;
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        (engine.currentSnapshot.position - paused).inMilliseconds.abs(),
        lessThan(300),
      );
      await engine.seek(const Duration(seconds: 7));
      await engine.setRate(2);
      await engine.play();
      await _until(
        tester,
        () => engine.currentSnapshot.position >= const Duration(seconds: 7),
      );
      expect(engine.currentSnapshot.rate, 2);
      final generation = engine.currentSnapshot.generation;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 240,
                child: VideoSurface(engine: engine),
              ),
            ),
          ),
        ),
      );
      expect(engine.currentSnapshot.generation, generation);
      final diagnostics = engine.inspectDiagnostics();
      debugPrint(
        'CONTROLLED_MEDIA video=${diagnostics.videoWidth}x${diagnostics.videoHeight} audioChannels=${diagnostics.audioChannels} audioHz=${diagnostics.audioSampleRate} videoRange=true audioRange=true',
      );
      await engine.stop();
      await engine.open(source, const OpenOptions(play: true, volume: 5));
      await _until(
        tester,
        () =>
            engine.currentSnapshot.position > const Duration(milliseconds: 300),
      );
      expect(engine.currentSnapshot.generation, greaterThan(generation));
      await engine.stop();
    },
  );

  testWidgets('Windows secure store writes and deletes an isolated probe', (
    tester,
  ) async {
    final key = 'bilisail.validation.${DateTime.now().microsecondsSinceEpoch}';
    final storage = SystemCredentialStore(keyPrefix: key);
    try {
      await storage.write('synthetic-validation-value');
      expect(await storage.read(), 'synthetic-validation-value');
      await storage.write('synthetic-validation-updated');
      expect(await storage.read(), 'synthetic-validation-updated');
    } finally {
      await storage.delete();
    }
    expect(await storage.read(), isNull);
  });

  testWidgets('Windows guest UGC resolves and decodes both native tracks', (
    tester,
  ) async {
    const online = bool.fromEnvironment('BILI_ONLINE_SMOKE');
    if (!online) return;
    initializePlayerBackend();
    final requests = ApiRequests();
    final api = BiliApiClient(sessionProvider: requests);
    addTearDown(api.close);
    final list = await api.getPopular();
    final selected = list.items.firstWhere(
      (item) => item.duration > const Duration(seconds: 40),
    );
    final detail = await ApiVideoRepository(
      api,
      requests,
    ).loadDetail(VideoId(selected.bvid), cancellation: RequestCancellation());
    final engine = MediaKitEngine();
    final repo = ApiPlaybackRepository(api, requests);
    final session = PlaybackSession(
      engine: engine,
      repository: repo,
      progress: _NoopProgressStore(),
      accountScope: () => 'guest',
    );
    session.configureComments(enabled: false, fontScale: 1);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      // The first CDN may consume its native timeout before the one backup
      // attempt. Keep the entire online playback assertion bounded.
      final deadline = DateTime.now().add(const Duration(seconds: 85));
      await session
          .open(detail, detail.parts.first)
          .timeout(deadline.difference(DateTime.now()));
      expect(session.error, isNull);
      expect(session.media, isNotNull);
      await _until(
        tester,
        () =>
            engine.inspectDiagnostics().hasDecodedVideo &&
            engine.inspectDiagnostics().hasDecodedAudio &&
            engine.currentSnapshot.position > const Duration(seconds: 2),
        deadline: deadline,
        onTimeout: () => debugPrint(
          'ONLINE_TIMEOUT ${engine.inspectDiagnostics()} phase=${engine.currentSnapshot.phase} error=${session.error}',
        ),
      );
      await session
          .seek(const Duration(seconds: 10))
          .timeout(deadline.difference(DateTime.now()));
      expect(session.error, isNull);
      await _until(
        tester,
        () => engine.currentSnapshot.position >= const Duration(seconds: 10),
        deadline: deadline,
      );
      final diagnostics = engine.inspectDiagnostics();
      debugPrint(
        'ONLINE_UGC bvid=${detail.summary.id.value} quality=${session.media?.quality} video=${diagnostics.videoWidth}x${diagnostics.videoHeight} audioChannels=${diagnostics.audioChannels} audioHz=${diagnostics.audioSampleRate}',
      );
      await session.pause();
      expect(session.error, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
    }
  });

  testWidgets(
    'Windows native responsive controls, fullscreen and Esc preserve one playback source',
    (tester) async {
      initializePlayerBackend();
      final fixturePath = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixturePath, isNotNull, reason: 'Use tool/test-windows-media.ps1');
      final videoFile = File('$fixturePath/video.mp4');
      final audioFile = File('$fixturePath/audio.m4a');
      expect(await videoFile.exists(), isTrue);
      expect(await audioFile.exists(), isTrue);

      final window = WindowService();
      await window.initialize();
      await window.setFullScreen(false);
      final engine = MediaKitEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakePlaybackRepository(videoFile.uri, audioFile.uri),
        progress: _NoopProgressStore(),
        accountScope: () => 'guest',
      );
      final semantics = tester.ensureSemantics();
      final panelWidth = ValueNotifier(640.0);
      const part = VideoPart(
        cid: 'fixture-1',
        page: 1,
        title: '本地分轨测试',
        duration: Duration(seconds: 12),
      );
      const detail = VideoDetail(
        summary: VideoSummary(
          id: VideoId('BV1abc123456'),
          title: '本地测试视频',
          coverUrl: '',
          author: 'fixture',
          duration: Duration(seconds: 12),
        ),
        description: '',
        parts: [part],
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: ValueListenableBuilder<double>(
                    valueListenable: panelWidth,
                    builder: (context, width, child) => SizedBox(
                      width: width,
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: PlaybackPanel(
                          detail: detail,
                          part: part,
                          settings: AppSettings(danmakuEnabled: false),
                          onToggleComments: () {},
                          window: window,
                          danmakuComposerBuilder: (_) => const SizedBox(
                            height: 36,
                            child: TextField(
                              decoration: InputDecoration(hintText: '测试弹幕草稿'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              engine.inspectDiagnostics().hasDecodedVideo &&
              engine.inspectDiagnostics().hasDecodedAudio &&
              engine.currentSnapshot.position >
                  const Duration(milliseconds: 300),
        );
        await session.setVolume(0);
        await session.pause();
        final generation = engine.currentSnapshot.generation;
        expect(generation, greaterThan(0));
        expect(tester.takeException(), isNull);

        final resizePosition = engine.currentSnapshot.position;
        final surfaceTarget = find.byKey(
          const ValueKey('player-surface-tap-target'),
        );
        await tester.tapAt(
          tester.getTopLeft(surfaceTarget) + const Offset(30, 50),
        );
        await tester.pump(const Duration(milliseconds: 400));
        final progress = tester.widget<LinearProgressIndicator>(
          find.byKey(const ValueKey('player-collapsed-progress')),
        );
        expect(
          progress.value,
          closeTo(
            engine.currentSnapshot.position.inMilliseconds /
                engine.currentSnapshot.duration.inMilliseconds,
            .01,
          ),
        );
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        await tester.tapAt(
          tester.getTopLeft(surfaceTarget) + const Offset(30, 50),
        );
        await tester.pump(const Duration(milliseconds: 400));
        for (final width in [940.0, 600.0, 420.0, 940.0, 640.0]) {
          panelWidth.value = width;
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(
            find.byKey(
              ValueKey(
                width >= 940 ? 'standard-control-row' : 'compact-control-row',
              ),
            ),
            findsOneWidget,
          );
          expect(find.byType(VideoSurface), findsOneWidget);
          expect(engine.currentSnapshot.generation, generation);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(
            (engine.currentSnapshot.position - resizePosition).abs(),
            lessThan(const Duration(milliseconds: 250)),
          );
          expect(tester.takeException(), isNull);
        }
        await tester.tap(find.byTooltip('播放（空格）'));
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        await tester.pump();
        await tester.tap(find.byTooltip('暂停（空格）'));
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.paused,
        );

        // Inline activation must focus the player before any picture click.
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await _until(tester, () => engine.currentSnapshot.rate == 1.25);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await _until(tester, () => engine.currentSnapshot.rate == 1);
        await session.setRate(1.5);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await _until(tester, () => engine.currentSnapshot.rate == 2);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await _until(tester, () => engine.currentSnapshot.rate == 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.pump(const Duration(milliseconds: 200));
        expect(engine.currentSnapshot.rate, 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await _until(tester, () => engine.currentSnapshot.rate == 2);
        // Windows VK 222 produces quote. quoteSingle normalization is covered
        // by constructed key events because this simulator cannot map it.
        await tester.sendKeyEvent(LogicalKeyboardKey.quote);
        await _until(tester, () => engine.currentSnapshot.rate == 3);
        await tester.sendKeyEvent(LogicalKeyboardKey.semicolon);
        await _until(tester, () => engine.currentSnapshot.rate == 2);
        await session.setRate(0.5);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await tester.pump(const Duration(milliseconds: 200));
        expect(engine.currentSnapshot.rate, 0.5);
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        await session.setRate(1);

        // Tapping the picture only changes the overlay, never playback intent.
        final tapTarget = find.byKey(
          const ValueKey('player-surface-tap-target'),
        );
        await tester.tapAt(tester.getTopLeft(tapTarget) + const Offset(30, 50));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('player-controls')), findsNothing);
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(engine.currentSnapshot.generation, generation);
        await tester.tapAt(tester.getTopLeft(tapTarget) + const Offset(30, 50));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byKey(const ValueKey('player-controls')), findsOneWidget);
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);

        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.paused,
        );
        expect(engine.currentSnapshot.generation, generation);

        await session.setRate(1.5);
        await _until(tester, () => engine.currentSnapshot.rate == 1.5);
        final pausedPosition = engine.currentSnapshot.position;
        await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        await _until(tester, () => engine.currentSnapshot.rate == 3);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        await _until(tester, () => engine.currentSnapshot.rate == 1.5);
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(
          (engine.currentSnapshot.position - pausedPosition).abs(),
          lessThan(const Duration(milliseconds: 250)),
          reason: 'Releasing a long press must not also perform a short seek',
        );

        for (var cycle = 0; cycle < 6; cycle++) {
          if (cycle.isEven) {
            await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
          } else {
            await tester.tap(find.byTooltip('全屏（F）'));
          }
          await _until(
            tester,
            () =>
                window.isFullScreen &&
                find.byTooltip('退出全屏（Esc）').evaluate().length == 1,
          );
          expect(find.byTooltip('退出全屏（Esc）'), findsOneWidget);
          expect(engine.currentSnapshot.generation, generation);
          expect(tester.takeException(), isNull);

          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await _until(
            tester,
            () =>
                !window.isFullScreen &&
                find.byTooltip('全屏（F）').evaluate().length == 1,
          );
          expect(find.byTooltip('全屏（F）'), findsOneWidget);
          expect(engine.currentSnapshot.generation, generation);
          expect(engine.inspectDiagnostics().generation, generation);
          expect(tester.takeException(), isNull);
        }
        expect(window.isFullScreen, isFalse);
      } finally {
        await window.setFullScreen(false);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await session.close();
        semantics.dispose();
        panelWidth.dispose();
      }
    },
  );
  testWidgets(
    'Windows workspace continues hidden playback and retains video checkpoints',
    (tester) async {
      initializePlayerBackend();
      final fixturePath = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(fixturePath, isNotNull);
      final window = WindowService();
      await window.initialize();
      final engine = MediaKitEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _FakePlaybackRepository(
          File('$fixturePath/video.mp4').uri,
          File('$fixturePath/audio.m4a').uri,
        ),
        progress: _NoopProgressStore(),
        accountScope: () => 'guest',
      );
      const part = VideoPart(
        cid: 'workspace-fixture',
        page: 1,
        title: '本地分轨',
        duration: Duration(seconds: 12),
      );
      const detail = VideoDetail(
        summary: VideoSummary(
          id: VideoId('BV1abc123456'),
          title: '工作区本地视频',
          coverUrl: '',
          author: 'fixture',
          duration: Duration(seconds: 12),
        ),
        description: '',
        parts: [part],
      );
      final router = GoRouter(
        routes: [
          ShellRoute(
            builder: (context, state, child) => BiliAppShell(
              location: state.uri.toString(),
              windowControlsBuilder: (_) => const DesktopWindowControls(),
              dragRegionBuilder: (_, child) => DesktopDragRegion(child: child),
              pageBuilder: (context, tab) => tab.isVideo
                  ? Row(
                      children: [
                        Expanded(
                          child: Center(
                            child: SizedBox(
                              width: 640,
                              child: AspectRatio(
                                aspectRatio: 16 / 9,
                                child: PlaybackPanel(
                                  detail: VideoDetail(
                                    summary: VideoSummary(
                                      id: VideoId(
                                        tab.location.pathSegments.last,
                                      ),
                                      title: detail.summary.title,
                                      coverUrl: '',
                                      author: 'fixture',
                                      duration: part.duration,
                                    ),
                                    description: '',
                                    parts: [part],
                                  ),
                                  part: part,
                                  settings: AppSettings(danmakuEnabled: false),
                                  onToggleComments: () {},
                                  window: window,
                                ),
                              ),
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {},
                          child: const Text('推荐视频测试'),
                        ),
                      ],
                    )
                  : const Center(child: Text('本地工作区首页')),
              child: child,
            ),
            routes: [
              GoRoute(path: '/', builder: (_, _) => const SizedBox()),
              GoRoute(
                path: '/video/:bvid',
                builder: (_, _) => const SizedBox(),
              ),
            ],
          ),
        ],
      );
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: MaterialApp.router(
              theme: BiliTheme.light(),
              routerConfig: router,
            ),
          ),
        );
        await tester.pump();
        router.go('/video/BV1abc123456');
        await _until(
          tester,
          () =>
              engine.inspectDiagnostics().hasDecodedVideo &&
              engine.inspectDiagnostics().hasDecodedAudio &&
              engine.currentSnapshot.position >
                  const Duration(milliseconds: 300),
        );
        await session.setVolume(0);
        final generation = engine.currentSnapshot.generation;
        await session.pause();
        final sidebarFocus = Focus.of(tester.element(find.text('推荐视频测试')));
        sidebarFocus.requestFocus();
        await _until(tester, () => sidebarFocus.hasPrimaryFocus);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await _until(tester, () => engine.currentSnapshot.rate == 1.25);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await _until(tester, () => engine.currentSnapshot.volume == 5);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await _until(tester, () => engine.currentSnapshot.volume == 0);
        await tester.sendKeyEvent(LogicalKeyboardKey.f1);
        await _until(tester, () => engine.currentSnapshot.rate == 1);
        expect(sidebarFocus.hasPrimaryFocus, isTrue);
        await session.togglePlaying();
        await session.seek(const Duration(milliseconds: 1700));
        await session.setRate(1.5);
        expect(find.byType(PlaybackPanel), findsOneWidget);
        final beforeHiding = engine.currentSnapshot.position;
        await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
        await _until(
          tester,
          () =>
              engine.currentSnapshot.phase == PlaybackPhase.playing &&
              engine.currentSnapshot.position >
                  beforeHiding + const Duration(milliseconds: 400),
        );
        final retainedPosition = engine.currentSnapshot.position;
        expect(
          retainedPosition,
          greaterThanOrEqualTo(const Duration(milliseconds: 1700)),
        );
        expect(find.byType(PlaybackPanel, skipOffstage: false), findsOneWidget);
        expect(find.byType(VideoSurface, skipOffstage: false), findsNothing);
        expect(engine.currentSnapshot.generation, generation);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump(const Duration(milliseconds: 200));
        expect(engine.currentSnapshot.rate, 1.5);
        expect(engine.currentSnapshot.volume, 0);
        expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
        await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
        await _until(
          tester,
          () =>
              engine.currentSnapshot.phase == PlaybackPhase.playing &&
              find
                      .byType(VideoSurface, skipOffstage: false)
                      .evaluate()
                      .length ==
                  1,
        );
        expect(engine.currentSnapshot.generation, generation);
        expect(
          engine.currentSnapshot.position,
          greaterThanOrEqualTo(retainedPosition),
        );
        expect(engine.currentSnapshot.rate, 1.5);
        expect(find.byType(VideoSurface, skipOffstage: false), findsOneWidget);

        await session.seek(const Duration(milliseconds: 1700));
        await session.pause();
        router.go('/video/BV1abc654321');
        await _until(
          tester,
          () =>
              session.detail?.summary.id.value == 'BV1abc654321' &&
              engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        await session.seek(const Duration(milliseconds: 4000));
        expect(
          find.byType(PlaybackPanel, skipOffstage: false),
          findsNWidgets(2),
        );
        expect(find.byType(VideoSurface, skipOffstage: false), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('workspace-tab-tab-1')));
        await _until(
          tester,
          () =>
              session.detail?.summary.id.value == 'BV1abc123456' &&
              engine.currentSnapshot.phase == PlaybackPhase.paused &&
              !session.isResolving,
        );
        expect(
          engine.currentSnapshot.position.inMilliseconds,
          closeTo(1700, 150),
        );
        expect(engine.currentSnapshot.rate, 1.5);
        await tester.tap(
          find.byKey(const ValueKey('close-workspace-tab-tab-2')),
        );
        await tester.pump();
        expect(session.detail?.summary.id.value, 'BV1abc123456');
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(find.byType(PlaybackPanel, skipOffstage: false), findsOneWidget);
        expect(find.byType(VideoSurface, skipOffstage: false), findsOneWidget);

        await session.togglePlaying();
        await tester.tap(find.byKey(const ValueKey('workspace-tab-home')));
        await tester.pump();
        expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
        expect(find.byType(VideoSurface, skipOffstage: false), findsNothing);
        await tester.tap(
          find.byKey(const ValueKey('close-workspace-tab-tab-1')),
        );
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.idle,
        );
        expect(find.byType(PlaybackPanel, skipOffstage: false), findsNothing);
        expect(find.text('本地工作区首页'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await session.close();
        router.dispose();
      }
    },
  );
}

final class _FakePlaybackRepository implements PlaybackRepository {
  const _FakePlaybackRepository(this.videoUri, this.audioUri);
  final Uri videoUri;
  final Uri audioUri;

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(urls: [videoUri], codec: 'avc1', bandwidth: 1000000),
    audio: PlaybackTrack(urls: [audioUri], codec: 'mp4a', bandwidth: 64000),
    quality: 80,
    qualities: const [80],
    duration: const Duration(seconds: 12),
    headers: const {},
  );

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => const [];

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => const [];

  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => const [];
}

final class _NoopProgressStore implements PlaybackProgressStore {
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
  }) async {}
}

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  DateTime? deadline,
  VoidCallback? onTimeout,
}) async {
  final expiresAt = deadline ?? DateTime.now().add(const Duration(seconds: 35));
  while (!condition() && DateTime.now().isBefore(expiresAt)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (!condition()) onTimeout?.call();
  expect(
    condition(),
    isTrue,
    reason: 'Native playback did not reach the required decoded state',
  );
}
