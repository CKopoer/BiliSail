import '../../support/material_tooltip_finder.dart';

import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/input_test_app.dart';
import '../../support/memory_settings_repository.dart';
import '../../support/system_media_playback_fixture.dart';
import '../../support/video_card_fake_engine.dart';

void main() {
  for (final orientation in [
    AppOrientationPreference.portrait,
    AppOrientationPreference.landscape,
  ]) {
    for (final display in [const Size(400, 800), const Size(800, 1200)]) {
      for (final dimensions in [
        const VideoDimensions(1920, 1080),
        const VideoDimensions(1080, 1920),
      ]) {
        testWidgets(
          'browse $orientation yields to video ${dimensions.width}x${dimensions.height} on $display',
          (tester) async {
            tester.view.devicePixelRatio = 1;
            tester.view.display.size = display;
            tester.view.physicalSize =
                orientation == AppOrientationPreference.landscape
                ? const Size(800, 400)
                : const Size(400, 800);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.display.resetSize);
            addTearDown(tester.view.resetPhysicalSize);
            final applied = <Object?>[];
            tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              SystemChannels.platform,
              (call) async {
                if (call.method == 'SystemChrome.setPreferredOrientations') {
                  applied.add(call.arguments);
                }
                return null;
              },
            );
            addTearDown(
              () => tester.binding.defaultBinaryMessenger
                  .setMockMethodCallHandler(SystemChannels.platform, null),
            );
            final events = StreamController<FullScreenOrientation>.broadcast(
              sync: true,
            );
            addTearDown(events.close);
            final window = _MobileWindow(events.stream);
            await window.updateDisplaySize(display, orientation: orientation);
            final engine = _Engine();
            final session = PlaybackSession(
              engine: engine,
              repository: SystemMediaFixtureRepository(),
              progress: SystemMediaFixtureProgress(),
              accountScope: () => 'guest',
            );
            addTearDown(session.close);
            final settings = AppSettings(orientation: orientation);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  playbackSessionProvider.overrideWithValue(session),
                  settingsRepositoryProvider.overrideWithValue(
                    MemorySettingsRepository()..value = settings,
                  ),
                ],
                child: InputTestApp(
                  builder: AppNoticeHost.builder,
                  home: Scaffold(
                    body: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: PlaybackPanel(
                        detail: systemMediaVideo('方向测试'),
                        part: systemMediaPart,
                        settings: settings,
                        onToggleComments: () {},
                        window: window,
                      ),
                    ),
                  ),
                ),
              ),
            );
            await _frames(tester);
            engine.publish(
              engine.snapshot.copyWith(
                videoDimensions: dimensions,
                position: const Duration(seconds: 7),
              ),
            );
            await _frames(tester);
            expect(events.hasListener, isFalse);
            final opens = engine.opens;
            expect(opens, 1);
            final locked = applied.single;
            events.add(FullScreenOrientation.landscape);
            tester.view.display.size = Size(display.height, display.width);
            tester.view.physicalSize = const Size(800, 400);
            await _frames(tester);
            expect(window.isFullScreen, isFalse);
            tester.view.display.size = display;
            tester.view.physicalSize =
                orientation == AppOrientationPreference.landscape
                ? const Size(800, 400)
                : const Size(400, 800);
            await _frames(tester);
            await _showControls(tester);
            await tester.tap(findMaterialTooltip('全屏（F）'));
            await _frames(tester);
            expect(window.isFullScreen, isTrue);
            final videoDirection = dimensions.width > dimensions.height
                ? [
                    'DeviceOrientation.landscapeLeft',
                    'DeviceOrientation.landscapeRight',
                  ]
                : ['DeviceOrientation.portraitUp'];
            expect(applied.last, videoDirection);
            events.add(FullScreenOrientation.portrait);
            await _frames(tester);
            expect(
              window.isFullScreen,
              isTrue,
              reason: 'The first physical posture only establishes a baseline',
            );
            await window.updateDisplaySize(
              display,
              orientation: orientation == AppOrientationPreference.portrait
                  ? AppOrientationPreference.landscape
                  : AppOrientationPreference.portrait,
            );
            expect(applied.last, videoDirection);
            await window.updateDisplaySize(display, orientation: orientation);
            expect(
              find.byKey(const ValueKey('fake-card-video-surface')),
              findsOneWidget,
            );
            // Late dimensions (e.g. the next part) also update the same fullscreen.
            engine.publish(
              engine.snapshot.copyWith(
                videoDimensions: VideoDimensions(
                  dimensions.height,
                  dimensions.width,
                ),
              ),
            );
            await _frames(tester);
            expect(window.isFullScreen, isTrue);
            expect(
              applied.last,
              dimensions.width > dimensions.height
                  ? ['DeviceOrientation.portraitUp']
                  : [
                      'DeviceOrientation.landscapeLeft',
                      'DeviceOrientation.landscapeRight',
                    ],
            );
            await _showControls(tester);
            await tester.tap(findMaterialTooltip('退出全屏（Esc）'));
            await _frames(tester);
            expect(window.isFullScreen, isFalse);
            expect(applied.last, locked);
            expect(engine.opens, opens);
            expect(engine.snapshot.position, const Duration(seconds: 7));
            expect(
              find.byKey(const ValueKey('fake-card-video-surface')),
              findsOneWidget,
            );
            await tester.pumpWidget(const SizedBox());
            await _frames(tester);
            await window.clearDisplayOrientationPolicy();
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _showControls(WidgetTester tester) async {
  if (find.byKey(const ValueKey('player-controls')).evaluate().isNotEmpty) {
    return;
  }
  final surface = find.byKey(const ValueKey('player-surface-tap-target'));
  await tester.tapAt(tester.getTopLeft(surface) + const Offset(130, 54));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 216));
}

class _MobileWindow extends WindowService {
  _MobileWindow(this.deviceOrientations);
  @override
  final Stream<FullScreenOrientation?> deviceOrientations;
  @override
  bool get hasDesktopWindow => false;
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
