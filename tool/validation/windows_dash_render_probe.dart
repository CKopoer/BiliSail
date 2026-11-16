import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _probe();
    exit(0);
  } on Object catch (error, stack) {
    debugPrint('WINDOWS_DASH_RENDER_PROBE_FAILED $error\n$stack');
    exit(1);
  }
}

Future<void> _probe() async {
  final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
  if (directory == null) {
    throw StateError('BILI_TEST_MEDIA_DIR is required');
  }
  final engine = MediaKitEngine();
  final extent = ValueNotifier(const Size(640, 360));
  final full = ValueNotifier(false);
  final rows = <Map<String, Object?>>[];
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1200, 800));
  runApp(
    MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) => ValueListenableBuilder<Size>(
            valueListenable: extent,
            builder: (context, size, _) => ValueListenableBuilder<bool>(
              valueListenable: full,
              builder: (context, isFull, _) => SizedBox(
                width: isFull ? constraints.maxWidth : size.width,
                height: isFull ? constraints.maxHeight : size.height,
                child: VideoSurface(engine: engine),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Future<void> stage(String name, int count) async {
    for (var i = 0; i < count; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final snapshot = engine.currentSnapshot;
      final dimensions = engine.inspectDiagnostics();
      final native = await engine.inspectNativePlaybackTiming();
      rows.add({
        'stage': name,
        'positionMs': snapshot.position.inMilliseconds,
        'phase': snapshot.phase.name,
        'rate': snapshot.rate,
        'buffering': snapshot.isBuffering,
        'avsyncMs': native.avsyncSeconds == null
            ? null
            : (native.avsyncSeconds! * 1000).round(),
        'frameDrops': native.frameDrops,
        'decoderDrops': native.decoderDrops,
        'audioDecoded': dimensions.hasDecodedAudio,
        'videoDecoded': dimensions.hasDecodedVideo,
        'outputWidth': dimensions.outputWidth,
        'outputHeight': dimensions.outputHeight,
      });
    }
    debugPrint('WINDOWS_DASH_STAGE_END $name samples=$count');
  }

  try {
    await Future<void>.delayed(const Duration(seconds: 1));
    await engine.open(
      DashPairSource(
        video: MediaTrack(
          uri: File('$directory/video.mp4').absolute.uri,
          requestPolicy: MediaRequestPolicy(),
        ),
        audio: MediaTrack(
          uri: File('$directory/audio.m4a').absolute.uri,
          requestPolicy: MediaRequestPolicy(),
        ),
      ),
      const OpenOptions(play: true, volume: 0),
    );
    await stage('small', 12);
    await engine.setRate(3);
    await stage('fast', 4);
    await engine.setRate(1);
    await stage('afterFast', 6);
    await engine.pause();
    await stage('paused', 2);
    await engine.seek(const Duration(seconds: 12));
    await engine.play();
    await stage('afterSeek', 8);
    await windowManager.setFullScreen(true);
    full.value = true;
    await stage('fullscreen', 6);
    await windowManager.setFullScreen(false);
    full.value = false;
    await stage('restored', 6);
    final report = File('build/validation/windows-dash-render.json');
    await report.parent.create(recursive: true);
    await report.writeAsString(
      jsonEncode({
        'hardwareDecoder': await engine.inspectHardwareDecoder(),
        'samples': rows,
      }),
    );
    debugPrint('WINDOWS_DASH_RENDER_REPORT ${report.path}');
  } finally {
    await engine.dispose();
    extent.dispose();
    full.dispose();
  }
}
