import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/shortcut_coordinator.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/bili_icons.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Offline production panel, identical media interval for every overlay phase.
/// Environment: BILI_4K_LABEL, MEDIA, ARRIVALS (2/20), SECONDS, REVERSE, FULLSCREEN.
/// No account, persisted settings, network, progress reporting or product changes.
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  final env = Platform.environment;
  final label = env['BILI_4K_LABEL'] ?? '';
  final media = File(env['BILI_4K_MEDIA'] ?? '');
  final arrivals = int.parse(env['BILI_4K_ARRIVALS'] ?? '20');
  final seconds = int.parse(env['BILI_4K_SECONDS'] ?? '30');
  final fullscreen = env['BILI_4K_FULLSCREEN'] != '0';
  if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(label) ||
      !await media.exists() ||
      arrivals < 1 ||
      arrivals > 20 ||
      seconds < 10 ||
      seconds > 60) {
    throw StateError('Invalid label, media, density or duration');
  }
  final file = File('build/validation/4k60/$label.playback.jsonl');
  if (await file.exists()) throw StateError('Use a fresh label');
  await file.parent.create(recursive: true);
  Future<void> write(Map<String, Object?> row) => file.writeAsString(
    '${jsonEncode({'timeUtc': DateTime.now().toUtc().toIso8601String(), 'pid': pid, ...row})}\n',
    mode: FileMode.append,
  );
  await windowManager.ensureInitialized();
  await windowManager.setSize(const Size(1320, 820));
  final window = WindowService();
  final engine = MediaKitEngine();
  final session = PlaybackSession(
    engine: engine,
    repository: _LocalRepository(media.absolute.uri, arrivals),
    progress: _NoProgress(),
    accountScope: () => 'guest',
  );
  final input = ShortcutCoordinator();
  final rebuild = ValueNotifier(0);
  var settings = const AppSettings.defaults().copyWith(
    autoPlay: true,
    resumePlayback: false,
    continuousPlayback: false,
    defaultVolume: 0,
    danmakuEnabled: false,
  );
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> frames) => timings.addAll(frames);
  SchedulerBinding.instance.addTimingsCallback(collect);
  var errors = 0;
  FlutterError.onError = (details) {
    errors++;
    FlutterError.presentError(details);
  };
  runApp(
    ProviderScope(
      overrides: [playbackSessionProvider.overrideWithValue(session)],
      child: MaterialApp(
        theme: BiliTheme.light(),
        navigatorObservers: [input.routes],
        builder: (context, child) => AppInputHost<Object>(
          dispatcher: input,
          routes: input.routes,
          child: child ?? const SizedBox(),
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 1280,
              height: 720,
              child: ValueListenableBuilder<int>(
                valueListenable: rebuild,
                builder: (context, _, _) => PlaybackPanel(
                  detail: _detail,
                  part: _part,
                  settings: settings,
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
  await windowManager.show();

  Future<void> waitFor(bool Function() ready, String condition) async {
    final clock = Stopwatch()..start();
    while (!ready()) {
      if (clock.elapsed > const Duration(seconds: 40)) {
        throw StateError('Timed out: $condition');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  Semantics surfaceTap() {
    final widget = _find(
      (e) =>
          e.widget is Semantics &&
          (e.widget as Semantics).properties.label == '视频播放器' &&
          (e.widget as Semantics).properties.onTap != null,
    )?.widget;
    if (widget is! Semantics) throw StateError('Player tap target missing');
    return widget;
  }

  Element? controls() =>
      _find((e) => e.widget.key == const ValueKey('player-controls'));
  bool controlsVisible() {
    final element = controls();
    if (element == null) return false;
    var visible = true;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget is FadeTransition && widget.opacity.value < .999) {
        visible = false;
      }
      if (widget is IgnorePointer && widget.ignoring) visible = false;
      return true;
    });
    return visible;
  }

  MouseRegion? hoveredRegion;
  Future<void> showControls(bool visible) async {
    hoveredRegion?.onExit?.call(const PointerExitEvent());
    hoveredRegion = null;
    if (controlsVisible() != visible) surfaceTap().properties.onTap?.call();
    await waitFor(() => controlsVisible() == visible, 'controls=$visible');
    if (visible) {
      controls()?.visitAncestorElements((ancestor) {
        if (ancestor.widget case final MouseRegion region
            when region.onEnter != null) {
          hoveredRegion = region;
          return false;
        }
        return true;
      });
      if (hoveredRegion == null) {
        throw StateError('Controls hover region missing');
      }
      // Exercise the real hover retention once, without artificial per-frame input.
      hoveredRegion?.onEnter?.call(const PointerEnterEvent());
    }
  }

  Future<Map<String, Object?>> sample(String stage, Stopwatch clock) async {
    final snapshot = session.snapshots.value;
    final diagnostic = engine.inspectDiagnostics();
    final native = await engine.inspectNativePlaybackTiming();
    final hardware = await engine.inspectHardwareDecoder();
    final cache = session.danmaku.rasterStatistics;
    final surface = _find((e) => e.widget is VideoSurface);
    final box = surface?.findRenderObject();
    final size = box is RenderBox ? box.size : Size.zero;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    // Drain after async native reads, so no FrameTiming batches are lost.
    final frames = List<FrameTiming>.of(timings);
    timings.clear();
    return {
      'type': 'sample',
      'stage': stage,
      'elapsedMs': clock.elapsedMilliseconds,
      'positionMs': snapshot.position.inMilliseconds,
      'phase': snapshot.phase.name,
      'buffering': snapshot.isBuffering,
      'seeking': snapshot.isSeeking,
      'rate': snapshot.rate,
      'decoded': [diagnostic.videoWidth, diagnostic.videoHeight],
      'output': [diagnostic.outputWidth, diagnostic.outputHeight],
      'audioDecoded': diagnostic.hasDecodedAudio,
      'surface': [size.width, size.height],
      'view': [view.physicalSize.width, view.physicalSize.height],
      'dpr': view.devicePixelRatio,
      'refreshRate': view.display.refreshRate,
      'hwdec': hardware,
      'visible': session.danmaku.visibleCount,
      'pending': session.danmaku.pendingCount,
      'droppedComments': session.danmaku.dropped,
      'controlsVisible': controlsVisible(),
      'imagePaints': cache.imagePaints,
      'cacheHits': cache.cacheHits,
      'rasterBuilds': cache.rasterBuilds,
      'directPaints': cache.directPaints,
      'rasterBytes': session.danmaku.textRasterBytes,
      'dartFrames': frames.length,
      'uiUs': frames.map((f) => f.buildDuration.inMicroseconds).toList(),
      'rasterUs': frames.map((f) => f.rasterDuration.inMicroseconds).toList(),
      'totalUs': frames.map((f) => f.totalSpan.inMicroseconds).toList(),
      'vsyncUs': frames.map((f) => f.vsyncOverhead.inMicroseconds).toList(),
      'frameDrops': native.frameDrops,
      'decoderDrops': native.decoderDrops,
      'avsyncSeconds': native.avsyncSeconds,
      'errors': errors,
    };
  }

  try {
    await waitFor(
      () =>
          engine.currentSnapshot.phase == PlaybackPhase.playing &&
          engine.inspectDiagnostics().hasDecodedAudio,
      'decoded playback',
    );
    if (fullscreen) {
      await showControls(true);
      final button = _find(
        (e) =>
            e.widget is IconButton &&
            (e.widget as IconButton).icon is Icon &&
            ((e.widget as IconButton).icon as Icon).icon ==
                BiliIcons.fullscreen,
      )?.widget;
      if (button is! IconButton) throw StateError('Fullscreen button missing');
      button.onPressed?.call();
      await waitFor(() => window.isFullScreen, 'fullscreen');
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    await write({
      'type': 'metadata',
      'label': label,
      'arrivals': arrivals,
      'commentMode': 'mixed-80-percent-scrolling',
      'opacity': settings.danmakuOpacity,
      'area': settings.danmakuArea,
      'fontScale': settings.danmakuFontScale,
      'effect': settings.danmakuStyle.name,
      'fullscreen': fullscreen,
      'seconds': seconds,
      'warmupSeconds': 8,
      'seekSeconds': 37,
      'profile': const bool.fromEnvironment('dart.vm.profile'),
      'release': const bool.fromEnvironment('dart.vm.product'),
    });
    var stages = <({String name, bool comments, bool controls})>[
      (name: 'video', comments: false, controls: false),
      (name: 'controls', comments: false, controls: true),
      (name: 'danmaku', comments: true, controls: false),
      (name: 'danmaku-controls', comments: true, controls: true),
    ];
    if (env['BILI_4K_REVERSE'] == '1') stages = stages.reversed.toList();
    for (final stage in stages) {
      hoveredRegion?.onExit?.call(const PointerExitEvent());
      hoveredRegion = null;
      settings = settings.copyWith(danmakuEnabled: stage.comments);
      rebuild.value++;
      await WidgetsBinding.instance.endOfFrame;
      await session.seek(const Duration(seconds: 37));
      await waitFor(
        () =>
            session.snapshots.value.phase == PlaybackPhase.playing &&
            !session.snapshots.value.isBuffering &&
            !session.snapshots.value.isSeeking,
        'playing after seek',
      );
      await showControls(stage.controls);
      await Future<void>.delayed(const Duration(seconds: 8));
      final clock = Stopwatch()..start();
      final baseline = await sample(stage.name, clock);
      await write({...baseline, 'type': 'phase-start'});
      timings.clear();
      debugPrint('4K_STAGE ${stage.name}');
      for (var tick = 1; tick <= seconds; tick++) {
        final delay = Duration(seconds: tick) - clock.elapsed;
        if (delay > Duration.zero) await Future<void>.delayed(delay);
        final row = await sample(stage.name, clock);
        await write(row);
        if (row['controlsVisible'] != stage.controls ||
            row['buffering'] != false ||
            row['seeking'] != false ||
            row['phase'] != 'playing' ||
            row['audioDecoded'] != true ||
            errors != 0 ||
            (stage.comments && session.danmaku.visibleCount == 0)) {
          throw StateError('Invalid sampled state: ${stage.name}');
        }
      }
      await write({
        'type': 'phase-end',
        'stage': stage.name,
        'elapsedMs': clock.elapsedMilliseconds,
      });
    }
    await write({'type': 'complete'});
  } catch (error, stack) {
    await write({'type': 'failed', 'reason': error.toString()});
    debugPrint('$error\n$stack');
    exitCode = 1;
  } finally {
    hoveredRegion?.onExit?.call(const PointerExitEvent());
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 150));
    SchedulerBinding.instance.removeTimingsCallback(collect);
    await session.close();
    input.dispose();
    rebuild.dispose();
  }
  exit(exitCode);
}

Element? _find(bool Function(Element) predicate) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (predicate(element)) {
      found = element;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

const _part = VideoPart(
  cid: '123',
  page: 1,
  title: 'Public 4K60 fixture',
  duration: Duration(seconds: 634),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: 'Public 4K60 playback benchmark',
    coverUrl: '',
    author: 'Blender Foundation',
    duration: Duration(seconds: 634),
  ),
  description: '',
  parts: [_part],
);

final class _LocalRepository implements PlaybackRepository {
  _LocalRepository(this.uri, this.arrivals);
  final Uri uri;
  final int arrivals;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(urls: [uri], codec: 'avc1', bandwidth: 8500000),
    audio: null,
    quality: 120,
    qualities: const [120],
    duration: const Duration(seconds: 634),
    headers: const {},
    kind: PlaybackMediaKind.progressive,
  );
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [
    for (var i = 0; i < 120 * arrivals; i++)
      TimedComment(
        id: '$i',
        position: Duration(microseconds: i * 1000000 ~/ arrivals),
        text: '公开4K60播放性能测试 弹幕对照 $i',
        mode: i % 10 < 8 ? 1 : (i.isEven ? 5 : 4),
        color: 0xffffff,
        fontSize: 25,
      ),
  ];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => [];
}

final class _NoProgress implements PlaybackProgressStore {
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
