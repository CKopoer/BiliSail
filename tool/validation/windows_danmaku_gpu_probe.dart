import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:bili_danmaku/bili_danmaku.dart';
import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

/// Local video plus synthetic danmaku. The candidate renderer is probe-only.
/// BILI_GPU_RENDERER=production/limited/atlas; BILI_GPU_MODE=scroll/fixed/mixed;
/// BILI_GPU_ARRIVALS=2/20; BILI_GPU_OPACITY=0.8/1.0.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1100, 700));
  final env = Platform.environment;
  final media = env['BILI_GPU_MEDIA'];
  final label = env['BILI_GPU_LABEL'];
  if (media == null || label == null) {
    throw StateError('BILI_GPU_MEDIA and BILI_GPU_LABEL are required');
  }
  final seconds = int.parse(env['BILI_GPU_SECONDS'] ?? '30');
  final renderer = env['BILI_GPU_RENDERER'] ?? 'production';
  final mode = env['BILI_GPU_MODE'] ?? 'scroll';
  final arrivals = int.parse(env['BILI_GPU_ARRIVALS'] ?? '20');
  final opacity = double.parse(env['BILI_GPU_OPACITY'] ?? '0.8');
  if (!['production', 'limited', 'atlas'].contains(renderer) ||
      !['scroll', 'fixed', 'mixed'].contains(mode) ||
      arrivals < 1 ||
      arrivals > 20 ||
      opacity < 0 ||
      opacity > 1) {
    throw StateError('Invalid probe scenario');
  }
  final file = File('build/validation/windows-gpu-playback-$label.jsonl');
  await file.parent.create(recursive: true);
  if (await file.exists()) throw StateError('Label already has playback data');
  final clock = Stopwatch()..start();
  final engine = MediaKitEngine();
  final danmaku = DanmakuController(monotonicNow: () => clock.elapsed)
    ..configure(area: 0.75, speed: 1);
  final enabled = ValueNotifier(false);
  final atlas = _AtlasProbeCache();
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
                  valueListenable: enabled,
                  builder: (context, active, _) => active
                      ? Opacity(
                          opacity: opacity,
                          child: switch (renderer) {
                            'production' => DanmakuOverlay(
                              controller: danmaku,
                              bottomInset: 48,
                            ),
                            'atlas' => _AtlasOverlay(
                              controller: danmaku,
                              cache: atlas,
                            ),
                            _ => _LimitedOverlay(controller: danmaku),
                          },
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  // Hidden windows can suppress presentation and invalidate the comparison.
  await windowManager.show();
  Timer? windowRefresh;
  void refreshWindow() {
    final at = engine.currentSnapshot.position.inMicroseconds;
    final from = ((at - 9000000) * arrivals ~/ 1000000).clamp(0, 1000000);
    final until = (at + 10000000) * arrivals ~/ 1000000;
    danmaku.replaceEvents([
      for (var index = from; index < until; index++)
        DanmakuEvent(
          id: '$index',
          at: Duration(microseconds: index * 1000000 ~/ arrivals),
          text: '${_texts[index % _texts.length]} $index',
          fontSize: 25,
          mode: mode == 'scroll' || (mode == 'mixed' && index % 10 < 8)
              ? DanmakuMode.scroll
              : (index.isEven ? DanmakuMode.top : DanmakuMode.bottom),
        ),
    ], sorted: true);
  }

  Future<void> stage(String name, int count) async {
    debugPrint('GPU_STAGE $name ${DateTime.now().toUtc().toIso8601String()}');
    timings.clear();
    for (var index = 0; index < count; index++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final snapshot = engine.currentSnapshot;
      final diagnostic = engine.inspectDiagnostics();
      final native = await engine.inspectNativePlaybackTiming();
      final raster = danmaku.rasterStatistics;
      final atlasMetrics = {
        'atlasBuilds': atlas.builds,
        'atlasBytes': atlas.bytes,
        'atlasPeakBytes': atlas.peakBytes,
        'atlasDrawItems': atlas.drawItems,
      };
      await file.writeAsString(
        '${jsonEncode({'stage': name, 'pid': pid, 'timeUtc': DateTime.now().toUtc().toIso8601String(), 'renderer': renderer, 'mode': mode, 'arrivalsPerSecond': arrivals, 'opacity': opacity, 'positionMs': snapshot.position.inMilliseconds, 'phase': snapshot.phase.name, 'buffering': snapshot.isBuffering, 'decodedWidth': diagnostic.videoWidth, 'decodedHeight': diagnostic.videoHeight, 'outputWidth': diagnostic.outputWidth, 'outputHeight': diagnostic.outputHeight, 'hwdec': await engine.inspectHardwareDecoder(), 'avsyncSeconds': native.avsyncSeconds, 'frameDrops': native.frameDrops, 'decoderDrops': native.decoderDrops, 'dartFrames': timings.length, 'uiUs': timings.map((f) => f.buildDuration.inMicroseconds).toList(), 'rasterUs': timings.map((f) => f.rasterDuration.inMicroseconds).toList(), 'visible': danmaku.visibleCount, 'dropped': danmaku.dropped, 'layoutBuilds': danmaku.textLayoutBuildCount, 'rasterBytes': danmaku.textRasterBytes, 'imagePaints': raster.imagePaints, 'cacheHits': raster.cacheHits, 'rasterBuilds': raster.rasterBuilds, 'directPaints': raster.directPaints, ...atlasMetrics})}\n',
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
    await stage('video', 10);
    await engine.seek(Duration.zero);
    refreshWindow();
    windowRefresh = Timer.periodic(
      const Duration(seconds: 1),
      (_) => refreshWindow(),
    );
    enabled.value = true;
    await stage('danmaku-warmup', 8);
    if (renderer == 'atlas') {
      final placements = danmaku.frame();
      final ratio = WidgetsBinding
          .instance
          .platformDispatcher
          .views
          .first
          .devicePixelRatio;
      final pixels = <Uint8List>[];
      for (final useAtlas in [false, true]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..scale(ratio);
        const bounds = Rect.fromLTWH(0, 0, 960, 540);
        canvas.clipRect(bounds);
        canvas.saveLayer(
          bounds,
          Paint()..color = Color.fromRGBO(255, 255, 255, opacity),
        );
        if (useAtlas) {
          atlas.paint(canvas, danmaku, placements, ratio);
        } else {
          for (final item in placements) {
            danmaku.paintText(
              item.event,
              canvas,
              Offset(item.x, item.y),
              pixelRatio: ratio,
            );
          }
        }
        canvas.restore();
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          (960 * ratio).ceil(),
          (540 * ratio).ceil(),
        );
        final data = await image.toByteData();
        if (data == null) throw StateError('Missing atlas comparison pixels');
        pixels.add(data.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      }
      var differingChannels = 0, maxDifference = 0;
      for (var i = 0; i < pixels[0].length; i++) {
        final difference = (pixels[0][i] - pixels[1][i]).abs();
        if (difference > 0) differingChannels++;
        maxDifference = math.max(maxDifference, difference);
      }
      debugPrint(
        'ATLAS_PIXELS ${jsonEncode({'dpr': ratio, 'differingChannels': differingChannels, 'maxDifference': maxDifference})}',
      );
    }
    await stage('danmaku', seconds);
    windowRefresh.cancel();
    await engine.pause();
    enabled.value = false;
    await stage('paused', 3);
  } finally {
    windowRefresh?.cancel();
    await subscription.cancel();
    SchedulerBinding.instance.removeTimingsCallback(recordTimings);
    enabled.dispose();
    atlas.dispose();
    danmaku.dispose();
    await engine.dispose();
  }
  exit(0);
}

/// Candidate only: preserves item order and high-refresh ticks. Its additional
/// 16 MiB atlas is measured separately from the production 32 MiB image cache.
final class _AtlasProbeCache {
  ui.Image? _image;
  List<DanmakuEvent> _events = const [];
  double _ratio = 0;
  Float32List _rects = Float32List(0), _transforms = Float32List(0);
  final _paint = Paint()..filterQuality = FilterQuality.low;
  int builds = 0, bytes = 0, peakBytes = 0, drawItems = 0;

  void paint(
    Canvas canvas,
    DanmakuController controller,
    List<DanmakuPlacement> placements,
    double ratio,
  ) {
    if (_ratio != ratio ||
        _events.length != placements.length ||
        !Iterable<int>.generate(placements.length)
            .every((i) => identical(_events[i], placements[i].event))) {
      _rebuild(controller, placements, ratio);
    }
    final image = _image;
    if (image == null) {
      for (final item in placements) {
        controller.paintText(
          item.event,
          canvas,
          Offset(item.x, item.y),
          pixelRatio: ratio,
        );
      }
      return;
    }
    for (var i = 0; i < placements.length; i++) {
      _transforms[i * 4] = 1 / ratio;
      _transforms[i * 4 + 2] = placements[i].x - 6;
      _transforms[i * 4 + 3] = placements[i].y - 6;
    }
    canvas.drawRawAtlas(image, _transforms, _rects, null, null, null, _paint);
    drawItems += placements.length;
  }

  void _rebuild(
    DanmakuController controller,
    List<DanmakuPlacement> placements,
    double ratio,
  ) {
    _image?.dispose();
    _image = null;
    bytes = 0;
    _ratio = ratio;
    _events = placements.map((p) => p.event).toList(growable: false);
    if (placements.isEmpty) return;
    final dimensions = <(int, int)>[];
    var area = 0;
    for (final item in placements) {
      final layout = TextPainter(
        text: TextSpan(
          text: item.event.text,
          style: TextStyle(
            fontSize: item.event.fontSize,
            fontWeight: FontWeight.normal,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final width = ((layout.width + 12) * ratio).ceil();
      final height = ((layout.height + 12) * ratio).ceil();
      layout.dispose();
      dimensions.add((width, height));
      area += (width + 2) * (height + 2);
    }
    var atlasWidth = 512;
    while (atlasWidth < math.sqrt(area) && atlasWidth < 2048) {
      atlasWidth *= 2;
    }
    final slots = <Rect>[];
    var x = 0, y = 0, rowHeight = 0;
    for (final (width, height) in dimensions) {
      if (width + 2 > atlasWidth) return;
      if (x + width + 2 > atlasWidth) {
        x = 0;
        y += rowHeight;
        rowHeight = 0;
      }
      slots.add(
        Rect.fromLTWH(x + 1.0, y + 1.0, width.toDouble(), height.toDouble()),
      );
      x += width + 2;
      rowHeight = math.max(rowHeight, height + 2);
    }
    final atlasHeight = y + rowHeight;
    final cost = atlasWidth * atlasHeight * 4;
    if (atlasHeight > 4096 || cost > 16 * 1024 * 1024) return;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _rects = Float32List(placements.length * 4);
    _transforms = Float32List(placements.length * 4);
    for (var i = 0; i < placements.length; i++) {
      final slot = slots[i];
      canvas.save();
      canvas.translate(slot.left, slot.top);
      canvas.scale(ratio);
      controller.paintText(
        placements[i].event,
        canvas,
        const Offset(6, 6),
        pixelRatio: ratio,
      );
      canvas.restore();
      _rects[i * 4] = slot.left;
      _rects[i * 4 + 1] = slot.top;
      _rects[i * 4 + 2] = slot.right;
      _rects[i * 4 + 3] = slot.bottom;
    }
    final picture = recorder.endRecording();
    _image = picture.toImageSync(atlasWidth, atlasHeight);
    picture.dispose();
    bytes = cost;
    peakBytes = math.max(peakBytes, bytes);
    builds++;
  }

  void dispose() {
    _image?.dispose();
    _image = null;
    _events = const [];
    bytes = 0;
  }
}

final class _AtlasOverlay extends StatefulWidget {
  const _AtlasOverlay({required this.controller, required this.cache});
  final DanmakuController controller;
  final _AtlasProbeCache cache;
  @override
  State<_AtlasOverlay> createState() => _AtlasOverlayState();
}

final class _AtlasOverlayState extends State<_AtlasOverlay>
    with SingleTickerProviderStateMixin {
  final _repaint = ValueNotifier(0);
  late final Ticker _ticker;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _repaint.value++)..start();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.setViewport(
            width: bounds.maxWidth,
            height: bounds.maxHeight,
            bottomInset: 48,
          );
        }
      });
      return RepaintBoundary(
        child: CustomPaint(
          painter: _AtlasPainter(
            widget.controller,
            widget.cache,
            _repaint,
            MediaQuery.devicePixelRatioOf(context),
          ),
          size: Size.infinite,
        ),
      );
    },
  );
  @override
  void dispose() {
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }
}

