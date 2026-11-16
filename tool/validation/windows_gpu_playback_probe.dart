import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

/// Same application backend and empty overlay before/after native output changes.
/// Runs only local fixtures and records no account or network data.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1100, 700));
  final media = Platform.environment['BILI_GPU_MEDIA'];
  final label = Platform.environment['BILI_GPU_LABEL'];
  if (media == null || label == null) {
    throw StateError('BILI_GPU_MEDIA and BILI_GPU_LABEL are required');
  }
  final seconds = int.parse(Platform.environment['BILI_GPU_SECONDS'] ?? '40');
  final engine = MediaKitEngine();
  final clock = Stopwatch()..start();
  final danmaku = DanmakuController(monotonicNow: () => clock.elapsed);
  final overlay = ValueNotifier(false);
  final timings = <FrameTiming>[];
  void recordTimings(List<FrameTiming> frames) => timings.addAll(frames);
  SchedulerBinding.instance.addTimingsCallback(recordTimings);
  final subscription = engine.snapshots.listen((snapshot) {
    danmaku.sync(
      confirmedPosition: snapshot.position,
      playing: snapshot.phase == PlaybackPhase.playing,
      buffering: snapshot.isBuffering,
      seeking: snapshot.isSeeking,
      rate: snapshot.rate,
    );
  });
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 960,
            height: 540,
            child: Stack(
              fit: StackFit.expand,
              children: [
                VideoSurface(engine: engine),
                ValueListenableBuilder<bool>(
                  valueListenable: overlay,
                  builder: (context, enabled, _) => enabled
                      ? DanmakuOverlay(controller: danmaku)
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  final file = File('build/validation/windows-gpu-playback-$label.jsonl');
  await file.parent.create(recursive: true);
  if (await file.exists()) throw StateError('Label already has playback data');
  Future<void> stage(String name, int count) async {
    debugPrint('GPU_STAGE $name ${DateTime.now().toUtc().toIso8601String()}');
    timings.clear();
    for (var index = 0; index < count; index++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final snapshot = engine.currentSnapshot;
      final diagnostic = engine.inspectDiagnostics();
      final native = await engine.inspectNativePlaybackTiming();
      await file.writeAsString(
        '${jsonEncode({'stage': name, 'pid': pid, 'timeUtc': DateTime.now().toUtc().toIso8601String(), 'positionMs': snapshot.position.inMilliseconds, 'phase': snapshot.phase.name, 'buffering': snapshot.isBuffering, 'decodedWidth': diagnostic.videoWidth, 'decodedHeight': diagnostic.videoHeight, 'outputWidth': diagnostic.outputWidth, 'outputHeight': diagnostic.outputHeight, 'audioDecoded': diagnostic.hasDecodedAudio, 'hwdec': await engine.inspectHardwareDecoder(), 'avsyncSeconds': native.avsyncSeconds, 'frameDrops': native.frameDrops, 'decoderDrops': native.decoderDrops, 'dartFrames': timings.length, 'rasterUs': timings.map((f) => f.rasterDuration.inMicroseconds).toList()})}\n',
        mode: FileMode.append,
      );
      timings.clear();
    }
  }

  try {
    await engine.open(
      ProgressiveSource(
        MediaTrack(
          uri: File(media).absolute.uri,
          requestPolicy: MediaRequestPolicy(),
        ),
      ),
      const OpenOptions(play: true, volume: 0),
    );
    await stage('video-warmup', 3);
    await stage('video', seconds);
    overlay.value = true;
    await engine.seek(Duration.zero);
    await stage('empty-warmup', 3);
    await stage('empty-danmaku', seconds);
    await engine.pause();
    overlay.value = false;
    await stage('paused', 5);
  } finally {
    await subscription.cancel();
    SchedulerBinding.instance.removeTimingsCallback(recordTimings);
    overlay.dispose();
    danmaku.dispose();
    await engine.dispose();
  }
  exit(0);
}
