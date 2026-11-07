import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/platform/window_brightness_service.dart';
import 'package:bilisail/core/presentation/mobile_playback_status_bar.dart';
import 'package:bilisail/core/presentation/window_orientation_host.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/playback/presentation/player_picture_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/input_test_app.dart';
import '../test/support/video_card_fake_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Android native picture pinch changes texture composition and preserves session',
    (tester) async {
      const base = String.fromEnvironment('GESTURE_FIXTURE_BASE');
      if (!Platform.isAndroid || base.isEmpty) return;
      initializePlayerBackend();
      final engine = MediaKitEngine();
      final window = WindowService();
      final repository = _NativeRepository(base);
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: _Progress(),
        accountScope: () => 'guest',
      );
      final boundaryKey = GlobalKey();
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: InputTestApp(
              home: Scaffold(
                body: RepaintBoundary(
                  key: boundaryKey,
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: PlaybackPanel(
                      detail: _detail,
                      part: _detail.parts.first,
                      settings: const AppSettings.defaults(),
                      onToggleComments: () {},
                      window: window,
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
              engine.currentSnapshot.phase == PlaybackPhase.playing &&
              (engine.videoOutput as VideoFrameReadiness).frameReady.value,
        );
        await session.pause();
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.paused,
        );
        final before = engine.currentSnapshot;
        final generation = session.sourceGeneration;
        final pixels = await _picturePixels(tester, boundaryKey);
        expect(pixels.toSet().length, greaterThan(16));
        final controller = tester
            .widget<PlayerPicture>(find.byType(PlayerPicture))
            .controller;
        await _pinch(tester);
        expect(controller.value.scale, closeTo(1.5, .01));
        final zoomedPixels = await _picturePixels(tester, boundaryKey);
        expect(listEquals(pixels, zoomedPixels), isFalse);
        expect(engine.currentSnapshot.position, before.position);
        expect(engine.currentSnapshot.volume, before.volume);
        expect(engine.currentSnapshot.rate, before.rate);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(session.sourceGeneration, generation);
        var surface = tester.getRect(
          find.byKey(const ValueKey('player-surface-tap-target')),
        );
        await tester.dragFrom(surface.center, const Offset(0, -65));
        await _until(tester, () => window.isFullScreen && _isLandscape(tester));
        expect(controller.value.scale, closeTo(1.5, .01));
        await _pinch(tester);
        expect(controller.value.scale, 2);
        surface = tester.getRect(
          find.byKey(const ValueKey('player-surface-tap-target')),
        );
        await tester.dragFrom(surface.center, const Offset(0, 65));
        await _until(
          tester,
          () => !window.isFullScreen && !_isLandscape(tester),
        );
        expect(controller.value.scale, 2);
        await tester.tapAt(
          tester.getCenter(
            find.byKey(const ValueKey('player-surface-tap-target')),
          ),
        );
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('player-restore-picture'))
              .hitTestable()
              .evaluate()
              .isNotEmpty,
        );
        await tester.tap(find.byKey(const ValueKey('player-restore-picture')));
        expect(controller.value, PlayerPictureController.identity);
        expect(session.sourceGeneration, generation);
        expect(engine.currentSnapshot.generation, before.generation);
        expect(engine.currentSnapshot.position, before.position);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(tester.takeException(), isNull);
        IntegrationTestWidgetsFlutterBinding.instance.reportData = {
          'nativePicture': {
            'textureChanged': true,
            'fullscreenRetainedTransform': true,
            'restoredPicture': true,
            'sourceGenerationUnchanged': true,
          },
        };
      } finally {
        await tester.pumpWidget(const SizedBox());
        await session.close();
        await window.setFullScreen(false);
      }
    },
  );

  testWidgets(
    'Android video and live fullscreen rotate and adjust brightness and volume',
    (tester) async {
      if (!Platform.isAndroid) return;
      final engine = _Engine();
      final window = WindowService();
      final session = PlaybackSession(
        engine: engine,
        repository: _Repository(),
        contentRepository: _ContentRepository(),
        progress: _Progress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      addTearDown(() => window.setFullScreen(false));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      for (final live in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: InputTestApp(
              home: Scaffold(
                body: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: PlaybackPanel(
                    detail: live ? null : _detail,
                    part: live ? null : _detail.parts.first,
                    target: live ? const LivePlaybackTarget('12') : null,
                    settings: const AppSettings.defaults(),
                    onToggleComments: () {},
                    window: window,
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        expect(session.isLive, live);
        final opens = engine.opens;
        final generation = engine.currentSnapshot.generation;
        await tester.tapAt(
          tester.getTopLeft(
                find.byKey(const ValueKey('player-surface-tap-target')),
              ) +
              const Offset(130, 70),
        );
        await _until(
          tester,
          () => find.byTooltip('全屏（F）').evaluate().isNotEmpty,
        );
        engine.publish(
          engine.currentSnapshot.copyWith(
            videoDimensions: const VideoDimensions(1920, 1080),
          ),
        );
        await tester.tap(find.byTooltip('全屏（F）'));
        await _until(tester, () => window.isFullScreen && _isLandscape(tester));
        expect(find.byTooltip('退出全屏（Esc）'), findsOneWidget);
        final brightness = WindowBrightnessService();
        final originalBrightness = await brightness.read();
        final surface = tester.getRect(
          find.byKey(const ValueKey('player-surface-tap-target')),
        );
        await tester.dragFrom(
          Offset(surface.left + surface.width * .25, surface.center.dy),
          Offset(0, surface.height * .2),
        );
        final expectedBrightness = (originalBrightness - .2).clamp(.01, 1.0);
        await _until(
          tester,
          () => find
              .byKey(const ValueKey('player-swipe-feedback'))
              .evaluate()
              .isNotEmpty,
        );
        expect(await brightness.read(), closeTo(expectedBrightness, .02));
        await session.setVolume(50);
        await tester.pump();
        await tester.dragFrom(
          Offset(surface.left + surface.width * .75, surface.center.dy),
          Offset(0, -surface.height * .2),
        );
        await _until(
          tester,
          () => (engine.currentSnapshot.volume - 70).abs() < 1,
        );
        expect(engine.currentSnapshot.rate, 1);
        engine.publish(
          engine.currentSnapshot.copyWith(
            videoDimensions: const VideoDimensions(1080, 1920),
          ),
        );
        await _until(tester, () => !_isLandscape(tester));
        await tester.tap(find.byTooltip('退出全屏（Esc）'));
        await _until(tester, () => !window.isFullScreen);
        expect(await brightness.read(), closeTo(originalBrightness, .01));
        // A portrait source also enters fullscreen without changing to landscape.
        await tester.tap(find.byTooltip('全屏（F）'));
        await _until(tester, () => window.isFullScreen);
        expect(_isLandscape(tester), isFalse);
        await tester.tap(find.byTooltip('退出全屏（Esc）'));
        await _until(tester, () => !window.isFullScreen);
        expect(engine.opens, opens);
        expect(engine.currentSnapshot.generation, generation);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );
  testWidgets(
    'Android fullscreen exit covers native portrait rotation and restored status inset',
    (tester) async {
      if (!Platform.isAndroid) return;
      for (final systemBack in [false, true]) {
        final engine = _Engine();
        var coveredBeforeRestore = false;
        final window = _ObservedExitWindow(
          onRestore: () {
            coveredBeforeRestore = find.byType(Dialog).evaluate().length == 1;
          },
        );
        final session = PlaybackSession(
          engine: engine,
          repository: _Repository(),
          progress: _Progress(),
          accountScope: () => 'guest',
        );
        final boundary = GlobalKey();
        try {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [playbackSessionProvider.overrideWithValue(session)],
              child: InputTestApp(
                builder: (_, child) => WindowOrientationHost(
                  window: window,
                  child: RepaintBoundary(key: boundary, child: child!),
                ),
                home: MobilePlaybackStatusBar(
                  enabled: true,
                  builder: (_) => Scaffold(
                    body: SafeArea(
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: PlaybackPanel(
                          detail: _detail,
                          part: _detail.parts.first,
                          settings: const AppSettings.defaults(),
                          onToggleComments: () {},
                          window: window,
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
            () => engine.currentSnapshot.phase == PlaybackPhase.playing,
          );
          await session.pause();
          engine.publish(
            engine.currentSnapshot.copyWith(
              videoDimensions: const VideoDimensions(1920, 1080),
            ),
          );
          await tester.tapAt(
            tester.getCenter(
              find.byKey(const ValueKey('player-surface-tap-target')),
            ),
          );
          await _until(
            tester,
            () => find.byTooltip('全屏（F）').evaluate().isNotEmpty,
          );
          await tester.tap(find.byTooltip('全屏（F）'));
          await _until(
            tester,
            () => window.isFullScreen && _isLandscape(tester),
          );
          final opens = engine.opens;
          final generation = session.sourceGeneration;
          window.observeExit = true;
          if (systemBack) {
            await tester.binding.handlePopRoute();
          } else {
            await tester.tap(find.byTooltip('退出全屏（Esc）'));
          }
          await _until(
            tester,
            () =>
                !window.isFullScreen &&
                !_isLandscape(tester) &&
                tester.view.padding.top > 0,
          );
          expect(coveredBeforeRestore, isTrue);
          expect(find.byType(Dialog), findsOneWidget);
          await _expectBlackStatus(tester, boundary);
          window.restoreGate.complete();
          await _until(tester, () => find.byType(Dialog).evaluate().isEmpty);
          await _expectBlackStatus(tester, boundary);
          expect(engine.opens, opens);
          expect(session.sourceGeneration, generation);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(tester.takeException(), isNull);
        } finally {
          window.observeExit = false;
          if (!window.restoreGate.isCompleted) window.restoreGate.complete();
          await tester.pumpWidget(const SizedBox());
          await session.close();
          await window.setFullScreen(false);
        }
      }
      final binding = IntegrationTestWidgetsFlutterBinding.instance;
      binding.reportData = {
        ...?binding.reportData,
        'fullscreenExit': {
          'buttonAndSystemBack': true,
          'coveredBeforeNativeRestore': true,
          'portraitStatusPixelsBlack': true,
          'inlineStatusPixelsBlack': true,
        },
      };
    },
  );
}

Future<void> _expectBlackStatus(WidgetTester tester, GlobalKey boundary) async {
  final render =
      boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = (await tester.runAsync(() => render.toImage()))!;
  try {
    final pixels = (await tester.runAsync(image.toByteData))!;
    final offset = (12 * image.width + image.width ~/ 2) * 4;
    expect(pixels.getUint32(offset), 0x000000ff);
  } finally {
    image.dispose();
  }
}

class _ObservedExitWindow extends WindowService {
  _ObservedExitWindow({required this.onRestore});
  final VoidCallback onRestore;
  final restoreGate = Completer<void>();
  bool observeExit = false;

  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    if (!value && observeExit) onRestore();
    await super.setFullScreen(value, orientation: orientation);
    if (!value && observeExit) await restoreGate.future;
  }
}

bool _isLandscape(WidgetTester tester) =>
    tester.view.physicalSize.width > tester.view.physicalSize.height;

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
  await tester.pump(const Duration(milliseconds: 100));
}

class _Engine extends CardFakeEngine {
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
  @override
  Future<void> setRate(double rate) async =>
      publish(snapshot.copyWith(rate: rate));
  @override
  Future<void> setVolume(double volume) async =>
      publish(snapshot.copyWith(volume: volume));
}

class _Repository extends Fake implements PlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
}

class _ContentRepository implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
}

class _Progress implements PlaybackProgressStore {
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

const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '全屏方向测试',
    coverUrl: '',
    author: 'fixture',
    duration: Duration(seconds: 20),
  ),
  description: '',
  parts: [
    VideoPart(
      cid: '123',
      page: 1,
      title: 'fixture',
      duration: Duration(seconds: 20),
    ),
  ],
);

Future<Uint8List> _picturePixels(WidgetTester tester, GlobalKey key) async {
  await tester.pump(const Duration(milliseconds: 100));
  return (await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: .1);
    try {
      return (await image.toByteData())!.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }))!;
}

Future<void> _pinch(WidgetTester tester) async {
  final surface = tester.getRect(
    find.byKey(const ValueKey('player-surface-tap-target')),
  );
  final a = await tester.startGesture(
    surface.topLeft + Offset(surface.width * .4, surface.height * .4),
    pointer: 1,
  );
  final b = await tester.startGesture(
    surface.topLeft + Offset(surface.width * .6, surface.height * .4),
    pointer: 2,
  );
  await a.moveBy(Offset(-surface.width * .05, 0));
  await b.moveBy(Offset(surface.width * .05, 0));
  await a.up();
  await b.up();
  await tester.pump(const Duration(milliseconds: 100));
}

class _NativeRepository extends _Repository {
  _NativeRepository(this.base);
  final String base;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [Uri.parse('$base/sdr.mp4')],
      codec: 'avc1',
      bandwidth: 1000000,
    ),
    audio: PlaybackTrack(
      urls: [Uri.parse('$base/audio.m4a')],
      codec: 'mp4a',
      bandwidth: 128000,
    ),
    quality: 16,
    qualities: const [16],
    duration: const Duration(seconds: 20),
    headers: const {},
  );
}