final class _AtlasPainter extends CustomPainter {
  _AtlasPainter(this.controller, this.cache, Listenable repaint, this.ratio)
    : super(repaint: repaint);
  final DanmakuController controller;
  final _AtlasProbeCache cache;
  final double ratio;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    cache.paint(canvas, controller, controller.frame(), ratio);
  }

  @override
  bool shouldRepaint(_AtlasPainter old) =>
      old.controller != controller || old.ratio != ratio;
}

const _texts = [
  '这个画面很好看',
  '弹幕与视频同播测试',
  '前方高能注意',
  '欢迎来到哔帆',
  '这段值得再看一次',
  '连续移动文字样本',
];

/// Test 60Hz presentation without changing media/animation clocks or images.
/// Fixed text only invalidates paint when content or positions actually change.
final class _LimitedOverlay extends StatefulWidget {
  const _LimitedOverlay({required this.controller});
  final DanmakuController controller;
  @override
  State<_LimitedOverlay> createState() => _LimitedOverlayState();
}

final class _LimitedOverlayState extends State<_LimitedOverlay> {
  final _repaint = ValueNotifier(0);
  List<DanmakuPlacement> _placements = const [];
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(microseconds: 16667), (_) {
      final next = widget.controller.frame();
      final unchanged =
          next.length == _placements.length &&
          Iterable<int>.generate(next.length).every(
            (i) =>
                identical(next[i].event, _placements[i].event) &&
                next[i].x == _placements[i].x &&
                next[i].y == _placements[i].y,
          );
      _placements = next;
      if (!unchanged) _repaint.value++;
    });
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          widget.controller.setViewport(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            bottomInset: 48,
          );
        }
      });
      return RepaintBoundary(
        child: CustomPaint(
          painter: _ProbePainter(
            widget.controller,
            () => _placements,
            _repaint,
            MediaQuery.devicePixelRatioOf(context),
          ),
          size: Size.infinite,
        ),
      );
    },
  );

  @override
  void dispose() {
    _timer?.cancel();
    _repaint.dispose();
    super.dispose();
  }
}

final class _ProbePainter extends CustomPainter {
  _ProbePainter(this.controller, this.placements, Listenable repaint, this.dpr)
    : super(repaint: repaint);
  final DanmakuController controller;
  final List<DanmakuPlacement> Function() placements;
  final double dpr;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final item in placements()) {
      controller.paintText(
        item.event,
        canvas,
        Offset(item.x, item.y),
        pixelRatio: dpr,
      );
    }
  }

  @override
  bool shouldRepaint(_ProbePainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) || dpr != oldDelegate.dpr;
}
