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
    debugPrint('WINDOWS_RENDER_PROBE_FAILED $error\n$stack');
    exit(1);
  }
}

Future<void> _probe() async {
  final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
  final label = Platform.environment['BILI_RENDER_LABEL'];
  if (directory == null || label == null) {
    throw StateError('BILI_TEST_MEDIA_DIR and BILI_RENDER_LABEL are required');
  }
  final mainEngine = MediaKitEngine();
  final previewEngine = MediaKitEngine();
  final extent = ValueNotifier(const Size(640, 360));
  final fillWindow = ValueNotifier(false);
  final previewVisible = ValueNotifier(false);
  var currentSurfaceSize = const Size(640, 360);
  final rows = <Map<String, Object?>>[];
  final media = File('$directory/main.mp4').absolute.uri;
  final preview = File('$directory/preview.mp4').absolute.uri;
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1480, 900));
  runApp(
    MaterialApp(
      home: Scaffold(
        body: LayoutBuilder(
          builder: (context, constraints) => ValueListenableBuilder<Size>(
            valueListenable: extent,
            builder: (context, size, _) => ValueListenableBuilder<bool>(
              valueListenable: fillWindow,
              builder: (context, full, _) {
                currentSurfaceSize = full
                    ? Size(constraints.maxWidth, constraints.maxHeight)
                    : size;
                return Stack(
                  children: [
                    SizedBox(
                      width: full ? constraints.maxWidth : size.width,
                      height: full ? constraints.maxHeight : size.height,
                      child: VideoSurface(engine: mainEngine),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: previewVisible,
                      builder: (context, visible, _) => visible
                          ? Positioned(
                              right: 10,
                              bottom: 10,
                              child: SizedBox(
                                width: 320,
                                height: 180,
                                child: VideoSurface(engine: previewEngine),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    ),
  );
  Future<void> stage(String name, int samples) async {
    debugPrint(
      'WINDOWS_RENDER_STAGE_START $name atMs=${DateTime.now().millisecondsSinceEpoch}',
    );
    for (var i = 0; i < samples; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final snapshot = mainEngine.currentSnapshot;
      final dimensions = mainEngine.inspectDiagnostics();
      final native = await mainEngine.inspectNativePlaybackTiming();
      rows.add({
        'stage': name,
        'timeUtc': DateTime.now().toUtc().toIso8601String(),
        'positionMs': snapshot.position.inMilliseconds,
        'phase': snapshot.phase.name,
        'buffering': snapshot.isBuffering,
        'seeking': snapshot.isSeeking,
        'rate': snapshot.rate,
        'avsyncMs': native.avsyncSeconds == null
            ? null
            : (native.avsyncSeconds! * 1000).round(),
        'frameDrops': native.frameDrops,
        'decoderDrops': native.decoderDrops,
        'decodedWidth': dimensions.videoWidth,
        'decodedHeight': dimensions.videoHeight,
        'outputReady': dimensions.hasVideoOutput,
        'outputWidth': dimensions.outputWidth,
        'outputHeight': dimensions.outputHeight,
        'audioDecoded': dimensions.hasDecodedAudio,
        'viewportWidth': currentSurfaceSize.width,
        'viewportHeight': currentSurfaceSize.height,
        'previewVisible': previewVisible.value,
      });
    }
    debugPrint(
      'WINDOWS_RENDER_STAGE_END $name samples=$samples atMs=${DateTime.now().millisecondsSinceEpoch}',
    );
  }

  try {
    await Future<void>.delayed(const Duration(seconds: 1));
    await mainEngine.open(
      ProgressiveSource(
        MediaTrack(uri: media, requestPolicy: MediaRequestPolicy()),
      ),
      const OpenOptions(play: true, volume: 0),
    );
    await stage('warmup', 4);
    await stage('small', 14);
    await previewEngine.open(
      DashVideoSource(
        MediaTrack(uri: preview, requestPolicy: MediaRequestPolicy()),
      ),
      const OpenOptions(
        play: true,
        volume: 0,
        maxBufferAhead: Duration(seconds: 5),
      ),
    );
    previewVisible.value = true;
    await stage('preview', 12);
    final previewOutput = previewEngine.inspectDiagnostics().hasVideoOutput;
    final previewDecodedAudio = previewEngine
        .inspectDiagnostics()
        .hasDecodedAudio;
    previewVisible.value = false;
    await previewEngine.dispose();
    await mainEngine.setRate(3);
    await stage('fast', 4);
    await mainEngine.setRate(1);
    await stage('afterFast', 6);
    await mainEngine.pause();
    await stage('paused', 2);
    await mainEngine.seek(const Duration(seconds: 12));
    await mainEngine.play();
    await stage('afterSeek', 8);
    extent.value = const Size(1280, 720);
    await stage('expanded', 8);
    await windowManager.setFullScreen(true);
    fillWindow.value = true;
    await stage('fullscreen', 6);
    await windowManager.setFullScreen(false);
    fillWindow.value = false;
    extent.value = const Size(640, 360);
    await stage('restored', 6);
    final report = File('build/validation/windows-video-render-$label.json');
    await report.parent.create(recursive: true);
    await report.writeAsString(
      jsonEncode({
        'hardwareDecoder': await mainEngine.inspectHardwareDecoder(),
        'previewOutput': previewOutput,
        'previewDecodedAudio': previewDecodedAudio,
        'samples': rows,
      }),
    );
    debugPrint('WINDOWS_RENDER_REPORT ${report.path}');
  } finally {
    await previewEngine.dispose();
    await mainEngine.dispose();
    previewVisible.dispose();
    fillWindow.dispose();
    extent.dispose();
  }
}
