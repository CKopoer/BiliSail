import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../test/support/input_test_app.dart';
import '../../test/support/system_media_playback_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializePlayerBackend();
  final window = WindowService();
  await window.initialize();
  final session = PlaybackSession(
    engine: MediaKitEngine(),
    repository: SystemMediaFixtureRepository(
      directory: Platform.environment['BILI_TEST_MEDIA_DIR'],
    ),
    progress: SystemMediaFixtureProgress(),
    accountScope: () => 'guest',
  );
  AppLifecycleListener(
    onExitRequested: () async {
      await session.close();
      return AppExitResponse.exit;
    },
  );
  runApp(
    ProviderScope(
      overrides: [playbackSessionProvider.overrideWithValue(session)],
      child: InputTestApp(
        theme: BiliTheme.dark(),
        home: Scaffold(
          body: Center(
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: PlaybackPanel(
                detail: systemMediaVideo('哔帆 · 迷你播放器'),
                part: systemMediaPart,
                settings: AppSettings(
                  autoPlay: true,
                  defaultVolume: 0,
                  resumePlayback: false,
                  danmakuEnabled: false,
                  playbackMode: PlaybackMode.singleLoop,
                ),
                window: window,
                onToggleComments: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  Timer(const Duration(seconds: 3), () {
    window.onMiniPlayerRequested?.call();
  });
}
