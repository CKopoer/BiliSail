import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/dependencies.dart';
import 'package:bilisail/core/platform/detached_playback_window.dart';
import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';

/// AOT exit probe: empty credentials, in-memory database and local DASH only.
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  final directory = Platform.environment['BILI_TEST_MEDIA_DIR']!;
  final output = File(Platform.environment['BILI_EXIT_PROBE_OUTPUT']!);
  void record(String stage) => output.writeAsStringSync(
    '${DateTime.now().millisecondsSinceEpoch} $stage\n',
    mode: FileMode.append,
  );
  final dependencies = await AppDependencies.create(
    credentials: _EmptyCredentials(),
    databaseOverride: AppDatabase(NativeDatabase.memory()),
  );
  final engine = dependencies.playback.acquire('exit-probe').engine;
  DetachedPlaybackWindow? window;
  AppLifecycleListener(
    onExitRequested: () async {
      record('closeRequested');
      await dependencies.close();
      if (WidgetsBinding.instance.platformDispatcher.views.length != 1 ||
          window?.isOpen == true) {
        throw StateError('Playback view survived dependency cleanup');
      }
      record('dependenciesClosed');
      return AppExitResponse.exit;
    },
  );
  runApp(
    DesktopPlaybackWindow(
      controller: dependencies.playbackWindow,
      windowFactory: ({required title, required onCloseRequested}) =>
          window = DetachedPlaybackWindow.create(
            title: title,
            onCloseRequested: onCloseRequested,
          ),
      onCloseRequested: () {},
      onError: (_) => record('windowError'),
      playback: MaterialApp(
        home: Scaffold(body: VideoSurface(engine: engine)),
      ),
      child: const MaterialApp(home: Scaffold(body: Text('Exit probe'))),
    ),
  );
  await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
  final policy = MediaRequestPolicy();
  await engine.open(
    DashPairSource(
      video: MediaTrack(
        uri: File('$directory/video.mp4').uri,
        requestPolicy: policy,
      ),
      audio: MediaTrack(
        uri: File('$directory/audio.m4a').uri,
        requestPolicy: policy,
      ),
    ),
    const OpenOptions(play: true, volume: 0),
  );
  while (engine.currentSnapshot.position <= Duration.zero ||
      WidgetsBinding.instance.platformDispatcher.views.length != 2) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  switch (Platform.environment['BILI_EXIT_PROBE_PRESENTATION']) {
    case 'minimized':
      await window!.windowService.minimizePlaybackWindow();
    case 'fullscreen':
      await window!.windowService.setFullScreen(true);
  }
  record('ready');
}

class _EmptyCredentials implements CredentialStore {
  @override
  Future<String?> read() async => null;
  @override
  Future<void> write(String value) async {}
  @override
  Future<void> delete() async {}
}
