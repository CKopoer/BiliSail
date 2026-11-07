import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/app/workspace_playback_window.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/platform/picture_in_picture_service.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/shortcut_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test/support/input_test_app.dart';
import '../test/support/system_media_playback_fixture.dart';
import 'support/multi_view_binding.dart';
import 'support/native_playback_window.dart';

void main() {
  final binding =
      MultiViewIntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final detached in Platform.isWindows ? [false, true] : [false]) {
    testWidgets(
      'native mini player retains DASH playback and restores window detached=$detached',
      (tester) async {
        initializePlayerBackend();
        final directory = Platform.isAndroid
            ? '/sdcard/Android/data/dev.bilisail.bilisail.test/files/mini-player'
            : Platform.environment['BILI_TEST_MEDIA_DIR']!;
        final engine = MediaKitEngine();
        final session = PlaybackSession(
          engine: engine,
          repository: SystemMediaFixtureRepository(directory: directory),
          progress: SystemMediaFixtureProgress(),
          accountScope: () => 'guest',
        );
        final rootWindow = WindowService();
        final controller = DesktopPlaybackWindowController();
        WindowService window = rootWindow;
        DetachedPlaybackWindow? nativeWindow;
        final settings = AppSettings(
          autoPlay: true,
          resumePlayback: false,
          defaultVolume: 0,
          danmakuEnabled: false,
        );
        Widget player() => Builder(
          builder: (context) {
            window = WindowServiceScope.maybeOf(context) ?? rootWindow;
            return PlaybackPanel(
              detail: systemMediaVideo('哔帆 · 迷你播放器'),
              part: systemMediaPart,
              settings: settings,
              window: window,
              onToggleComments: () {},
            );
          },
        );
        try {
          if (!detached) await rootWindow.initialize();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [playbackSessionProvider.overrideWithValue(session)],
              child: detached
                  ? DesktopPlaybackWindow(
                      controller: controller,
                      windowFactory:
                          ({required title, required onCloseRequested}) {
                            nativeWindow = DetachedPlaybackWindow.create(
                              title: title,
                              onCloseRequested: onCloseRequested,
                            );
                            return nativeWindow!;
                          },
                      onCloseRequested: () {},
                      onError: (error) => throw StateError('$error'),
                      playback: Builder(
                        builder: (context) => WorkspacePlaybackWindow(
                          shortcuts: const ShortcutSettings.defaults(),
                          onBack: () {},
                          onClose: () {},
                          onActivateBrowser: () {},
                          theme: BiliTheme.dark(),
                          child: player(),
                        ),
                      ),
                      child: const InputTestApp(
                        home: Scaffold(body: SizedBox.expand()),
                      ),
                    )
                  : InputTestApp(
                      theme: BiliTheme.dark(),
                      home: Scaffold(
                        body: Center(
                          child: AspectRatio(
                            aspectRatio: 16 / 9,
                            child: player(),
                          ),
                        ),
                      ),
                    ),
            ),
          );
          await _until(
            tester,
            () =>
                session.media != null &&
                engine.currentSnapshot.videoDimensions != null,
          );
          await session.pause();
          await session.seek(const Duration(seconds: 2));
          final generation = session.sourceGeneration;
          final native = Platform.isWindows
              ? NativePlaybackWindow(nativeWindow?.viewId ?? 0)
              : null;
          final original = native?.outerSize;
          window.onMiniPlayerRequested!();
          await _until(
            tester,
            () =>
                find.byKey(const ValueKey('mini-player')).evaluate().isNotEmpty,
          );
          if (Platform.isWindows) {
            await _until(tester, () => window.miniPlayer.value);
            native!.resize(320, 180);
            await tester.pump(const Duration(milliseconds: 300));
            expect(native.outerSize, const Size(320, 180));
            await window.setAlwaysOnTop(false);
            await window.setAlwaysOnTop(true);
            expect(session.sourceGeneration, generation);
            expect(session.snapshots.value.desiredPlaying, isFalse);
            await tester.tapAt(
              tester.getCenter(find.byTooltip('播放')),
              view: View.of(tester.element(find.byTooltip('播放'))),
            );
            await _until(
              tester,
              () =>
                  session.snapshots.value.position >
                  const Duration(milliseconds: 2500),
            );
            await tester.tapAt(
              tester.getCenter(find.byTooltip('还原播放页')),
              view: View.of(tester.element(find.byTooltip('还原播放页'))),
            );
            await _until(
              tester,
              () => !window.miniPlayer.value && native.outerSize == original,
            );
            expect(native.outerSize, original);
            expect(session.sourceGeneration, generation);
          } else if (Platform.isAndroid) {
            await _until(
              tester,
              () => PictureInPictureService.instance.active.value,
            );
            await session.play();
            await _until(
              tester,
              () =>
                  session.snapshots.value.position >
                  const Duration(milliseconds: 2500),
            );
            binding.reportData = {
              'miniPlayer': {
                'pip': true,
                'sourceGenerationUnchanged':
                    session.sourceGeneration == generation,
                'positionMs': session.snapshots.value.position.inMilliseconds,
              },
            };
            // The host restores the activity through its launcher. Keep observing
            // until the native callback confirms expansion and the inline surface.
            await _until(
              tester,
              () => !PictureInPictureService.instance.active.value,
            );
            await _until(
              tester,
              () =>
                  find.byKey(const ValueKey('mini-player')).evaluate().isEmpty,
            );
            expect(session.sourceGeneration, generation);
          }
          expect(session.error, isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          await session.close();
          await controller.close();
          await rootWindow.dispose();
        }
      },
    );
  }
}

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 40));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  expect(condition(), isTrue);
}
