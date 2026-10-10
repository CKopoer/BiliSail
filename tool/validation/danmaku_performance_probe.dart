import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:flutter/material.dart';

// Use a native Profile build. This probe uses synthetic text, no account/video.
Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final host = ValueNotifier<Widget>(const SizedBox.expand());
  runApp(
    MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.black,
        body: ValueListenableBuilder<Widget>(
          valueListenable: host,
          builder: (_, child, _) => child,
        ),
      ),
    ),
  );
  await Future<void>.delayed(const Duration(seconds: 1));
  final results = <Map<String, Object?>>[];
  for (final effect in DanmakuTextEffect.values) {
    final style = DanmakuTextStyle(effect: effect);
    final refreshUs = <int>[];
    final burstUs = <int>[];
    final vod = DanmakuController(monotonicNow: () => Duration.zero);
    vod.configure(area: 1, speed: 1, textStyle: style);
    vod.setViewport(width: 1280, height: 720);
    final events = _vodEvents(Duration.zero);
    for (var sample = 0; sample < 35; sample++) {
      final watch = Stopwatch()..start();
      vod.replaceEvents(events);
      final elapsed = watch.elapsedMicroseconds;
      if (sample >= 5) refreshUs.add(elapsed);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    vod.dispose();
    final live = LiveDanmakuController(monotonicNow: () => Duration.zero);
    live.configure(area: 1, speed: 1, maxPerSecond: 0, textStyle: style);
    live.setViewport(width: 1280, height: 720);
    for (var sample = 0; sample < 35; sample++) {
      live.clear();
      live.add(_liveEvents(sample));
      final watch = Stopwatch()..start();
      live.frame();
      final elapsed = watch.elapsedMicroseconds;
      if (sample >= 5) burstUs.add(elapsed);
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    live.dispose();
    results.add({
      'effect': effect.name,
      'vodRefresh': _stats(refreshUs),
      'liveBurst': _stats(burstUs),
    });

    for (final isLive in [false, true]) {
      final clock = Stopwatch()..start();
      final frames = <ui.FrameTiming>[];
      final sceneVod = DanmakuController(monotonicNow: () => clock.elapsed);
      final sceneLive = LiveDanmakuController(
        monotonicNow: () => clock.elapsed,
      );
      var rasterPeakBytes = 0;
      var visiblePeak = 0;
      void collect(List<ui.FrameTiming> batch) {
        frames.addAll(batch);
        final bytes = isLive
            ? sceneLive.textRasterBytes
            : sceneVod.textRasterBytes;
        final count = isLive ? sceneLive.visibleCount : sceneVod.visibleCount;
        if (bytes > rasterPeakBytes) rasterPeakBytes = bytes;
        if (count > visiblePeak) visiblePeak = count;
      }

      sceneVod.configure(area: 1, speed: 1, textStyle: style);
      sceneLive.configure(area: 1, speed: 1, maxPerSecond: 0, textStyle: style);
      host.value = isLive
          ? LiveDanmakuOverlay(controller: sceneLive, bottomInset: 0)
          : DanmakuOverlay(controller: sceneVod);
      var batch = 0;
      final timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
        if (isLive) {
          sceneLive.add(_liveEvents(batch++));
        } else {
          sceneVod.sync(
            confirmedPosition: clock.elapsed,
            playing: true,
            buffering: false,
            seeking: false,
            rate: 1,
          );
          sceneVod.replaceEvents(_vodEvents(clock.elapsed));
        }
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      binding.addTimingsCallback(collect);
      await Future<void>.delayed(const Duration(seconds: 6));
      binding.removeTimingsCallback(collect);
      timer.cancel();
      results.add({
        'effect': effect.name,
        'scene': isLive ? 'live' : 'vod',
        'frames': frames.length,
        'ui': _stats(frames.map((f) => f.buildDuration.inMicroseconds)),
        'raster': _stats(frames.map((f) => f.rasterDuration.inMicroseconds)),
        'over16ms': frames
            .where(
              (f) =>
                  f.buildDuration.inMicroseconds > 16667 ||
                  f.rasterDuration.inMicroseconds > 16667,
            )
            .length,
        'visible': isLive ? sceneLive.visibleCount : sceneVod.visibleCount,
        'visiblePeak': visiblePeak,
        'rasterPeakBytes': rasterPeakBytes,
        'layoutBuilds': isLive
            ? sceneLive.textLayoutBuildCount
            : sceneVod.textLayoutBuildCount,
        'dropped': isLive ? sceneLive.dropped : sceneVod.dropped,
      });
      host.value = const SizedBox.expand();
      await binding.endOfFrame;
      sceneVod.dispose();
      sceneLive.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  final view = binding.platformDispatcher.views.first;
  final output = File(
    const String.fromEnvironment(
      'DANMAKU_PROBE_OUTPUT',
      defaultValue: 'artifacts/danmaku-performance/results.json',
    ),
  );
  await output.parent.create(recursive: true);
  await output.writeAsString(
    const JsonEncoder.withIndent('  ').convert({
      'profile': const bool.fromEnvironment('dart.vm.profile'),
      'physicalSize': [view.physicalSize.width, view.physicalSize.height],
      'dpr': view.devicePixelRatio,
      'eventsPerBatch': 500,
      'results': results,
    }),
  );
  exit(0);
}

String _text(int i) =>
    '高密度弹幕测试 $i 你好世界 Flutter performance '
    '${i % 3 == 0 ? '较长的多语言文本 😀' : '普通文本'}';

List<DanmakuEvent> _vodEvents(Duration at) => [
  for (
    var i = (at.inMilliseconds ~/ 30 - 125).clamp(0, 1000000);
    i < (at.inMilliseconds ~/ 30 - 125).clamp(0, 1000000) + 500;
    i++
  )
    DanmakuEvent(
      id: '$i',
      text: _text(i),
      at: Duration(milliseconds: i * 30),
      mode: DanmakuMode.values[i % 3],
      fontSize: i % 4 == 0 ? 36 : 24,
    ),
];

List<LiveDanmakuEvent> _liveEvents(int batch) => [
  for (var i = 0; i < 500; i++)
    LiveDanmakuEvent(
      id: '$batch-$i',
      text: _text(batch * 500 + i),
      mode: DanmakuMode.values[i % 3],
      fontSize: i % 4 == 0 ? 36 : 24,
    ),
];

Map<String, Object> _stats(Iterable<int> values) {
  final sorted = values.toList()..sort();
  if (sorted.isEmpty) return {'count': 0};
  return {
    'count': sorted.length,
    'meanMs': sorted.reduce((a, b) => a + b) / sorted.length / 1000,
    'p95Ms': sorted[((sorted.length - 1) * .95).ceil()] / 1000,
    'maxMs': sorted.last / 1000,
  };
}
