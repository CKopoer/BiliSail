import '../../support/input_test_app.dart';

import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/core/presentation/input_scope.dart';
import 'package:bilisail/core/input/input_stroke.dart';
import 'package:bilisail/core/input/shortcut_dispatcher.dart';

import 'dart:async';
import 'dart:ui' show PointerDeviceKind, Tristate;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

final _composerScopeProvider = Provider<String>((ref) => 'root');

void main() {
  for (final live in [false, true]) {
    for (final dimensions in [
      const VideoDimensions(1920, 1080),
      const VideoDimensions(1080, 1920),
      const VideoDimensions(1080, 1080),
    ]) {
      testWidgets(
        'mobile ${live ? 'live' : 'video'} fullscreen follows ${dimensions.width}x${dimensions.height}',
        (tester) async {
          final engine = _FakeEngine();
          final session = _session(engine);
          final window = _FakeWindowService(desktop: false);
          addTearDown(session.close);
          await tester.pumpWidget(
            _app(
              session,
              window,
              const AppSettings.defaults(),
              target: live ? const LivePlaybackTarget('12') : null,
            ),
          );
          await _pumpFrames(tester);
          expect(session.isLive, live);
          await session.pause();
          engine._emit(
            engine.currentSnapshot.copyWith(videoDimensions: dimensions),
          );
          final generation = engine.currentSnapshot.generation;
          final opens = engine.opens;
          await tester.tap(find.byTooltip('全屏（F）'));
          await _pumpFrames(tester);
          expect(window.fullScreen, isTrue);
          expect(
            window.orientations.single,
            dimensions.width > dimensions.height
                ? FullScreenOrientation.landscape
                : FullScreenOrientation.portrait,
          );
          for (var i = 0; i < 10; i++) {
            engine._emit(engine.currentSnapshot.copyWith(volume: 50));
          }
          await _pumpFrames(tester);
          expect(window.orientations, hasLength(1));
          await tester.tap(find.byTooltip('退出全屏（Esc）'));
          await _pumpFrames(tester);
          expect(window.fullScreen, isFalse);
          expect(window.orientations.last, isNull);
          expect(engine.opens, opens);
          expect(engine.currentSnapshot.generation, generation);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(engine.maxSurfaces, 1);
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
        },
      );
    }
  }

  testWidgets(
    'mobile fullscreen follows delayed dimensions and source changes',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(400, 800);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = _FakeEngine();
      final session = _session(engine);
      final window = _FakeWindowService(desktop: false);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('全屏（F）'));
      await _pumpFrames(tester);
      expect(window.orientations, [FullScreenOrientation.portrait]);
      engine._emit(
        engine.currentSnapshot.copyWith(
          videoDimensions: const VideoDimensions(1920, 1080),
        ),
      );
      await _pumpFrames(tester);
      expect(window.orientations.last, FullScreenOrientation.landscape);
      await session.retry();
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.videoDimensions, isNull);
      expect(window.orientations, hasLength(2));
      engine._emit(
        engine.currentSnapshot.copyWith(
          videoDimensions: const VideoDimensions(1080, 1920),
        ),
      );
      await _pumpFrames(tester);
      expect(window.orientations.last, FullScreenOrientation.portrait);
      expect(engine.maxSurfaces, 1);
      // A system back closes only the presentation and releases orientation.
      await tester.binding.handlePopRoute();
      await _pumpFrames(tester);
      expect(window.fullScreen, isFalse);
      expect(window.orientations.last, isNull);
      final calls = window.orientations.length;
      engine._emit(
        engine.currentSnapshot.copyWith(
          videoDimensions: const VideoDimensions(1920, 1080),
        ),
      );
      await _pumpFrames(tester);
      expect(window.orientations, hasLength(calls));
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  for (final dispose in [false, true]) {
    testWidgets(
      'mobile fullscreen releases orientation when ${dispose ? 'disposed' : 'hidden'}',
      (tester) async {
        final engine = _FakeEngine();
        final session = _session(engine);
        final window = _FakeWindowService(desktop: false);
        addTearDown(session.close);
        await tester.pumpWidget(
          _app(session, window, const AppSettings.defaults()),
        );
        await _pumpFrames(tester);
        engine._emit(
          engine.currentSnapshot.copyWith(
            videoDimensions: const VideoDimensions(1920, 1080),
          ),
        );
        await tester.tap(find.byTooltip('全屏（F）'));
        await _pumpFrames(tester);
        await tester.pumpWidget(
          dispose
              ? const SizedBox()
              : _app(
                  session,
                  window,
                  const AppSettings.defaults(),
                  active: false,
                ),
        );
        await _pumpFrames(tester);
        expect(window.fullScreen, isFalse);
        expect(window.orientations.last, isNull);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
      },
    );
  }

  testWidgets('cancelled mobile fullscreen drops queued orientation updates', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    final window = _DelayedWindow(desktop: false);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, window, const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    engine._emit(
      engine.currentSnapshot.copyWith(
        videoDimensions: const VideoDimensions(1080, 1920),
      ),
    );
    await tester.pumpWidget(
      _app(session, window, const AppSettings.defaults(), active: false),
    );
    await _pumpFrames(tester);
    window.gate.complete();
    await _pumpFrames(tester);
    expect(window.fullScreen, isFalse);
    expect(window.orientations, [FullScreenOrientation.landscape, null]);
    expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets(
    'workspace close exits fullscreen and held repeats cannot close a new page',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await _focusRecommendation(tester, session);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await _pumpFrames(tester);
      expect(find.byTooltip('退出全屏（Esc）'), findsOneWidget);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyW);
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('workspace-tab-tab-1')), findsNothing);
      expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsOneWidget);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.keyW);
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('workspace-tab-tab-2')), findsOneWidget);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyW);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      expect(engine.maxSurfaces, 1);
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final (mode, concurrent) in [
    for (final mode in WorkspaceNavigationMode.values)
      for (final allowed in [false, true]) (mode, allowed),
  ]) {
    testWidgets(
      'workspace scopes players and enforces ${mode.name} playback (concurrent: $concurrent)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final sessions = <PlaybackSession>[];
        final manager = PlaybackManager(
          createSession: () {
            final session = _session(_FakeEngine());
            sessions.add(session);
            return session;
          },
        );
        addTearDown(manager.close);
        final settings = _Settings()
          ..value = AppSettings.defaults(
            navigationMode: mode,
            allowConcurrentPlayback: concurrent,
          );
        final second = VideoDetail(
          summary: const VideoSummary(
            id: VideoId('BV2abc123456'),
            title: '第二个视频',
            coverUrl: '',
            author: 'UP',
            duration: Duration(minutes: 3),
          ),
          description: '',
          parts: const [
            VideoPart(
              cid: '456',
              page: 1,
              title: '第二个视频',
              duration: Duration(minutes: 3),
            ),
          ],
        );
        final router = createBiliRouter(
          initialLocation: '/video/${_detail.summary.id.value}',
          playerBuilder: (_, detail, part) => PlaybackPanel(
            detail: detail,
            part: part,
            settings: const AppSettings.defaults(),
            onToggleComments: () {},
            window: _FakeWindowService(),
          ),
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackManagerProvider.overrideWithValue(manager),
              settingsRepositoryProvider.overrideWithValue(settings),
              for (final video in [_detail, second]) ...[
                videoDetailProvider(video.summary.id)
                    .overrideWith((_) => video),
                relatedVideosProvider(video.summary.id).overrideWith((_) => []),
              ],
            ],
            child: InputTestApp.router(
              builder: AppNoticeHost.builder,
              routerConfig: router,
            ),
          ),
        );
        await _pumpFrames(tester);
        expect(sessions.length, 1);
        final firstSession = sessions.first;
        await firstSession.seek(const Duration(milliseconds: 1234));
        final generation = firstSession.sourceGeneration;
        router.go('/video/${second.summary.id.value}');
        await _pumpFrames(tester);
        expect(sessions.length, 2);
        final secondSession = sessions.last;
        expect(secondSession.detail?.summary.id, second.summary.id);
        expect(secondSession.snapshots.value.phase, PlaybackPhase.playing);
        expect(
          firstSession.snapshots.value.phase,
          mode == WorkspaceNavigationMode.multipleTabs && concurrent
              ? PlaybackPhase.playing
              : PlaybackPhase.paused,
        );
        expect(firstSession.sourceGeneration, generation);
        expect((firstSession.engine as _FakeEngine).activeSurfaces, 0);
        expect((secondSession.engine as _FakeEngine).activeSurfaces, 1);
        // Mode changes preserve the page/provider identity and media sources.
        final container = ProviderScope.containerOf(
          tester.element(find.byType(PlaybackPanel).last),
          listen: false,
        );
        final controller = container.read(settingsControllerProvider.notifier);
        await controller.setNavigationMode(WorkspaceNavigationMode.singlePage);
        await _pumpFrames(tester);
        expect(firstSession.snapshots.value.phase, PlaybackPhase.paused);
        expect(secondSession.snapshots.value.phase, PlaybackPhase.playing);
        await controller.setNavigationMode(
          WorkspaceNavigationMode.multipleTabs,
        );
        await _pumpFrames(tester);
        expect(
          firstSession.snapshots.value.phase,
          concurrent ? PlaybackPhase.playing : PlaybackPhase.paused,
        );
        await controller.setAllowConcurrentPlayback(true);
        await _pumpFrames(tester);
        expect(firstSession.snapshots.value.phase, PlaybackPhase.playing);
        // The real settings page changes policy without replacing either source.
        router.go('/settings?section=playback');
        await _pumpFrames(tester);
        final toggle = find.widgetWithText(SwitchListTile, '允许多个标签页同时播放');
        await tester.ensureVisible(toggle);
        await tester.pump();
        await tester.tap(toggle);
        await _pumpFrames(tester);
        expect(settings.value.allowConcurrentPlayback, isFalse);
        expect(firstSession.snapshots.value.phase, PlaybackPhase.paused);
        expect(secondSession.snapshots.value.phase, PlaybackPhase.playing);
        expect(firstSession.sourceGeneration, generation);
        await firstSession.pause();
        await tester.tap(toggle);
        await _pumpFrames(tester);
        expect(settings.value.allowConcurrentPlayback, isTrue);
        expect(firstSession.snapshots.value.phase, PlaybackPhase.paused);
        expect(secondSession.snapshots.value.phase, PlaybackPhase.playing);
        await firstSession.togglePlaying();
        await _pumpFrames(tester);
        expect(sessions.length, 2);
        router.go('/video/${_detail.summary.id.value}');
        await _pumpFrames(tester);
        expect(
          firstSession.snapshots.value.position,
          const Duration(milliseconds: 1234),
        );
        expect(firstSession.sourceGeneration, generation);
        // Closing the visible tab must leave the other tab's stream running.
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        await _pumpFrames(tester);
        expect(secondSession.snapshots.value.phase, PlaybackPhase.playing);
        expect(firstSession.media, isNull);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
        final closing = manager.close();
        // Provider disposal and broadcast stream closure cross Riverpod's real
        // scheduler and the widget test's fake clock; drain both before teardown.
        for (var i = 0; i < 5; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump();
        }
        await closing;
      },
    );
  }

  testWidgets(
    'control visibility preserves scrolling danmaku inline and fullscreen',
    (tester) async {
      final engine = _FakeEngine();
      var now = Duration.zero;
      final session = _session(engine, danmakuNow: () => now);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, _FakeWindowService(), AppSettings(danmakuMaxOnScreen: 1)),
      );
      await _pumpFrames(tester);
      await session.pause();
      for (final fullscreen in [false, true]) {
        if (fullscreen) {
          await tester.tap(find.byTooltip('全屏（F）'));
          await _pumpFrames(tester);
        }
        session.danmaku.replaceEvents(const [
          DanmakuEvent(
            id: 'warmup',
            at: Duration.zero,
            text: 'warmup',
            mode: DanmakuMode.top,
          ),
          DanmakuEvent(
            id: 'dropped',
            at: Duration(seconds: 1),
            text: 'dropped',
          ),
          DanmakuEvent(
            id: 'visible',
            at: Duration(seconds: 4),
            text: 'visible',
          ),
        ]);
        session.danmaku.seekConfirmed(Duration.zero);
        for (var halfSecond = 0; halfSecond <= 10; halfSecond++) {
          now += const Duration(milliseconds: 500);
          engine._emit(
            engine.currentSnapshot.copyWith(
              phase: PlaybackPhase.playing,
              position: Duration(milliseconds: halfSecond * 500),
            ),
          );
          await tester.pump();
        }
        await session.pause();
        await tester.pump();
        final before = session.danmaku.frame().single;
        expect(before.event.id, 'visible');
        final generation = engine.currentSnapshot.generation;
        final controls = find.byKey(const ValueKey('player-controls'));
        final target = find.byKey(const ValueKey('player-surface-tap-target'));
        for (final visible in [false, true, false, true]) {
          await tester.tapAt(tester.getTopLeft(target) + const Offset(30, 50));
          await _pumpSurfaceTap(tester);
          await tester.pump();
          expect(controls, visible ? findsOneWidget : findsNothing);
          expect(
            tester
                .widget<DanmakuOverlay>(find.byType(DanmakuOverlay))
                .bottomInset,
            visible ? 100 : 48,
          );
          final after = session.danmaku.frame().single;
          expect(after.event.id, before.event.id);
          expect(after.x, before.x);
          expect(after.y, before.y);
          expect(engine.currentSnapshot.position, const Duration(seconds: 5));
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(engine.currentSnapshot.generation, generation);
          expect(engine.opens, 1);
          expect(engine.maxSurfaces, 1);
        }
      }
      await tester.tap(find.byTooltip('退出全屏（Esc）'));
      await _pumpFrames(tester);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  for (final controlsVisible in [true, false]) {
    testWidgets(
      'fullscreen round trips preserve scrolling danmaku with controls $controlsVisible',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1280, 800);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final engine = _FakeEngine();
        var now = Duration.zero;
        final session = _session(engine, danmakuNow: () => now);
        final window = _FakeWindowService();
        addTearDown(session.close);
        await tester.pumpWidget(
          _app(session, window, AppSettings(danmakuMaxOnScreen: 1), width: 800),
        );
        await _pumpFrames(tester);
        await session.pause();
        final target = find.byKey(const ValueKey('player-surface-tap-target'));
        if (!controlsVisible) {
          await tester.tapAt(tester.getTopLeft(target) + const Offset(30, 50));
          await _pumpSurfaceTap(tester);
        }
        session.danmaku.replaceEvents(const [
          DanmakuEvent(
            id: 'warmup',
            at: Duration.zero,
            text: 'warmup',
            mode: DanmakuMode.top,
          ),
          DanmakuEvent(
            id: 'dropped',
            at: Duration(seconds: 1),
            text: 'dropped',
          ),
          DanmakuEvent(
            id: 'visible',
            at: Duration(seconds: 4),
            text: 'visible',
          ),
          DanmakuEvent(id: 'future', at: Duration(seconds: 14), text: 'future'),
        ]);
        session.danmaku.seekConfirmed(Duration.zero);
        for (var halfSecond = 0; halfSecond <= 10; halfSecond++) {
          now += const Duration(milliseconds: 500);
          engine._emit(
            engine.currentSnapshot.copyWith(
              phase: PlaybackPhase.playing,
              position: Duration(milliseconds: halfSecond * 500),
            ),
          );
          await tester.pump();
        }
        await session.pause();
        await tester.pump();
        final before = session.danmaku.frame().single;
        expect(before.event.id, 'visible');
        final generation = session.sourceGeneration;
        final pending = session.danmaku.pendingCount;
        final dropped = session.danmaku.dropped;
        final layouts = session.danmaku.textLayoutCount;
        final inlineWidth = tester.getSize(find.byType(DanmakuOverlay)).width;
        for (final fullscreen in [true, false, true, false]) {
          final point = tester.getTopLeft(target) + const Offset(30, 50);
          await tester.tapAt(point);
          await tester.pump(const Duration(milliseconds: 50));
          await tester.tapAt(point);
          await _pumpFrames(tester);
          await _pumpSurfaceTap(tester);
          expect(window.fullScreen, fullscreen);
          final controls = find.byKey(const ValueKey('player-controls'));
          expect(controls, controlsVisible ? findsOneWidget : findsNothing);
          expect(session.danmaku.visibleCount, 1);
          expect(session.danmaku.pendingCount, pending);
          expect(session.danmaku.textLayoutCount, layouts);
          final after = session.danmaku.frame().single;
          final width = tester.getSize(find.byType(DanmakuOverlay)).width;
          expect(after.event.id, before.event.id);
          expect(
            after.x,
            closeTo(before.x + (width - inlineWidth) * 7 / 8, .001),
          );
          expect(after.y, before.y);
          expect(session.danmaku.dropped, dropped);
          expect(engine.currentSnapshot.position, const Duration(seconds: 5));
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(session.sourceGeneration, generation);
          expect(engine.opens, 1);
          expect(engine.maxSurfaces, 1);
        }
        await session.togglePlaying();
        now += const Duration(milliseconds: 500);
        engine._emit(
          engine.currentSnapshot.copyWith(
            position: const Duration(milliseconds: 5500),
          ),
        );
        await tester.pump();
        final resumed = session.danmaku.frame().single;
        expect(resumed.event.id, before.event.id);
        expect(resumed.x, lessThan(before.x));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
      },
    );
  }

  testWidgets('top margin settings reach the shared playback overlay', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    final window = _FakeWindowService();
    for (final margin in [40.0, 80.0, 0.0]) {
      await tester.pumpWidget(
        _app(
          session,
          window,
          AppSettings(danmakuTopMargin: margin),
          width: 800,
        ),
      );
      await _pumpFrames(tester);
      await session.pause();
      session.danmaku.replaceEvents(const [
        DanmakuEvent(id: 'one', at: Duration.zero, text: 'one'),
      ]);
      session.danmaku.seekConfirmed(const Duration(seconds: 1));
      await tester.pump();
      expect(session.danmaku.frame().single.y, margin);
      expect(engine.opens, 1);
      expect(engine.maxSurfaces, 1);
    }
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  testWidgets('row gap settings update VOD without reopening the player', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    final window = _FakeWindowService();
    double? textHeight;
    for (final gap in [0.0, 20.0, 0.0, 5.0]) {
      await tester.pumpWidget(
        _app(session, window, AppSettings(danmakuLineSpacing: gap), width: 800),
      );
      await _pumpFrames(tester);
      await session.pause();
      session.danmaku.replaceEvents(const [
        DanmakuEvent(id: 'one', at: Duration(seconds: 1), text: 'line'),
        DanmakuEvent(id: 'two', at: Duration(seconds: 1), text: 'line'),
      ]);
      session.danmaku.seekConfirmed(const Duration(seconds: 1));
      final frame = session.danmaku.frame();
      expect(frame, hasLength(2));
      final laneHeight = frame[1].y - frame[0].y;
      textHeight ??= laneHeight;
      expect(laneHeight, textHeight + gap);
      expect(engine.opens, 1);
      expect(engine.maxSurfaces, 1);
    }
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  for (final width in [320.0, 1200.0]) {
    testWidgets('volume drags continuously at width $width and fullscreen', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1000);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          const AppSettings.defaults(),
          width: width,
          textScale: width == 320 ? 2 : 1,
        ),
      );
      await _pumpFrames(tester);
      await session.pause();
      await session.seek(const Duration(seconds: 45));
      final generation = engine.currentSnapshot.generation;
      final slider = find.byKey(const ValueKey('player-volume-slider'));

      for (final fullscreen in [false, true]) {
        if (fullscreen) {
          await tester.tap(find.byTooltip('全屏（F）'));
          await _pumpFrames(tester);
        }
        await tester.tap(find.byTooltip('音量'));
        await tester.pumpAndSettle();
        expect(slider, findsOneWidget);
        expect(tester.widget<Slider>(slider).divisions, isNull);
        final rect = tester.getRect(slider);
        final gesture = await tester.startGesture(rect.center);
        await tester.pump();
        await gesture.moveTo(
          Offset(rect.left + rect.width * .38, rect.center.dy),
        );
        await tester.pump();
        expect(engine.currentSnapshot.volume, inExclusiveRange(25, 50));
        await gesture.up();
        await tester.pumpAndSettle();
        expect(slider, findsOneWidget);
        expect(
          find.text('音量 ${engine.currentSnapshot.volume.round()}%'),
          findsOneWidget,
        );

        await session.setVolume(63.5);
        await tester.pump();
        expect(tester.widget<Slider>(slider).value, 63.5);
        expect(find.text('音量 64%'), findsOneWidget);
        await tester.tapAt(Offset(rect.left + 1, rect.center.dy));
        await tester.pumpAndSettle();
        expect(engine.currentSnapshot.volume, 0);
        expect(find.text('音量 0%'), findsOneWidget);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(slider, findsNothing);
        expect(find.byIcon(Icons.volume_off_outlined), findsOneWidget);

        await tester.tap(find.byTooltip('音量'));
        await tester.pumpAndSettle();
        expect(tester.widget<Slider>(slider).value, 0);
        final reopenedRect = tester.getRect(slider);
        await tester.tapAt(
          Offset(reopenedRect.right - 1, reopenedRect.center.dy),
        );
        await tester.pumpAndSettle();
        expect(engine.currentSnapshot.volume, 100);
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
        expect(engine.currentSnapshot.position, const Duration(seconds: 45));
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.opens, 1);
        expect(engine.maxSurfaces, 1);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byTooltip('退出全屏（Esc）'));
      await _pumpFrames(tester);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    });
  }

  for (final (content, target) in <(String, ContentPlaybackTarget?)>[
    ('video', null),
    ('pgc', const PgcPlaybackTarget('12', cid: '123')),
    ('live', const LivePlaybackTarget('12')),
    ('offline', const OfflinePlaybackTarget('local-task')),
  ]) {
    testWidgets('$content player wheel adjusts volume inline and fullscreen', (
      tester,
    ) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          AppSettings(shortcuts: ShortcutSettings(enabled: false)),
          target: target,
        ),
      );
      await _pumpFrames(tester);
      await session.pause();
      final generation = engine.currentSnapshot.generation;
      final position = engine.currentSnapshot.position;
      for (final fullscreen in [false, true]) {
        if (fullscreen) {
          await tester.tap(find.byTooltip('全屏'));
          await _pumpFrames(tester);
        }
        final point = tester.getCenter(
          find.byKey(const ValueKey('player-surface-tap-target')),
        );
        await session.setVolume(50);
        _wheel(tester, point, const Offset(0, -120));
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.volume, 55);
        expect(find.text('音量 55%'), findsOneWidget);
        _wheel(tester, point, const Offset(0, 120));
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.volume, 50);
        await session.setVolume(98);
        _wheel(tester, point, const Offset(0, -120));
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.volume, 100);
        await session.setVolume(2);
        _wheel(tester, point, const Offset(0, 120));
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.volume, 0);
        expect(engine.currentSnapshot.position, position);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.opens, 1);
        expect(engine.maxSurfaces, 1);
      }
      await tester.tap(find.byTooltip('退出全屏'));
      await _pumpFrames(tester);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    });
  }

  testWidgets('player wheel consumes scrolling only inside the picture', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    final scroll = ScrollController();
    addTearDown(session.close);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: InputTestApp(
          builder: AppNoticeHost.builder,
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scroll,
              child: Column(
                children: [
                  SizedBox(
                    width: 600,
                    height: 340,
                    child: PlaybackPanel(
                      detail: _detail,
                      part: _part,
                      settings: const AppSettings.defaults(),
                      onToggleComments: () {},
                      window: _FakeWindowService(),
                    ),
                  ),
                  const SizedBox(height: 1200),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester);
    await session.pause();
    final point = tester.getCenter(find.byType(PlaybackPanel));
    _wheel(tester, point, const Offset(0, 120));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 95);
    expect(scroll.offset, 0);
    _wheel(tester, const Offset(400, 500), const Offset(0, 120));
    await _pumpFrames(tester);
    expect(scroll.offset, greaterThan(0));
    expect(engine.currentSnapshot.volume, 95);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('player wheel respects modal, lifecycle and hidden-page guards', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    addTearDown(() => _resumeApp(tester));
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await session.pause();
    final surface = find.byKey(const ValueKey('player-surface-tap-target'));
    final point = tester.getCenter(surface);
    _wheel(tester, point, const Offset(-120, 0));
    _wheel(
      tester,
      point,
      const Offset(0, 120),
      kind: PointerDeviceKind.trackpad,
    );
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 100);
    final context = tester.element(surface);
    unawaited(
      showDialog<void>(
        context: context,
        requestFocus: false,
        builder: (_) => const AlertDialog(content: Text('wheel guard')),
      ),
    );
    await tester.pumpAndSettle();
    _wheel(tester, point, const Offset(0, 120));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 100);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    _wheel(tester, point, const Offset(0, 120));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 100);
    _resumeApp(tester);
    _wheel(tester, point, const Offset(0, 120));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 95);
    await tester.pumpWidget(
      _app(
        session,
        _FakeWindowService(),
        const AppSettings.defaults(),
        active: false,
      ),
    );
    await _pumpFrames(tester);
    _wheel(tester, point, const Offset(0, 120));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 95);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('rapid player wheel input accumulates pending volume targets', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await session.pause();
    await session.setVolume(50);
    final gate = Completer<void>();
    engine.nextVolume = gate;
    final point = tester.getCenter(
      find.byKey(const ValueKey('player-surface-tap-target')),
    );
    for (var i = 0; i < 5; i++) {
      _wheel(tester, point, const Offset(0, -120));
    }
    expect(session.commandVolume, 75);
    expect(engine.currentSnapshot.volume, 50);
    gate.complete();
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 75);
    expect(find.text('音量 75%'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('fullscreen composers retain the owning page provider scope', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(
        session,
        _FakeWindowService(),
        const AppSettings.defaults(),
        width: 1200,
        scopedComposer: true,
        composer: (_) => Consumer(
          builder: (_, ref, _) => Text(ref.watch(_composerScopeProvider)),
        ),
      ),
    );
    await _pumpFrames(tester);
    expect(find.text('房间草稿'), findsOneWidget);
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    expect(find.text('房间草稿'), findsOneWidget);
    expect(find.text('root'), findsNothing);
    expect(engine.maxSurfaces, 1);
    await tester.tap(find.byTooltip('退出全屏（Esc）'));
    await _pumpFrames(tester);
    expect(find.text('房间草稿'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  testWidgets(
    'collapsed progress tracks confirmed position, setting and content kind',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      final window = _FakeWindowService();
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      engine._emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 90)),
      );
      await tester.pump();
      const progressKey = ValueKey('player-collapsed-progress');
      expect(find.byKey(progressKey), findsNothing);
      await tester.tapAt(
        tester.getTopLeft(
              find.byKey(const ValueKey('player-surface-tap-target')),
            ) +
            const Offset(30, 50),
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(
        tester.widget<LinearProgressIndicator>(find.byKey(progressKey)).value,
        .5,
      );
      session.contentTarget = const PgcPlaybackTarget('7', cid: '123');
      engine._emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 180)),
      );
      await tester.pump();
      expect(
        tester.widget<LinearProgressIndicator>(find.byKey(progressKey)).value,
        1,
      );
      await tester.pumpWidget(
        _app(session, window, AppSettings(showCollapsedProgress: false)),
      );
      await _pumpFrames(tester);
      expect(find.byKey(progressKey), findsNothing);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      session.contentTarget = const LivePlaybackTarget('12');
      engine._emit(
        engine.currentSnapshot.copyWith(position: const Duration(seconds: 45)),
      );
      await tester.pump();
      expect(find.byKey(progressKey), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets(
    'live overlay follows visibility, settings and fullscreen surface',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      final window = _FakeWindowService();
      addTearDown(session.close);
      Widget overlay(BuildContext context) =>
          const IgnorePointer(child: Text('实时弹幕覆盖层'));
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults(), overlay: overlay),
      );
      await _pumpFrames(tester);
      expect(find.text('实时弹幕覆盖层'), findsOneWidget);
      final generation = engine.currentSnapshot.generation;
      await tester.tap(find.byTooltip('全屏（F）'));
      await _pumpFrames(tester);
      expect(find.text('实时弹幕覆盖层'), findsOneWidget);
      expect(engine.maxSurfaces, 1);
      expect(engine.currentSnapshot.generation, generation);
      await tester.tap(find.byTooltip('退出全屏（Esc）'));
      await _pumpFrames(tester);
      expect(find.text('实时弹幕覆盖层'), findsOneWidget);
      await tester.pumpWidget(
        _app(
          session,
          window,
          AppSettings(danmakuEnabled: false),
          overlay: overlay,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('实时弹幕覆盖层'), findsNothing);
      await tester.pumpWidget(
        _app(
          session,
          window,
          const AppSettings.defaults(),
          overlay: overlay,
          active: false,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('实时弹幕覆盖层'), findsNothing);
      expect(engine.currentSnapshot.generation, generation);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets(
    'side keys act once on the active player from the sidebar and respect modal/input guards',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await _focusRecommendation(
        tester,
        session,
        settings: AppSettings(
          shortcuts: const ShortcutSettings.defaults()
              .withKeys(ShortcutAction.volumeDown, ['MouseBack'])
              .withKeys(ShortcutAction.seekForward, ['Ctrl+MouseForward']),
        ),
      );
      final pointer = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kBackMouseButton,
      );
      final point = tester.getCenter(find.text('推荐视频 0'));
      await session.setVolume(50);
      await pointer.down(point);
      await pointer.up();
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.volume, 45);
      final forward = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        buttons: kForwardMouseButton,
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await forward.down(point);
      await forward.up();
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.position, const Duration(seconds: 3));
      expect(engine.currentSnapshot.rate, 1);
      final context = tester.element(find.text('推荐视频 0'));
      unawaited(
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => const AlertDialog(content: Text('mouse guard')),
        ),
      );
      await tester.pumpAndSettle();
      await pointer.down(point);
      await pointer.up();
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.volume, 45);
      Navigator.of(context, rootNavigator: true).pop();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          AppSettings(
            shortcuts: const ShortcutSettings.defaults().withKeys(
              ShortcutAction.volumeDown,
              ['MouseBack'],
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      await tester.tap(find.byKey(const Key('search-field')));
      await tester.pump();
      final volume = engine.currentSnapshot.volume;
      await pointer.down(tester.getCenter(find.byType(PlaybackPanel)));
      await pointer.up();
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.volume, volume);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
      expect(tester.takeException(), isNull);
    },
  );
  for (final desktop in [false, true]) {
    testWidgets(
      '${desktop ? 'desktop' : 'mobile'} system pause uses playback ownership when its tab is hidden',
      (tester) async {
        final engine = _FakeEngine();
        final session = _session(engine);
        final window = _FakeWindowService(desktop: desktop);
        addTearDown(session.close);
        addTearDown(() {
          _resumeApp(tester);
        });
        await tester.pumpWidget(
          _app(session, window, const AppSettings.defaults()),
        );
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
        final pauses = engine.pauses;
        await tester.pumpWidget(
          _app(session, window, const AppSettings.defaults(), active: false),
        );
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
        expect(engine.pauses, pauses);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.desiredPlaying, isTrue);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.desiredPlaying, desktop);
        expect(engine.pauses, pauses + (desktop ? 0 : 1));
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await _pumpFrames(tester);
        expect(engine.pauses, pauses + (desktop ? 0 : 2));
        _resumeApp(tester);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
      },
    );
  }

  testWidgets('only the retained playback owner pauses for mobile background', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    final window = _FakeWindowService(desktop: false);
    addTearDown(session.close);
    addTearDown(() {
      _resumeApp(tester);
    });
    Widget app(int active) => ProviderScope(
      overrides: [playbackSessionProvider.overrideWithValue(session)],
      child: InputTestApp(
        home: Scaffold(
          body: Stack(
            children: [
              for (var i = 0; i < 2; i++)
                Offstage(
                  key: ValueKey(i),
                  offstage: active != i,
                  child: WorkspaceActivity(
                    active: active == i,
                    child: SizedBox(
                      width: 400,
                      height: 225,
                      child: PlaybackPanel(
                        detail: _detail,
                        part: _part,
                        settings: const AppSettings.defaults(),
                        onToggleComments: () {},
                        window: window,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpWidget(app(0));
    await _pumpFrames(tester);
    await tester.pumpWidget(app(1));
    await _pumpFrames(tester);
    await tester.pumpWidget(app(-1));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.desiredPlaying, isTrue);
    final pauses = engine.pauses;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    expect(engine.pauses, pauses + 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _pumpFrames(tester);
    expect(engine.pauses, pauses + 2);
    _resumeApp(tester);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('rate keys follow menu steps and clamp at both ends', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    final focus = await _focusRecommendation(tester, session);
    await session.setRate(.5);
    for (final rate in [.75, 1.0, 1.25, 1.5, 2.0, 3.0, 3.0]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, rate);
    }
    for (final rate in [2.0, 1.5, 1.25, 1.0, .75, .5, .5]) {
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, rate);
    }
    // Existing sessions can carry a speed selected by the old continuous UI.
    await session.setRate(1.8);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.rate, 2);
    await session.setRate(1.8);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.rate, 1.5);
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  for (final volumeKeys in [true, false]) {
    testWidgets(
      '${volumeKeys ? 'volume' : 'rate'} keys work while a recommendation keeps focus',
      (tester) async {
        final engine = _FakeEngine();
        final session = _session(engine);
        addTearDown(session.close);
        final focus = await _focusRecommendation(tester, session);
        final scroll = Scrollable.of(focus.context!).position;
        final offset = scroll.pixels;
        if (volumeKeys) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.volume, 95);
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.volume, 90);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.volume, 95);
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.f2);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 1.25);
          await tester.sendKeyEvent(LogicalKeyboardKey.f1);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 1);
          await tester.sendKeyEvent(LogicalKeyboardKey.quote);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 1.25);
          await tester.sendKeyEvent(LogicalKeyboardKey.semicolon);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 1);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.digit1);
          await tester.sendKeyRepeatEvent(LogicalKeyboardKey.digit1);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.digit1);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 2);
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          await tester.pump(const Duration(milliseconds: 450));
          expect(engine.currentSnapshot.rate, 3);
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 2);
          expect(engine.currentSnapshot.position, Duration.zero);
        }
        expect(focus.hasPrimaryFocus, isTrue);
        expect(scroll.pixels, offset);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
        // Disposed players must remove their page-wide handlers.
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('sidebar shortcuts respect disabled actions and custom keys', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await _focusRecommendation(
      tester,
      session,
      settings: AppSettings(
        shortcuts: const ShortcutSettings.defaults()
            .withKeys(ShortcutAction.volumeDown, ['V'])
            .withActionEnabled(ShortcutAction.faster, false),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 100);
    expect(engine.currentSnapshot.rate, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.volume, 95);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('a modal blocks shortcuts even when focus stays on the sidebar', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    final focus = await _focusRecommendation(tester, session);
    final context = tester.element(find.byType(PlaybackPanel));
    unawaited(
      showDialog<void>(
        context: context,
        requestFocus: false,
        builder: (_) => const AlertDialog(content: Text('modal')),
      ),
    );
    await tester.pumpAndSettle();
    expect(focus.hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.rate, 1);
    expect(engine.currentSnapshot.volume, 100);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.rate, 1.25);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets(
    'resizing shrinks the editor then switches controls without reopening media',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1400, 1100);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final engine = _FakeEngine();
      final session = _session(engine);
      final window = _FakeWindowService();
      addTearDown(session.close);
      Future<void> resize(double width, {double textScale = 1}) async {
        await tester.pumpWidget(
          _app(
            session,
            window,
            const AppSettings.defaults(),
            width: width,
            textScale: textScale,
            composer: (_) => const SizedBox(
              height: 36,
              child: TextField(key: Key('responsive-composer')),
            ),
          ),
        );
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
      }

      await resize(1200);
      await session.pause();
      await session.seek(const Duration(seconds: 45));
      final field = find.byKey(const Key('responsive-composer'));
      await tester.enterText(field, '保留弹幕草稿');
      final largeWidth = tester.getSize(field).width;
      await resize(940);
      expect(
        find.byKey(const ValueKey('standard-control-row')),
        findsOneWidget,
      );
      expect(tester.getSize(field).width, lessThan(largeWidth));
      expect(tester.getSize(field).width, greaterThanOrEqualTo(200));
      final baseline = tester.getCenter(find.byTooltip('全屏（F）')).dy;
      for (final tooltip in [
        '播放（空格）',
        '弹幕配置',
        '播放配置',
        '字幕样式',
        '关闭弹幕',
        '清晰度',
        '播放速度',
        '音量',
      ]) {
        expect(
          tester.getCenter(find.byTooltip(tooltip)).dy,
          closeTo(baseline, .1),
        );
      }
      expect(tester.getCenter(field).dy, closeTo(baseline, .1));
      for (final label in ['1080P', '1.0x', '00:45 / 03:00']) {
        expect(
          tester
              .renderObject<RenderParagraph>(find.text(label))
              .didExceedMaxLines,
          isFalse,
        );
      }
      for (final width in [800.0, 640.0, 480.0, 320.0]) {
        await resize(width);
        expect(
          find.byKey(const ValueKey('compact-control-row')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('compact-playback-actions')),
          findsOneWidget,
        );
        expect(field, findsNothing);
        expect(
          tester.getSize(find.byKey(const ValueKey('player-controls'))).height,
          lessThan(90),
        );
        expect(find.byTooltip('全屏（F）').hitTestable(), findsOneWidget);
      }
      await tester.tap(find.byTooltip('发送弹幕'));
      await tester.pump();
      expect(
        tester.widget<TextField>(field).controller?.text ??
            tester
                .widget<EditableText>(
                  find.descendant(
                    of: field,
                    matching: find.byType(EditableText),
                  ),
                )
                .controller
                .text,
        '保留弹幕草稿',
      );
      await tester.tap(find.byTooltip('收起弹幕输入'));
      await tester.pump();
      await tester.tap(find.byTooltip('播放（空格）'));
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.desiredPlaying, isTrue);
      await tester.tap(find.byTooltip('暂停（空格）'));
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
      await resize(1200);
      expect(find.text('保留弹幕草稿'), findsOneWidget);
      expect(engine.opens, 1);
      expect(engine.maxSurfaces, 1);
      expect(engine.currentSnapshot.position, const Duration(seconds: 45));
      await resize(940, textScale: 2);
      expect(find.byKey(const ValueKey('compact-control-row')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  testWidgets('dynamic menu selection survives idle and pointer exit', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(
        session,
        _FakeWindowService(),
        AppSettings(playerControlsMode: PlayerControlsMode.dynamic),
        width: 1200,
      ),
    );
    await _pumpFrames(tester);
    await session.pause();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _surfacePoint(tester));
    await tester.pump();
    await tester.tap(find.byTooltip('播放速度'));
    await tester.pump(const Duration(milliseconds: 300));
    await mouse.moveTo(const Offset(-10, -10));
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.widgetWithText(PopupMenuItem<double>, '3.0x'));
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.rate, 3);
    expect(engine.opens, 1);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('compact menu keeps quality and playback rate available', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await session.pause();
    await tester.tap(find.byTooltip('更多播放选项'));
    await tester.pumpAndSettle();
    expect(find.text('清晰度 720P'), findsOneWidget);
    expect(find.text('清晰度 1080P'), findsOneWidget);
    final rate = find.widgetWithText(
      CheckedPopupMenuItem<VoidCallback>,
      '播放速度 3.0x',
    );
    await tester.ensureVisible(rate);
    await tester.tap(rate);
    await tester.pumpAndSettle();
    expect(engine.currentSnapshot.rate, 3);
    expect(engine.opens, 1);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  for (final compact in [false, true]) {
    for (final fullscreen in [false, true]) {
      for (final menu in ['quality', 'rate', 'subtitle', 'voice']) {
        testWidgets(
          'dynamic $menu menu applies after idle compact=$compact fullscreen=$fullscreen',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(compact ? 500 : 1400, 900);
            addTearDown(tester.view.resetPhysicalSize);
            addTearDown(tester.view.resetDevicePixelRatio);
            final engine = _FakeEngine();
            final session = _session(engine, repository: _MenuRepository());
            addTearDown(session.close);
            await tester.pumpWidget(
              _app(
                session,
                _FakeWindowService(),
                AppSettings(playerControlsMode: PlayerControlsMode.dynamic),
                width: compact ? 400 : 1200,
              ),
            );
            await _pumpFrames(tester);
            await session.pause();
            if (fullscreen) {
              await tester.tap(find.byTooltip('全屏（F）'));
              await _pumpFrames(tester);
            }
            final mouse = await tester.createGesture(
              kind: PointerDeviceKind.mouse,
            );
            await mouse.addPointer(location: _surfacePoint(tester));
            await tester.pump();
            final tooltip = compact
                ? '更多播放选项'
                : switch (menu) {
                    'quality' => '清晰度',
                    'rate' => '播放速度',
                    'subtitle' => '字幕',
                    _ => '语音翻译',
                  };
            await tester.tap(find.byTooltip(tooltip));
            await tester.pump(const Duration(milliseconds: 300));
            await mouse.moveTo(const Offset(-10, -10));
            await tester.pump(const Duration(seconds: 6));
            await tester.pump(const Duration(milliseconds: 300));
            final label = switch (menu) {
              'quality' => compact ? '清晰度 720P' : '720P',
              'rate' => compact ? '播放速度 3.0x' : '3.0x',
              'subtitle' => '中文 · AI',
              _ => compact ? '语音 English · AI 翻译' : 'English · AI 翻译',
            };
            final item = find
                .ancestor(
                  of: find.text(label),
                  matching: find.byWidgetPredicate(
                    (widget) => widget is PopupMenuEntry,
                  ),
                )
                .last;
            await tester.ensureVisible(item);
            await tester.tap(item);
            await _pumpFrames(tester);
            switch (menu) {
              case 'quality':
                expect(session.media?.quality, 64);
              case 'rate':
                expect(engine.currentSnapshot.rate, 3);
              case 'subtitle':
                expect(session.selectedSubtitle, 0);
                expect(session.subtitleCues.single.text, '字幕回归');
                expect(find.text('字幕回归'), findsOneWidget);
              case 'voice':
                expect(session.selectedVoice.languageCode, 'en');
                expect(session.media?.video.urls.single.path, '/video/en');
                expect(session.media?.audio?.urls.single.path, '/audio/en');
            }
            expect(engine.currentSnapshot.desiredPlaying, isFalse);
            expect(engine.maxSurfaces, 1);
            expect(tester.takeException(), isNull);
            await mouse.removePointer();
            await tester.pumpWidget(const SizedBox());
            await _pumpFrames(tester);
          },
        );
      }
    }
  }

  testWidgets('full toolbar exposes and applies the 3.0x menu step', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(
        session,
        _FakeWindowService(),
        const AppSettings.defaults(),
        width: 1200,
      ),
    );
    await _pumpFrames(tester);
    await session.pause();
    await tester.tap(find.byTooltip('播放速度'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<double>, '3.0x'));
    await tester.pumpAndSettle();
    expect(engine.currentSnapshot.rate, 3);
    expect(engine.opens, 1);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets(
    'workspace player keys work on entry and after returning to video',
    (tester) async {
      final engine = _FakeEngine();
      // Keep interpolation active so this test cannot pass by waiting for a
      // real Stopwatch to expire on a slower machine.
      final session = _session(engine, danmakuNow: () => Duration.zero);
      final window = _FakeWindowService();
      var danmakuToggles = 0;
      addTearDown(session.close);
      final router = createBiliRouter(
        initialLocation: '/video/${_detail.summary.id.value}',
        playerBuilder: (_, detail, part) => PlaybackPanel(
          detail: detail,
          part: part,
          settings: const AppSettings.defaults(),
          onToggleComments: () => danmakuToggles++,
          window: window,
        ),
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackSessionProvider.overrideWithValue(session),
            settingsRepositoryProvider.overrideWithValue(_Settings()),
            videoDetailProvider(_detail.summary.id)
                .overrideWith((_) => _detail),
            relatedVideosProvider(_detail.summary.id).overrideWith((_) => []),
          ],
          child: InputTestApp.router(
            builder: AppNoticeHost.builder,
            routerConfig: router,
          ),
        ),
      );
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(session.danmaku.isAnimating, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1.25);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.volume, 95);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.volume, 100);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.position, const Duration(seconds: 3));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.position, Duration.zero);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.position, const Duration(seconds: 90));
      await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
      await tester.sendKeyEvent(LogicalKeyboardKey.f9);
      expect(danmakuToggles, 2);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1);
      await tester.sendKeyEvent(LogicalKeyboardKey.quote);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1.25);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await _pumpFrames(tester);
      expect(window.fullScreen, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await _pumpFrames(tester);
      expect(window.fullScreen, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.f1);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1);

      router.go('/downloads');
      await _pumpFrames(tester);
      expect(find.byType(PlaybackPanel), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1);
      router.go('/video/${_detail.summary.id.value}');
      await _pumpFrames(tester);
      expect(find.byType(PlaybackPanel), findsOneWidget);
      expect(session.danmaku.isAnimating, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.f2);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1.25);
      expect(engine.maxSurfaces, 1);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  for (final fullscreen in [false, true]) {
    for (final visible in [false, true]) {
      testWidgets(
        'touch hold uses configured delay and rate with ${visible ? 'visible' : 'hidden'} controls ${fullscreen ? 'fullscreen' : 'inline'}',
        (tester) async {
          final engine = _FakeEngine();
          final session = _session(engine);
          final window = _FakeWindowService(desktop: false);
          addTearDown(session.close);
          final settings = const AppSettings.defaults().copyWith(
            shortcuts: const ShortcutSettings.defaults()
                .withEnabled(false)
                .withPlayback(holdDelayMs: 700, holdRate: 2),
          );
          await tester.pumpWidget(_app(session, window, settings));
          await _pumpFrames(tester);
          await session.setRate(1.5);
          await session.seek(const Duration(seconds: 12));
          if (fullscreen) {
            await tester.tap(find.byTooltip('全屏'));
            await _pumpFrames(tester);
          }
          if (!visible) {
            await tester.tapAt(_surfacePoint(tester));
            await _pumpSurfaceTap(tester);
          }
          // A hold changes speed without changing the user's pause intent.
          if (visible) await session.pause();
          final playing = engine.currentSnapshot.desiredPlaying;
          final opens = engine.opens;
          final generation = session.sourceGeneration;
          final gesture = await tester.startGesture(_surfacePoint(tester));
          await tester.pump(const Duration(milliseconds: 699));
          expect(engine.currentSnapshot.rate, 1.5);
          await tester.pump(const Duration(milliseconds: 2));
          expect(engine.currentSnapshot.rate, 2);
          expect(find.text('长按倍速 2.0x'), findsOneWidget);
          await gesture.up();
          await _pumpFrames(tester);
          await _pumpSurfaceTap(tester);
          expect(engine.currentSnapshot.rate, 1.5);
          expect(engine.currentSnapshot.desiredPlaying, playing);
          expect(engine.currentSnapshot.position, const Duration(seconds: 12));
          expect(engine.opens, opens);
          expect(session.sourceGeneration, generation);
          expect(engine.maxSurfaces, 1);
          expect(find.byKey(const ValueKey('player-rate-hud')), findsNothing);
          expect(
            find.byKey(const ValueKey('player-controls')),
            visible ? findsOneWidget : findsNothing,
          );
          expect(window.fullScreen, fullscreen);
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final started in [false, true]) {
    for (final cancel in [
      'pointer',
      'hidden',
      'background',
      'modal',
      'source',
      'settings',
      'disposed',
    ]) {
      testWidgets(
        'touch hold ${started ? 'restores' : 'stays cancelled'} on $cancel cancellation',
        (tester) async {
          final engine = _FakeEngine();
          final session = _session(engine);
          final window = _FakeWindowService(desktop: false);
          var settings = const AppSettings.defaults();
          addTearDown(session.close);
          _resumeApp(tester);
          addTearDown(() => _resumeApp(tester));
          await tester.pumpWidget(_app(session, window, settings));
          await _pumpFrames(tester);
          await session.setRate(1.5);
          final gesture = await tester.startGesture(_surfacePoint(tester));
          await tester.pump(Duration(milliseconds: started ? 450 : 150));
          expect(engine.currentSnapshot.rate, started ? 3 : 1.5);
          switch (cancel) {
            case 'pointer':
              await gesture.cancel();
            case 'hidden':
              await tester.pumpWidget(
                _app(session, window, settings, active: false),
              );
            case 'background':
              tester.binding.handleAppLifecycleStateChanged(
                AppLifecycleState.inactive,
              );
            case 'modal':
              unawaited(
                showDialog<void>(
                  context: tester.element(find.byType(PlaybackPanel)),
                  requestFocus: false,
                  builder: (_) => const AlertDialog(content: Text('modal')),
                ),
              );
            case 'source':
              await session.retry();
            case 'settings':
              settings = settings.copyWith(
                shortcuts: settings.shortcuts.withPlayback(
                  holdDelayMs: 900,
                  holdRate: 1.25,
                ),
              );
              await tester.pumpWidget(_app(session, window, settings));
            case 'disposed':
              await tester.pumpWidget(const SizedBox());
          }
          await _pumpFrames(tester);
          await tester.pump(const Duration(milliseconds: 600));
          expect(engine.currentSnapshot.rate, 1.5);
          if (cancel != 'pointer') await gesture.up();
          await _pumpFrames(tester);
          expect(engine.currentSnapshot.rate, 1.5);
          if (cancel == 'settings') {
            final next = await tester.startGesture(_surfacePoint(tester));
            await tester.pump(const Duration(milliseconds: 899));
            expect(engine.currentSnapshot.rate, 1.5);
            await tester.pump(const Duration(milliseconds: 2));
            expect(engine.currentSnapshot.rate, 1.25);
            await next.up();
            await _pumpFrames(tester);
            expect(engine.currentSnapshot.rate, 1.5);
          }
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final touchFirst in [false, true]) {
    testWidgets(
      'releasing ${touchFirst ? 'touch' : 'keyboard'} does not cancel the newer rate hold',
      (tester) async {
        final engine = _FakeEngine();
        final session = _session(engine);
        addTearDown(session.close);
        await tester.pumpWidget(
          _app(session, _FakeWindowService(), const AppSettings.defaults()),
        );
        await _pumpFrames(tester);
        await session.setRate(1.5);
        late TestGesture touch;
        if (touchFirst) {
          touch = await tester.startGesture(_surfacePoint(tester));
        } else {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
        }
        await tester.pump(const Duration(milliseconds: 450));
        expect(engine.currentSnapshot.rate, 3);
        if (touchFirst) {
          await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
          await touch.up();
        } else {
          touch = await tester.startGesture(_surfacePoint(tester));
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        }
        await tester.pump(const Duration(milliseconds: 450));
        expect(engine.currentSnapshot.rate, 3);
        if (touchFirst) {
          await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
        } else {
          await touch.up();
        }
        await _pumpFrames(tester);
        expect(engine.currentSnapshot.rate, 1.5);
        expect(engine.currentSnapshot.position, Duration.zero);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
      },
    );
  }

  testWidgets('touch hold released during pending native rate restores speed', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await session.setRate(1.5);
    final gate = Completer<void>();
    engine.nextRate = gate;
    final gesture = await tester.startGesture(_surfacePoint(tester));
    await tester.pump(const Duration(milliseconds: 450));
    expect(engine.currentSnapshot.rate, 1.5);
    await gesture.up();
    gate.complete();
    await _pumpFrames(tester);
    expect(engine.currentSnapshot.rate, 1.5);
    expect(engine.currentSnapshot.position, Duration.zero);
    expect(find.byKey(const ValueKey('player-rate-hud')), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  for (final action in ['drag', 'short touch', 'mouse', 'button', 'live']) {
    testWidgets('$action does not trigger touch acceleration', (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          const AppSettings.defaults(),
          target: action == 'live' ? const LivePlaybackTarget('12') : null,
        ),
      );
      await _pumpFrames(tester);
      final gesture = await tester.startGesture(
        action == 'button'
            ? tester.getCenter(find.byTooltip('暂停（空格）'))
            : _surfacePoint(tester),
        kind: action == 'mouse'
            ? PointerDeviceKind.mouse
            : PointerDeviceKind.touch,
      );
      if (action == 'drag') await gesture.moveBy(const Offset(60, 0));
      await tester.pump(
        Duration(milliseconds: action == 'short touch' ? 150 : 1700),
      );
      expect(engine.currentSnapshot.rate, 1);
      await gesture.up();
      await _pumpFrames(tester);
      await _pumpSurfaceTap(tester);
      expect(engine.currentSnapshot.rate, 1);
      expect(find.byKey(const ValueKey('player-rate-hud')), findsNothing);
      if (action == 'short touch') {
        expect(find.byKey(const ValueKey('player-controls')), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    });
  }

  for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
    for (final visible in [true, false]) {
      testWidgets(
        '${kind.name} double tap preserves ${visible ? 'visible' : 'hidden'} controls across fullscreen',
        (tester) async {
          final engine = _FakeEngine();
          final session = _session(engine);
          final window = _FakeWindowService();
          addTearDown(session.close);
          await tester.pumpWidget(
            _app(session, window, const AppSettings.defaults()),
          );
          await _pumpFrames(tester);
          await session.pause();
          await session.seek(const Duration(seconds: 12));
          final generation = session.sourceGeneration;
          final opens = engine.opens;
          final target = find.byKey(
            const ValueKey('player-surface-tap-target'),
          );
          final controls = find.byKey(const ValueKey('player-controls'));
          Offset surfacePoint() =>
              tester.getTopLeft(target) + const Offset(30, 50);

          Future<void> singleTap() async {
            await tester.tapAt(surfacePoint(), kind: kind);
            await _pumpSurfaceTap(tester);
          }

          Future<void> doubleTap() async {
            final point = surfacePoint();
            await tester.tapAt(point, kind: kind);
            await tester.pump(const Duration(milliseconds: 50));
            await tester.tapAt(point, kind: kind);
            await _pumpFrames(tester);
            await _pumpSurfaceTap(tester);
          }

          void expectControls(bool shown) =>
              expect(controls, shown ? findsOneWidget : findsNothing);

          if (!visible) await singleTap();
          expectControls(visible);
          await doubleTap();
          expect(window.fullScreen, isTrue);
          expectControls(visible);
          await doubleTap();
          expect(window.fullScreen, isFalse);
          expectControls(visible);

          // A single tap in fullscreen changes the state that returns inline.
          await doubleTap();
          expect(window.fullScreen, isTrue);
          await singleTap();
          expectControls(!visible);
          await doubleTap();
          expect(window.fullScreen, isFalse);
          expectControls(!visible);
          await singleTap();
          expectControls(visible);

          expect(engine.opens, opens);
          expect(session.sourceGeneration, generation);
          expect(engine.currentSnapshot.position, const Duration(seconds: 12));
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(find.byType(VideoSurface), findsOneWidget);
          expect(engine.maxSurfaces, 1);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
        },
      );
    }
  }

  for (final live in [false, true]) {
    for (final fullscreen in [false, true]) {
      testWidgets(
        'dynamic controls reveal on hover and hide after 2.5 seconds or exit live=$live fullscreen=$fullscreen',
        (tester) async {
          final engine = _FakeEngine();
          final session = _session(engine);
          addTearDown(session.close);
          await tester.pumpWidget(
            _app(
              session,
              _FakeWindowService(),
              AppSettings(playerControlsMode: PlayerControlsMode.dynamic),
              target: live ? const LivePlaybackTarget('12') : null,
            ),
          );
          await _pumpFrames(tester);
          if (fullscreen) {
            await tester.tap(find.byTooltip('全屏（F）'));
            await _pumpFrames(tester);
          }
          final controls = find.byKey(const ValueKey('player-controls'));
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer(location: const Offset(-10, -10));
          final point = _surfacePoint(tester);
          final playing = engine.currentSnapshot.desiredPlaying;
          double opacity() => tester
              .widget<FadeTransition>(
                find
                    .ancestor(
                      of: controls,
                      matching: find.byType(FadeTransition),
                    )
                    .first,
              )
              .opacity
              .value;
          await mouse.moveTo(point);
          await tester.pump();
          expect(controls, findsOneWidget);
          if (live) {
            await tester.pump(const Duration(milliseconds: 600));
            await mouse.down(point);
            await mouse.up();
            // A live surface click must not restart the hover deadline.
            await tester.pump(const Duration(milliseconds: 1899));
          } else {
            await tester.pump(const Duration(milliseconds: 2499));
          }
          expect(controls, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 1));
          expect(controls.hitTestable(), findsNothing);
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), inExclusiveRange(0, 1));
          await tester.pump(const Duration(milliseconds: 116));
          await tester.pump();
          expect(controls, findsNothing);
          await mouse.moveTo(point + const Offset(5, 0));
          await tester.pump();
          expect(opacity(), 0);
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), inExclusiveRange(0, 1));
          await tester.pump(const Duration(milliseconds: 600));
          expect(controls, findsOneWidget);
          await mouse.moveTo(point + const Offset(10, 0));
          await tester.pump(const Duration(milliseconds: 2499));
          expect(controls, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 1));
          expect(controls.hitTestable(), findsNothing);
          await tester.pump(const Duration(milliseconds: 216));
          await tester.pump();
          expect(controls, findsNothing);
          await mouse.moveTo(point + const Offset(15, 0));
          await tester.pump();
          expect(controls, findsOneWidget);
          await tester.pump(const Duration(milliseconds: 200));
          await mouse.moveTo(const Offset(-10, -10));
          await tester.pump();
          expect(controls.hitTestable(), findsNothing);
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), inExclusiveRange(0, 1));
          await tester.pump(const Duration(milliseconds: 116));
          await tester.pump();
          expect(controls, findsNothing);
          expect(engine.currentSnapshot.desiredPlaying, playing);
          expect(engine.opens, 1);
          expect(engine.maxSurfaces, 1);
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
        },
      );

      for (final kind in [PointerDeviceKind.mouse, PointerDeviceKind.touch]) {
        testWidgets(
          'dynamic ${kind.name} surface taps toggle playback only for video live=$live fullscreen=$fullscreen',
          (tester) async {
            final engine = _FakeEngine();
            final session = _session(engine);
            final window = _FakeWindowService();
            addTearDown(session.close);
            await tester.pumpWidget(
              _app(
                session,
                window,
                AppSettings(playerControlsMode: PlayerControlsMode.dynamic),
                target: live ? const LivePlaybackTarget('12') : null,
              ),
            );
            await _pumpFrames(tester);
            if (fullscreen) {
              await tester.tap(find.byTooltip('全屏（F）'));
              await _pumpFrames(tester);
            }
            final controls = find.byKey(const ValueKey('player-controls'));
            final mouse = kind == PointerDeviceKind.mouse
                ? await tester.createGesture(kind: PointerDeviceKind.mouse)
                : null;
            if (mouse != null) {
              await mouse.addPointer(location: const Offset(-10, -10));
              await mouse.moveTo(_surfacePoint(tester));
              await tester.pump();
            }
            await tester.pump(const Duration(milliseconds: 2500));
            await tester.pump(const Duration(milliseconds: 216));
            await tester.pump();
            expect(controls, findsNothing);
            final playing = engine.currentSnapshot.desiredPlaying;
            await tester.tapAt(_surfacePoint(tester), kind: kind);
            await _pumpSurfaceTap(tester);
            expect(
              engine.currentSnapshot.desiredPlaying,
              live ? playing : !playing,
            );
            expect(controls, live ? findsNothing : findsOneWidget);
            await tester.tapAt(_surfacePoint(tester), kind: kind);
            await _pumpSurfaceTap(tester);
            expect(engine.currentSnapshot.desiredPlaying, playing);
            expect(controls, live ? findsNothing : findsOneWidget);

            // The double-tap recognizer must win without issuing a play command.
            final point = _surfacePoint(tester);
            await tester.tapAt(point, kind: kind);
            await tester.pump(const Duration(milliseconds: 50));
            await tester.tapAt(point, kind: kind);
            await _pumpFrames(tester);
            expect(window.fullScreen, !fullscreen);
            expect(engine.currentSnapshot.desiredPlaying, playing);
            expect(engine.opens, 1);
            expect(engine.maxSurfaces, 1);
            if (mouse != null) await mouse.removePointer();
            await tester.pumpWidget(const SizedBox());
            await _pumpFrames(tester);
          },
        );
      }
    }
  }

  for (final live in [false, true]) {
    testWidgets('dynamic controls retain a pressed control live=$live', (
      tester,
    ) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          AppSettings(playerControlsMode: PlayerControlsMode.dynamic),
          target: live ? const LivePlaybackTarget('12') : null,
        ),
      );
      await _pumpFrames(tester);
      final controls = find.byKey(const ValueKey('player-controls'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('音量')),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump(const Duration(seconds: 4));
      expect(controls, findsOneWidget);
      await gesture.cancel();
      await gesture.moveTo(_surfacePoint(tester));
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 216));
      await tester.pump();
      expect(controls, findsNothing);
      await gesture.removePointer();
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    });
  }

  testWidgets(
    'changing modes cancels hide timers and hidden views dispose them',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      final window = _FakeWindowService();
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      final controls = find.byKey(const ValueKey('player-controls'));
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await tester.tapAt(_surfacePoint(tester));
      await _pumpSurfaceTap(tester);
      await mouse.moveTo(_surfacePoint(tester) + const Offset(5, 0));
      await tester.pump();
      expect(controls, findsNothing);
      final dynamicSettings = AppSettings(
        playerControlsMode: PlayerControlsMode.dynamic,
      );
      await tester.pumpWidget(_app(session, window, dynamicSettings));
      await _pumpFrames(tester);
      expect(controls, findsOneWidget);
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(controls, findsOneWidget);
      await tester.pumpWidget(_app(session, window, dynamicSettings));
      await _pumpFrames(tester);
      await tester.pumpWidget(
        _app(session, window, dynamicSettings, active: false),
      );
      await _pumpFrames(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(_app(session, window, dynamicSettings));
      await _pumpFrames(tester);
      await mouse.moveTo(_surfacePoint(tester) + const Offset(10, 0));
      await tester.pump();
      expect(controls, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
    },
  );

  testWidgets(
    'dynamic controls stay mounted during a touch hold without tapping',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          AppSettings(
            playerControlsMode: PlayerControlsMode.dynamic,
            shortcuts: const ShortcutSettings.defaults().withPlayback(
              holdDelayMs: 200,
              holdRate: 3,
            ),
          ),
        ),
      );
      await _pumpFrames(tester);
      final playing = engine.currentSnapshot.desiredPlaying;
      final controls = find.byKey(const ValueKey('player-controls'));
      final touch = await tester.startGesture(_surfacePoint(tester));
      await tester.pump(const Duration(milliseconds: 250));
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 3);
      await tester.pump(const Duration(seconds: 4));
      expect(controls, findsOneWidget);
      await touch.up();
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1);
      expect(engine.currentSnapshot.desiredPlaying, playing);
      await tester.pump(const Duration(milliseconds: 2500));
      await tester.pump(const Duration(milliseconds: 216));
      await tester.pump();
      expect(controls, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  for (final fullscreen in [false, true]) {
    for (final width in [400.0, 1200.0]) {
      testWidgets(
        'click controls fade, release input and reverse at width=$width fullscreen=$fullscreen',
        (tester) async {
          tester.view.physicalSize = const Size(1280, 800);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final engine = _FakeEngine();
          final session = _session(engine);
          final window = _FakeWindowService();
          addTearDown(session.close);
          await tester.pumpWidget(
            _app(session, window, const AppSettings.defaults(), width: width),
          );
          await _pumpFrames(tester);
          await session.pause();
          if (fullscreen) {
            await tester.tap(find.byTooltip('全屏（F）'));
            await _pumpFrames(tester);
          }
          final controls = find.byKey(const ValueKey('player-controls'));
          final generation = session.sourceGeneration;
          final opens = engine.opens;
          // Invoke the accepted single tap to isolate animation timing from the
          // double-tap recognizer's deadline (gestures have separate coverage).
          void tapSurface() => tester
              .widget<GestureDetector>(
                find.byKey(const ValueKey('player-surface-tap-target')),
              )
              .onTap!();
          double opacity() => tester
              .widget<FadeTransition>(
                find
                    .ancestor(
                      of: controls,
                      matching: find.byType(FadeTransition),
                    )
                    .first,
              )
              .opacity
              .value;

          expect(opacity(), 1);
          tapSurface();
          await tester.pump();
          expect(controls, findsOneWidget);
          expect(controls.hitTestable(), findsNothing);
          await tester.pump(const Duration(milliseconds: 100));
          final fadingOut = opacity();
          expect(fadingOut, inExclusiveRange(0, 1));
          tapSurface();
          await tester.pump();
          expect(opacity(), closeTo(fadingOut, .001));
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), greaterThan(fadingOut));
          await tester.pump(const Duration(milliseconds: 200));
          expect(opacity(), 1);

          tapSurface();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 216));
          await tester.pump();
          expect(controls, findsNothing);
          tapSurface();
          await tester.pump();
          expect(opacity(), 0);
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), inExclusiveRange(0, 1));
          await tester.pump(const Duration(milliseconds: 100));
          expect(opacity(), 1);
          expect(session.sourceGeneration, generation);
          expect(engine.opens, opens);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(engine.maxSurfaces, 1);
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
        },
      );
    }
    for (final (content, target) in <(String, ContentPlaybackTarget?)>[
      ('video', null),
      ('pgc', const PgcPlaybackTarget('12', cid: '123')),
      ('live', const LivePlaybackTarget('12')),
    ]) {
      testWidgets(
        'click controls hide after five seconds content=$content fullscreen=$fullscreen',
        (tester) async {
          final engine = _FakeEngine();
          final session = _session(engine);
          addTearDown(session.close);
          await tester.pumpWidget(
            _app(
              session,
              _FakeWindowService(),
              const AppSettings.defaults(),
              target: target,
            ),
          );
          await _pumpFrames(tester);
          if (fullscreen) {
            await tester.tap(find.byTooltip('全屏（F）'));
            await _pumpFrames(tester);
          }
          final controls = find.byKey(const ValueKey('player-controls'));
          final playing = engine.currentSnapshot.desiredPlaying;
          final surface = tester.widget<GestureDetector>(
            find.byKey(const ValueKey('player-surface-tap-target')),
          );
          surface.onTap!();
          surface.onTap!();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 4999));
          expect(controls, findsOneWidget);
          expect(controls.hitTestable(), findsOneWidget);
          await tester.pump(const Duration(milliseconds: 1));
          expect(controls, findsOneWidget);
          expect(controls.hitTestable(), findsNothing);
          await tester.pump(const Duration(milliseconds: 100));
          final fade = tester.widget<FadeTransition>(
            find
                .ancestor(of: controls, matching: find.byType(FadeTransition))
                .first,
          );
          expect(fade.opacity.value, inExclusiveRange(0, 1));
          await tester.pump(const Duration(milliseconds: 116));
          await tester.pump();
          expect(controls, findsNothing);
          expect(engine.currentSnapshot.desiredPlaying, playing);
          expect(engine.opens, 1);
          await tester.pumpWidget(const SizedBox());
          await _pumpFrames(tester);
        },
      );
    }
  }

  for (final mode in PlayerControlsMode.values) {
    for (final width in [320.0, 1200.0]) {
      for (final fullscreen in [false, true]) {
        for (final live in [false, true]) {
          testWidgets(
            '${mode.name} controls stay visible during mouse activity and hover width=$width live=$live fullscreen=$fullscreen',
            (tester) async {
              tester.view.physicalSize = Size(width, 800);
              tester.view.devicePixelRatio = 1;
              addTearDown(tester.view.resetPhysicalSize);
              addTearDown(tester.view.resetDevicePixelRatio);
              final engine = _FakeEngine();
              final session = _session(engine);
              addTearDown(session.close);
              await tester.pumpWidget(
                _app(
                  session,
                  _FakeWindowService(),
                  AppSettings(playerControlsMode: mode),
                  width: width,
                  target: live ? const LivePlaybackTarget('12') : null,
                ),
              );
              await _pumpFrames(tester);
              if (fullscreen) {
                await tester.tap(find.byTooltip('全屏（F）'));
                await _pumpFrames(tester);
              }
              final controls = find.byKey(const ValueKey('player-controls'));
              final barPoint = tester.getCenter(controls);
              final mouse = await tester.createGesture(
                kind: PointerDeviceKind.mouse,
              );
              await mouse.addPointer(location: const Offset(-10, -10));
              final playing = engine.currentSnapshot.desiredPlaying;
              final generation = session.sourceGeneration;
              final idleMilliseconds = mode == PlayerControlsMode.dynamic
                  ? 2500
                  : 5000;
              for (var i = 0; i < 3; i++) {
                await mouse.moveTo(_surfacePoint(tester) + Offset(i * 5, 0));
                await tester.pump(
                  Duration(milliseconds: idleMilliseconds - 1000),
                );
                expect(controls.hitTestable(), findsOneWidget);
              }
              for (final region in [
                controls,
                find.byKey(const ValueKey('player-control-title-layer')),
                if (width == 320)
                  find.byKey(const ValueKey('compact-playback-actions')),
                controls,
              ]) {
                await mouse.moveTo(tester.getCenter(region));
                await tester.pump(const Duration(seconds: 6));
                expect(controls.hitTestable(), findsOneWidget);
              }
              await mouse.moveTo(_surfacePoint(tester));
              await tester.pump(Duration(milliseconds: idleMilliseconds - 1));
              expect(controls.hitTestable(), findsOneWidget);
              await tester.pump(const Duration(milliseconds: 1));
              expect(controls.hitTestable(), findsNothing);
              await tester.pump(const Duration(milliseconds: 216));
              await tester.pump();
              expect(controls, findsNothing);
              await mouse.moveTo(barPoint);
              await tester.pump();
              await tester.pump(const Duration(seconds: 6));
              expect(
                controls,
                mode == PlayerControlsMode.dynamic
                    ? findsOneWidget
                    : findsNothing,
              );
              expect(engine.currentSnapshot.desiredPlaying, playing);
              expect(session.sourceGeneration, generation);
              expect(engine.opens, 1);
              expect(engine.maxSurfaces, 1);
              await mouse.removePointer();
              await tester.pumpWidget(const SizedBox());
              await _pumpFrames(tester);
            },
          );
        }
      }
    }

    testWidgets(
      '${mode.name} controls release hover when resizing removes compact actions',
      (tester) async {
        tester.view.physicalSize = const Size(1280, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final engine = _FakeEngine();
        final session = _session(engine);
        final window = _FakeWindowService();
        final settings = AppSettings(playerControlsMode: mode);
        addTearDown(session.close);
        await tester.pumpWidget(_app(session, window, settings, width: 320));
        await _pumpFrames(tester);
        final controls = find.byKey(const ValueKey('player-controls'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(-10, -10));
        await mouse.moveTo(
          tester.getCenter(
            find.byKey(const ValueKey('compact-playback-actions')),
          ),
        );
        await tester.pump(const Duration(seconds: 6));
        expect(controls.hitTestable(), findsOneWidget);
        await tester.pumpWidget(_app(session, window, settings, width: 1200));
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(milliseconds: 216));
        await tester.pump();
        expect(controls, findsNothing);
        expect(engine.opens, 1);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
      },
    );
  }

  testWidgets(
    'click controls wait for drags and menus, then restart the idle deadline',
    (tester) async {
      final session = _session(_FakeEngine());
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, _FakeWindowService(), const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      final controls = find.byKey(const ValueKey('player-controls'));
      await tester.pump(const Duration(seconds: 4));
      final gesture = await tester.startGesture(
        tester.getCenter(find.byTooltip('音量')),
      );
      await tester.pump(const Duration(seconds: 6));
      expect(controls, findsOneWidget);
      await gesture.up();
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('音量'));
      await _pumpFrames(tester);
      expect(
        find.byKey(const ValueKey('player-volume-slider')),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 10));
      expect(controls, findsOneWidget);
      await tester.tapAt(const Offset(5, 5));
      await _pumpFrames(tester);
      await tester.pump(const Duration(seconds: 4));
      expect(controls, findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(milliseconds: 216));
      await tester.pump();
      expect(controls, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  testWidgets(
    'click controls retain the focused editor and release it when hidden',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final session = _session(_FakeEngine());
      addTearDown(session.close);
      final editorFocus = FocusNode();
      addTearDown(editorFocus.dispose);
      await tester.pumpWidget(
        _app(
          session,
          _FakeWindowService(),
          const AppSettings.defaults(),
          width: 1200,
          composer: (_) =>
              TextField(key: const Key('click-editor'), focusNode: editorFocus),
        ),
      );
      await _pumpFrames(tester);
      final controls = find.byKey(const ValueKey('player-controls'));
      await tester.tap(find.byKey(const Key('click-editor')));
      await tester.enterText(find.byKey(const Key('click-editor')), '草稿');
      await tester.pump(const Duration(seconds: 10));
      expect(editorFocus.hasFocus, isTrue);
      expect(controls, findsOneWidget);
      await tester.tapAt(_surfacePoint(tester));
      await _pumpSurfaceTap(tester);
      expect(editorFocus.hasFocus, isFalse);
      expect(editorFocus.canRequestFocus, isFalse);
      await tester.pump(const Duration(milliseconds: 216));
      await tester.pump();
      expect(controls, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  testWidgets(
    'click controls suspend idle hiding in background and hidden views',
    (tester) async {
      final session = _session(_FakeEngine());
      addTearDown(session.close);
      final window = _FakeWindowService();
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      final controls = find.byKey(const ValueKey('player-controls'));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(seconds: 10));
      expect(controls, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 4));
      expect(controls, findsOneWidget);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults(), active: false),
      );
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      expect(controls, findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump(const Duration(milliseconds: 216));
      await tester.pump();
      expect(controls, findsNothing);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );

  testWidgets('click controls stay hidden during mouse activity and keys', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    final target = find.byKey(const ValueKey('player-surface-tap-target'));
    final controls = find.byKey(const ValueKey('player-controls'));
    final point = tester.getTopLeft(target) + const Offset(30, 50);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await tester.tapAt(point);
    await _pumpSurfaceTap(tester);
    expect(controls, findsNothing);
    await mouse.moveTo(point + const Offset(5, 0));
    await tester.pump();
    expect(controls, findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();
    expect(engine.currentSnapshot.rate, 1.25);
    expect(controls, findsNothing);
    expect(find.byKey(const ValueKey('player-rate-feedback')), findsOneWidget);
    expect(find.text('播放速度 1.25x'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const ValueKey('player-rate-feedback')), findsNothing);
    expect(controls, findsNothing);
    await tester.tapAt(point);
    await _pumpSurfaceTap(tester);
    expect(controls, findsOneWidget);
    await mouse.moveTo(point + const Offset(10, 0));
    await tester.pump(const Duration(seconds: 4));
    expect(controls, findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 216));
    await tester.pump();
    expect(controls, findsNothing);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets(
    'surface tap only toggles controls while Space toggles playback',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, _FakeWindowService(), const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      final target = find.byKey(const ValueKey('player-surface-tap-target'));
      final controls = find.byKey(const ValueKey('player-controls'));
      final playing = engine.currentSnapshot.desiredPlaying;
      await tester.tapAt(tester.getTopLeft(target) + const Offset(30, 50));
      await _pumpSurfaceTap(tester);
      expect(engine.currentSnapshot.desiredPlaying, playing);
      expect(controls, findsNothing);
      await tester.tapAt(tester.getTopLeft(target) + const Offset(30, 50));
      await _pumpSurfaceTap(tester);
      expect(engine.currentSnapshot.desiredPlaying, playing);
      expect(controls, findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.desiredPlaying, !playing);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets(
    'short Right seeks once and held Right restores speed on release and focus loss',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, _FakeWindowService(), const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      final target = find.byKey(const ValueKey('player-surface-tap-target'));
      await tester.tapAt(tester.getTopLeft(target) + const Offset(30, 50));
      await _pumpSurfaceTap(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.position, const Duration(seconds: 3));
      await session.setRate(1.5);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 450));
      expect(engine.currentSnapshot.rate, 3);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1.5);
      expect(engine.currentSnapshot.position, const Duration(seconds: 3));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 450));
      expect(engine.currentSnapshot.rate, 3);
      await tester.tap(find.byKey(const Key('search-field')));
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.rate, 1.5);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await _pumpFrames(tester);
      expect(engine.currentSnapshot.position, const Duration(seconds: 3));
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets('disabled action and modal dialog do not handle player keys', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await tester.tapAt(
      tester.getTopLeft(
            find.byKey(const ValueKey('player-surface-tap-target')),
          ) +
          const Offset(30, 50),
    );
    await _pumpSurfaceTap(tester);
    final pauses = engine.pauses;
    final context = tester.element(find.byType(PlaybackPanel));
    unawaited(
      showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(content: Text('modal')),
      ),
    );
    // Playback's interpolation ticker uses a real monotonic clock. Wait only
    // for the dialog transition instead of settling every playback frame.
    await _pumpFrames(tester);
    await _pumpSurfaceTap(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await _pumpFrames(tester);
    expect(engine.pauses, pauses);
    expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
    Navigator.of(context).pop();
    await _pumpFrames(tester);
    await _pumpSurfaceTap(tester);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  testWidgets(
    'failed playback reloads from its overflow menu and keeps pause',
    (tester) async {
      final engine = _FakeEngine();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, _FakeWindowService(), const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      await session.seek(const Duration(seconds: 12));
      await session.pause();
      await tester.tapAt(
        tester.getTopLeft(
              find.byKey(const ValueKey('player-surface-tap-target')),
            ) +
            const Offset(30, 50),
      );
      await _pumpSurfaceTap(tester);
      expect(find.byKey(const ValueKey('player-controls')), findsNothing);
      engine._failures.add(
        PlayerFailure(
          PlayerFailureKind.nativePlayback,
          '测试播放错误',
          engine.currentSnapshot.generation,
        ),
      );
      await _pumpFrames(tester);
      expect(find.byKey(const ValueKey('player-controls')), findsOneWidget);
      expect(find.byTooltip('更多播放选项').hitTestable(), findsOneWidget);
      expect(find.byTooltip('全屏（F）').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('重新加载'), findsNothing);
      await tester.tap(find.byTooltip('播放错误选项'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('重新加载'));
      await _pumpFrames(tester);
      expect(engine.opens, 2);
      expect(engine.currentSnapshot.position, const Duration(seconds: 12));
      expect(engine.currentSnapshot.phase, isNot(PlaybackPhase.playing));
      expect(engine.currentSnapshot.desiredPlaying, isFalse);
      expect(engine.maxSurfaces, 1);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets('fullscreen refresh preserves paused position and one source', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await session.seek(const Duration(seconds: 12));
    await session.pause();
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f5);
    await _pumpFrames(tester);
    expect(engine.opens, 2);
    expect(engine.currentSnapshot.position, const Duration(seconds: 12));
    expect(engine.currentSnapshot.desiredPlaying, isFalse);
    expect(engine.maxSurfaces, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpFrames(tester);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });

  testWidgets('native failure keeps fullscreen controls and settings usable', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final session = _session(engine);
    final window = _FakeWindowService();
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, window, const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    engine._failures.add(
      PlayerFailure(
        PlayerFailureKind.nativePlayback,
        '测试播放错误',
        engine.currentSnapshot.generation,
      ),
    );
    await _pumpFrames(tester);
    expect(find.byKey(const ValueKey('player-controls')), findsOneWidget);
    await tester.tap(find.byTooltip('播放配置'));
    await _pumpFrames(tester);
    await _pumpSurfaceTap(tester);
    expect(find.byType(Dialog), findsWidgets);
    Navigator.of(tester.element(find.byType(TabBar))).pop();
    await _pumpFrames(tester);
    await _pumpSurfaceTap(tester);
    await tester.tap(find.byTooltip('退出全屏（Esc）'));
    await _pumpFrames(tester);
    expect(window.fullScreen, isFalse);
    expect(engine.maxSurfaces, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  for (final width in [320.0, 800.0]) {
    testWidgets(
      'composer controls at $width keep video visible and text focus local',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1000, 1000);
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        final engine = _FakeEngine();
        final session = _session(engine);
        addTearDown(session.close);
        await tester.pumpWidget(
          _app(
            session,
            _FakeWindowService(),
            const AppSettings.defaults(),
            width: width,
            composer: (_) => const SizedBox(
              height: 36,
              child: TextField(
                key: Key('composer'),
                decoration: InputDecoration(isDense: true, hintText: '发送弹幕'),
              ),
            ),
          ),
        );
        await _pumpFrames(tester);
        expect(tester.takeException(), isNull);
        if (find.byTooltip('发送弹幕').evaluate().isNotEmpty) {
          await tester.tap(find.byTooltip('发送弹幕'));
          await tester.pump();
        }
        final playerRect = tester.getRect(find.byType(PlaybackPanel));
        final composerRect = tester.getRect(find.byKey(const Key('composer')));
        expect(composerRect.top, greaterThan(playerRect.top + 40));
        await tester.tap(find.byKey(const Key('composer')));
        final pauses = engine.pauses;
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
        await _pumpFrames(tester);
        expect(engine.pauses, pauses);
        expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await _pumpFrames(tester);
      },
    );
  }
  testWidgets('settings dialog at 400 width and doubled text has no overflow', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(
        session,
        _FakeWindowService(),
        const AppSettings.defaults(),
        textScale: 2,
      ),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('更多播放选项'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('播放配置'));
    await _pumpFrames(tester);
    expect(find.text('播放器设置'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  testWidgets(
    'switching from fullscreen to another tab mounts only one surface',
    (tester) async {
      final engine = _FakeEngine();
      final window = _FakeWindowService();
      final session = _session(engine);
      addTearDown(session.close);
      Widget app(int active) => ProviderScope(
        overrides: [playbackSessionProvider.overrideWithValue(session)],
        child: InputTestApp(
          home: Scaffold(
            body: Stack(
              children: [
                for (var i = 0; i < 2; i++)
                  Offstage(
                    key: ValueKey(i),
                    offstage: active != i,
                    child: WorkspaceActivity(
                      active: active == i,
                      child: SizedBox(
                        width: 400,
                        height: 225,
                        child: PlaybackPanel(
                          detail: _detail,
                          part: _part,
                          settings: const AppSettings.defaults(),
                          onToggleComments: () {},
                          window: window,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpWidget(app(0));
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('全屏（F）'));
      await _pumpFrames(tester);
      await tester.pumpWidget(app(1));
      await _pumpFrames(tester);
      expect(engine.maxSurfaces, 1);
      expect(engine.activeSurfaces, 1);
      expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
      expect(window.fullScreen, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets('pending fullscreen is cancelled when its page becomes hidden', (
    tester,
  ) async {
    final engine = _FakeEngine();
    final window = _DelayedWindow();
    final session = _session(engine);
    addTearDown(session.close);
    final observer = _FocusAtPopObserver();
    await tester.pumpWidget(
      _app(
        session,
        window,
        const AppSettings.defaults(),
        navigatorObserver: observer,
      ),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    await tester.pumpWidget(
      _app(
        session,
        window,
        const AppSettings.defaults(),
        active: false,
        navigatorObserver: observer,
      ),
    );
    await _pumpFrames(tester);
    expect(observer.popCount, 0);
    window.gate.complete();
    await _pumpFrames(tester);
    expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
    expect(engine.activeSurfaces, 0);
    expect(window.fullScreen, isFalse);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
  });
  testWidgets(
    'an open fullscreen closes when hidden without navigator mutation during build',
    (tester) async {
      final engine = _FakeEngine();
      final window = _FakeWindowService();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      await _pumpFrames(tester);
      await tester.tap(find.byTooltip('全屏（F）'));
      await _pumpFrames(tester);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults(), active: false),
      );
      await _pumpFrames(tester);
      expect(find.byTooltip('退出全屏（Esc）'), findsNothing);
      expect(window.fullScreen, isFalse);
      expect(engine.activeSurfaces, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await _pumpFrames(tester);
    },
  );
  testWidgets('compact controls retain fullscreen and one surface', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = _FakeEngine();
    final window = _FakeWindowService();
    final session = _session(engine);
    addTearDown(session.close);

    await tester.pumpWidget(
      _app(session, window, const AppSettings.defaults(), textScale: 2),
    );
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('全屏（F）'), findsOneWidget);
    expect(engine.maxSurfaces, 1);

    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
    expect(window.fullScreen, isTrue);
    expect(find.byTooltip('退出全屏（Esc）'), findsOneWidget);
    expect(engine.maxSurfaces, 1);
    expect(engine.opens, 1);

    await tester.pumpWidget(
      _app(session, window, AppSettings(danmakuEnabled: false), textScale: 2),
    );
    await _pumpFrames(tester);
    expect(find.byTooltip('开启弹幕'), findsOneWidget);

    await tester.tap(find.byTooltip('退出全屏（Esc）'));
    await _pumpFrames(tester);
    expect(window.fullScreen, isFalse);
    expect(engine.maxSurfaces, 1);
    expect(engine.opens, 1);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _pumpFrames(tester);
    expect(window.fullScreen, isFalse);
    expect(engine.opens, 1);
    expect(engine.maxSurfaces, 1);
  });

  testWidgets('player shortcuts do not steal focus from search', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = _FakeEngine();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, _FakeWindowService(), const AppSettings.defaults()),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final initialPauses = engine.pauses;
    final initialRate = engine.currentSnapshot.rate;
    final initialVolume = engine.currentSnapshot.volume;
    await tester.tap(find.byKey(const Key('search-field')));
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(engine.pauses, initialPauses);
    expect(engine.currentSnapshot.rate, initialRate);
    expect(engine.currentSnapshot.volume, initialVolume);
  });

  testWidgets('fullscreen exit releases focus before one route pop', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = _FakeEngine();
    final window = _FakeWindowService();
    final observer = _FocusAtPopObserver();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(
        session,
        window,
        const AppSettings.defaults(),
        textScale: 2,
        navigatorObserver: observer,
      ),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'video player');

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    expect(observer.popCount, 0);
    expect(window.fullScreen, isTrue);
    expect(find.byTooltip('退出全屏（Esc）'), findsOneWidget);

    await _pumpFrames(tester);
    expect(observer.popCount, 1);
    expect(observer.focusAtPop, isNot('video player'));
    expect(window.fullScreen, isFalse);
    expect(engine.maxSurfaces, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('pending fullscreen exit does not pop a disposed navigator', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final engine = _FakeEngine();
    final window = _FakeWindowService();
    final session = _session(engine);
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, window, const AppSettings.defaults(), textScale: 2),
    );
    await _pumpFrames(tester);
    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpWidget(const SizedBox());
    await _pumpFrames(tester);
    expect(tester.takeException(), isNull);
  });

  for (final fullscreen in [false, true]) {
    testWidgets('ended playback hides stale buffering fullscreen=$fullscreen', (
      tester,
    ) async {
      final engine = _FakeEngine();
      final window = _FakeWindowService();
      final session = _session(engine);
      addTearDown(session.close);
      await tester.pumpWidget(
        _app(session, window, const AppSettings.defaults()),
      );
      await _pumpFrames(tester);
      if (fullscreen) {
        await tester.tap(find.byTooltip('全屏（F）'));
        await _pumpFrames(tester);
      }

      engine._emit(
        engine.currentSnapshot.copyWith(
          phase: PlaybackPhase.buffering,
          isBuffering: true,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('正在准备音视频…'), findsOneWidget);

      // Completion takes precedence even if a backend retains its last flag.
      engine._emit(
        engine.currentSnapshot.copyWith(
          phase: PlaybackPhase.ended,
          position: engine.currentSnapshot.duration,
          desiredPlaying: false,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('正在准备音视频…'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.byTooltip('播放（空格）'), findsOneWidget);

      // A later position sample must not bring the completion spinner back.
      engine._emit(engine.currentSnapshot);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('正在准备音视频…'), findsNothing);

      engine._emit(
        engine.currentSnapshot.copyWith(
          phase: PlaybackPhase.buffering,
          position: Duration.zero,
          desiredPlaying: true,
        ),
      );
      await _pumpFrames(tester);
      expect(find.text('正在准备音视频…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('player group keeps its name and exposes controls', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final gate = Completer<void>();
    final engine = _FakeEngine();
    final window = _FakeWindowService();
    final session = _session(engine, repository: _FakePlaybackRepository(gate));
    addTearDown(session.close);
    await tester.pumpWidget(
      _app(session, window, const AppSettings.defaults()),
    );
    await _pumpFrames(tester);
    expect(find.text('正在准备音视频…'), findsOneWidget);
    _expectPlayerSemantics(tester, '全屏（F）', focused: true);

    await tester.tap(find.byTooltip('全屏（F）'));
    await _pumpFrames(tester);
    expect(window.fullScreen, isTrue);
    _expectPlayerSemantics(tester, '退出全屏（Esc）', focused: true);

    gate.complete();
    await _pumpFrames(tester);
    expect(find.text('正在准备音视频…'), findsNothing);
    _expectPlayerSemantics(tester, '退出全屏（Esc）', focused: true);
    await session.seek(const Duration(seconds: 40));
    await _pumpFrames(tester);
    _expectPlayerSemantics(tester, '退出全屏（Esc）', focused: true);
    semantics.dispose();
  });
}

void _expectPlayerSemantics(
  WidgetTester tester,
  String fullscreenLabel, {
  bool focused = false,
}) {
  final group = find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == '视频播放器',
  );
  expect(group, findsOneWidget);
  final groupNode = tester.getSemantics(group);
  expect(groupNode.label, '视频播放器');
  expect(
    groupNode.flagsCollection.isFocused,
    focused ? Tristate.isTrue : Tristate.isFalse,
  );
  final fullscreenButton = find.byTooltip(fullscreenLabel);
  expect(fullscreenButton, findsOneWidget);
  expect(tester.getSemantics(fullscreenButton).tooltip, fullscreenLabel);
}

Future<void> _pumpFrames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void _wheel(
  WidgetTester tester,
  Offset position,
  Offset delta, {
  PointerDeviceKind kind = PointerDeviceKind.mouse,
}) => tester.binding.handlePointerEvent(
  PointerScrollEvent(kind: kind, position: position, scrollDelta: delta),
);

Future<void> _pumpSurfaceTap(WidgetTester tester) async {
  // Accept the single tap after the double-tap deadline, then finish fading.
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 216));
  await tester.pump();
}

Future<FocusNode> _focusRecommendation(
  WidgetTester tester,
  PlaybackSession session, {
  AppSettings settings = const AppSettings.defaults(),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1280, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final window = _FakeWindowService();
  final router = createBiliRouter(
    initialLocation: '/video/${_detail.summary.id.value}',
    playerBuilder: (_, detail, part) => PlaybackPanel(
      detail: detail,
      part: part,
      settings: settings,
      onToggleComments: () {},
      window: window,
    ),
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playbackSessionProvider.overrideWithValue(session),
        settingsRepositoryProvider.overrideWithValue(
          _Settings()..value = settings,
        ),
        videoDetailProvider(_detail.summary.id).overrideWith((_) => _detail),
        relatedVideosProvider(_detail.summary.id).overrideWith(
          (_) => List.generate(
            12,
            (i) => VideoSummary(
              id: VideoId('BV${i.toString().padLeft(10, '0')}'),
              title: '推荐视频 $i',
              coverUrl: '',
              author: 'UP',
              duration: const Duration(minutes: 3),
            ),
          ),
        ),
      ],
      child: InputTestApp.router(
        builder: AppNoticeHost.builder,
        routerConfig: router,
      ),
    ),
  );
  await _pumpFrames(tester);
  await session.pause();
  await tester.pumpAndSettle();
  final recommendation = find.text('推荐视频 0');
  await tester.ensureVisible(recommendation);
  final focus = Focus.of(tester.element(recommendation));
  focus.requestFocus();
  await tester.pumpAndSettle();
  expect(focus.hasPrimaryFocus, isTrue);
  expect(FocusManager.instance.primaryFocus?.debugLabel, isNot('video player'));
  return focus;
}

Widget _app(
  PlaybackSession session,
  WindowService window,
  AppSettings settings, {
  double textScale = 1,
  double width = 400,
  WidgetBuilder? composer,
  WidgetBuilder? overlay,
  bool active = true,
  bool scopedComposer = false,
  NavigatorObserver? navigatorObserver,
  ContentPlaybackTarget? target,
}) => ProviderScope(
  overrides: [
    playbackSessionProvider.overrideWithValue(session),
    settingsRepositoryProvider.overrideWithValue(_Settings()),
  ],
  child: InputTestApp(
    shortcuts: settings.shortcuts,
    theme: BiliTheme.light(),
    navigatorObservers: [?navigatorObserver],
    builder: (context, child) => AppNoticeHost(
      child: MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: WorkspaceActivity(
          active: active,
          child: child ?? const SizedBox(),
        ),
      ),
    ),
    home: CommandTargetScope<Object>(
      scope: CommandScope.page,
      active: active,
      commands: {
        ShortcutAction.refresh: (stroke) async {
          if (stroke.phase != InputPhase.down) return CommandOutcome.noOp;
          await session.retry();
          return CommandOutcome.completed;
        },
      },
      child: _pageScope(
        Scaffold(
          body: Column(
            children: [
              const TextField(key: Key('search-field')),
              SizedBox(
                width: width,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: PlaybackPanel(
                    detail: target == null ? _detail : null,
                    part: target == null ? _part : null,
                    target: target,
                    settings: settings,
                    onToggleComments: () {},
                    window: window,
                    danmakuComposerBuilder: composer,
                    danmakuOverlayBuilder: overlay,
                  ),
                ),
              ),
            ],
          ),
        ),
        scopedComposer,
      ),
    ),
  ),
);

Widget _pageScope(Widget child, bool scoped) => scoped
    ? ProviderScope(
        overrides: [_composerScopeProvider.overrideWithValue('房间草稿')],
        child: child,
      )
    : child;

Offset _surfacePoint(WidgetTester tester) =>
    tester.getTopLeft(find.byKey(const ValueKey('player-surface-tap-target'))) +
    const Offset(30, 50);

void _resumeApp(WidgetTester tester) {
  if (tester.binding.lifecycleState == AppLifecycleState.paused) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
  }
  if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
  }
  if (tester.binding.lifecycleState != AppLifecycleState.resumed) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }
}

PlaybackSession _session(
  PlayerEngine engine, {
  PlaybackRepository? repository,
  Duration Function()? danmakuNow,
}) => PlaybackSession(
  engine: engine,
  repository: repository ?? _FakePlaybackRepository(),
  contentRepository: _FakeContentPlaybackRepository(),
  progress: _FakeProgressStore(),
  accountScope: () => 'guest',
  danmakuNow: danmakuNow,
);

const _part = VideoPart(
  cid: '123',
  page: 1,
  title: '第一集',
  duration: Duration(minutes: 3),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '测试视频',
    coverUrl: '',
    author: 'UP',
    duration: Duration(minutes: 3),
  ),
  description: '',
  parts: [_part],
);

final class _FakeWindowService extends WindowService {
  _FakeWindowService({this.desktop = true});
  final bool desktop;
  bool fullScreen = false;
  final orientations = <FullScreenOrientation?>[];

  @override
  bool get hasDesktopWindow => desktop;

  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    fullScreen = value;
    orientations.add(value ? orientation : null);
  }
}

final class _FocusAtPopObserver extends NavigatorObserver {
  int popCount = 0;
  String? focusAtPop;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popCount++;
    focusAtPop = FocusManager.instance.primaryFocus?.debugLabel;
  }
}

final class _FakeEngine implements PlayerEngine, VideoSurfaceSource {
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  PlaybackSnapshot _current = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );
  int opens = 0;
  int pauses = 0;
  int activeSurfaces = 0;
  int maxSurfaces = 0;
  Completer<void>? nextRate;
  Completer<void>? nextVolume;

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PlayerFailure> get failures => _failures.stream;
  @override
  PlaybackSnapshot get currentSnapshot => _current;
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);

  void _emit(PlaybackSnapshot value) {
    _current = value;
    _snapshots.add(value);
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    opens++;
    _emit(
      PlaybackSnapshot(
        phase: PlaybackPhase.ready,
        generation: opens,
        position: options.startPosition,
        duration: const Duration(minutes: 3),
        rate: options.rate,
        volume: options.volume,
      ),
    );
  }

  @override
  Future<void> play() async => _emit(
    _current.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );

  @override
  Future<void> pause() async {
    pauses++;
    _emit(
      _current.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
    );
  }

  @override
  Future<void> seek(Duration target) async =>
      _emit(_current.copyWith(position: target));
  @override
  Future<void> setRate(double rate) async {
    final gate = nextRate;
    nextRate = null;
    if (gate != null) await gate.future;
    _emit(_current.copyWith(rate: rate));
  }

  @override
  Future<void> setVolume(double volume) async {
    final gate = nextVolume;
    nextVolume = null;
    if (gate != null) await gate.future;
    _emit(_current.copyWith(volume: volume));
  }

  @override
  Future<void> stop() async =>
      _emit(_current.copyWith(phase: PlaybackPhase.idle));
  @override
  Future<void> dispose() async {
    await _snapshots.close();
    await _failures.close();
  }

  @override
  Widget buildVideoSurface() => _FakeSurface(this);
}

final class _FakeSurface extends StatefulWidget {
  const _FakeSurface(this.engine);
  final _FakeEngine engine;

  @override
  State<_FakeSurface> createState() => _FakeSurfaceState();
}

final class _FakeSurfaceState extends State<_FakeSurface> {
  @override
  void initState() {
    super.initState();
    widget.engine.activeSurfaces++;
    if (widget.engine.activeSurfaces > widget.engine.maxSurfaces) {
      widget.engine.maxSurfaces = widget.engine.activeSurfaces;
    }
  }

  @override
  void dispose() {
    widget.engine.activeSurfaces--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.black);
}

final class _FakePlaybackRepository implements PlaybackRepository {
  _FakePlaybackRepository([this.gate]);

  final Completer<void>? gate;

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async {
    final waitForRelease = gate;
    if (waitForRelease != null) await waitForRelease.future;
    return PlaybackMedia(
      video: PlaybackTrack(
        urls: [Uri.parse('https://example.test/video')],
        codec: 'avc1',
        bandwidth: 1000,
      ),
      audio: PlaybackTrack(
        urls: [Uri.parse('https://example.test/audio')],
        codec: 'mp4a',
        bandwidth: 128,
      ),
      quality: 80,
      qualities: const [64, 80],
      duration: const Duration(minutes: 3),
      headers: const {},
    );
  }

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

final class _MenuRepository extends Fake
    implements PlaybackRepository, VoicePlaybackRepository {
  static const voice = PlaybackVoice(
    languageCode: 'en',
    label: 'English',
    productionType: 2,
    subtitleLanguage: 'ai-en',
  );
  PlaybackMedia _media(int quality, PlaybackVoice selected) => PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri.https('example.test', '/video/${selected.languageCode}')],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [Uri.https('example.test', '/audio/${selected.languageCode}')],
      codec: 'mp4a',
      bandwidth: 128,
    ),
    quality: quality,
    qualities: const [64, 80],
    duration: const Duration(minutes: 3),
    headers: const {},
    voices: const [voice],
    voice: selected,
  );
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => _media(quality, const PlaybackVoice.original());
  @override
  Future<PlaybackMedia> resolveVoice(
    VideoId video,
    String cid, {
    required PlaybackVoice voice,
    required int quality,
    required VideoCodecPreference preferredCodec,
    required RequestCancellation cancellation,
  }) async => _media(quality, voice);
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
  }) async => [
    SubtitleTrack(
      '中文',
      Uri.https('example.test', '/zh'),
      languageCode: 'ai-zh',
      type: 1,
      aiType: 0,
    ),
    SubtitleTrack(
      'English',
      Uri.https('example.test', '/en'),
      languageCode: 'ai-en',
      type: 1,
      aiType: 1,
    ),
  ];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => [const SubtitleCue(Duration.zero, Duration(minutes: 3), '字幕回归')];
}

final class _FakeProgressStore implements PlaybackProgressStore {
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

final class _DelayedWindow extends WindowService {
  _DelayedWindow({this.desktop = true});
  final bool desktop;
  final gate = Completer<void>();
  bool fullScreen = false;
  final orientations = <FullScreenOrientation?>[];
  @override
  bool get hasDesktopWindow => desktop;
  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    if (value) await gate.future;
    fullScreen = value;
    orientations.add(value ? orientation : null);
  }
}

final class _FakeContentPlaybackRepository
    implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => _FakePlaybackRepository().resolve(
    _detail.summary.id,
    _part.cid,
    quality: quality,
    preferredCodec: preferredCodec,
    cancellation: cancellation,
  );
}

final class _Settings implements SettingsRepository {
  AppSettings value = const AppSettings.defaults();
  @override
  Future<AppSettings> load() async => value;
  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}
