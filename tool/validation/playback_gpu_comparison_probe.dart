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
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

/// Local-only production panel: same video, comments, controls and time range.
/// BILI_GPU_PANEL=surface/panel; BILI_GPU_ARRIVALS=2/20;
/// BILI_GPU_OPACITY=0.8/1; BILI_GPU_SIZE=960/1600;
/// BILI_GPU_MODE=scroll/fixed/mixed (80% scrolling, 20% fixed).
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  final env = Platform.environment;
  final label = env['BILI_GPU_LABEL'];
  final media = env['BILI_GPU_MEDIA'];
  if (label == null || media == null || !RegExp(r'^[\w-]+$').hasMatch(label)) {
    throw StateError('Set BILI_GPU_LABEL and BILI_GPU_MEDIA');
  }
  final seconds = int.parse(env['BILI_GPU_SECONDS'] ?? '20');
  final arrivals = int.parse(env['BILI_GPU_ARRIVALS'] ?? '20');
  final mode = env['BILI_GPU_MODE'] ?? 'scroll';
  final opacity = double.parse(env['BILI_GPU_OPACITY'] ?? '0.8');
  final width = double.parse(env['BILI_GPU_SIZE'] ?? '960');
  if (!['scroll', 'fixed', 'mixed'].contains(mode) ||
      seconds < 10 ||
      seconds > 20 ||
      arrivals < 1 ||
      arrivals > 20 ||
      !opacity.isFinite ||
      opacity < 0 ||
      opacity > 1 ||
      !width.isFinite ||
      width < 320 ||
      width > 1600) {
    throw StateError('Invalid sampling duration, density, opacity or size');
  }
  final surfaceOnly = env['BILI_GPU_PANEL'] == 'surface';
  final size = Size(width, width * 9 / 16);
  await windowManager.setSize(Size(width + 40, size.height + 80));
  final file = File('build/validation/windows-gpu-playback-$label.jsonl');
  if (await file.exists()) throw StateError('Use a fresh label');
  await file.parent.create(recursive: true);
  final engine = MediaKitEngine();
  final session = PlaybackSession(
    engine: engine,
    repository: _LocalRepository(File(media).absolute.uri, arrivals, mode),
    progress: _NoProgress(),
    accountScope: () => 'guest',
  );
  final input = ShortcutCoordinator();
  var settings = const AppSettings.defaults().copyWith(
    autoPlay: true,
    resumePlayback: false,
    defaultVolume: 0,
    danmakuEnabled: false,
    danmakuOpacity: opacity,
  );
  final rebuild = ValueNotifier(0);
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> frames) => timings.addAll(frames);
  SchedulerBinding.instance.addTimingsCallback(collect);
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
            child: SizedBox.fromSize(
              size: size,
              child: ValueListenableBuilder<int>(
                valueListenable: rebuild,
                builder: (context, _, _) => surfaceOnly
                    ? VideoSurface(engine: engine)
                    : PlaybackPanel(
                        detail: _detail,
                        part: _part,
                        settings: settings,
                        onToggleComments: () {},
                        window: WindowService(),
                      ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await windowManager.show();
  await windowManager.setSize(Size(width + 40, size.height + 80));
  await WidgetsBinding.instance.endOfFrame;
  final windowSize = await windowManager.getSize();
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  debugPrint(
    'GPU_WINDOW ${jsonEncode({'windowWidth': windowSize.width, 'windowHeight': windowSize.height, 'physicalWidth': view.physicalSize.width, 'physicalHeight': view.physicalSize.height, 'dpr': view.devicePixelRatio})}',
  );

  Future<void> stage(String name, int count) async {
    debugPrint('GPU_STAGE $name ${DateTime.now().toUtc().toIso8601String()}');
    timings.clear();
    for (var i = 0; i < count; i++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      final snapshot = engine.currentSnapshot;
      final diagnostic = engine.inspectDiagnostics();
      final native = await engine.inspectNativePlaybackTiming();
      await file.writeAsString(
        '${jsonEncode({'stage': name, 'pid': pid, 'timeUtc': DateTime.now().toUtc().toIso8601String(), 'panel': !surfaceOnly, 'arrivals': arrivals, 'mode': mode, 'opacity': opacity, 'positionMs': snapshot.position.inMilliseconds, 'phase': snapshot.phase.name, 'decodedWidth': diagnostic.videoWidth, 'decodedHeight': diagnostic.videoHeight, 'outputWidth': diagnostic.outputWidth, 'outputHeight': diagnostic.outputHeight, 'hwdec': await engine.inspectHardwareDecoder(), 'avsyncSeconds': native.avsyncSeconds, 'frameDrops': native.frameDrops, 'decoderDrops': native.decoderDrops, 'dartFrames': timings.length, 'uiUs': timings.map((f) => f.buildDuration.inMicroseconds).toList(), 'rasterUs': timings.map((f) => f.rasterDuration.inMicroseconds).toList(), 'visible': session.danmaku.visibleCount, 'rasterBuilds': session.danmaku.rasterStatistics.rasterBuilds, 'imagePaints': session.danmaku.rasterStatistics.imagePaints, 'directPaints': session.danmaku.rasterStatistics.directPaints})}\n',
        mode: FileMode.append,
      );
      timings.clear();
    }
  }

  void tapSurface() {
    Element? target;
    void visit(Element element) {
      if (element.widget.key == const ValueKey('player-surface-tap-target')) {
        target = element;
      }
      element.visitChildren(visit);
    }

    WidgetsBinding.instance.rootElement!.visitChildren(visit);
    final box = target?.findRenderObject();
    if (box is! RenderBox) throw StateError('Player tap target missing');
    final position = box.localToGlobal(const Offset(140, 80));
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(position: position),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(position: position),
    );
  }

  try {
    if (surfaceOnly) {
      await engine.open(
        ProgressiveSource(
          MediaTrack(
            uri: File(media).absolute.uri,
            requestPolicy: MediaRequestPolicy(),
          ),
        ),
        const OpenOptions(play: true, volume: 0),
      );
    }
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    while (engine.currentSnapshot.phase != PlaybackPhase.playing) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Playback did not start');
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    await engine.seek(const Duration(seconds: 10));
    await stage('video-warmup', 4);
    await stage('video', seconds);
    if (!surfaceOnly) {
      settings = settings.copyWith(danmakuEnabled: true);
      rebuild.value++;
      await session.seek(const Duration(seconds: 10));
      await stage('danmaku-warmup', 5);
      await stage('danmaku', seconds);
      tapSurface();
      await stage('controls-warmup', 1);
      await stage('controls', seconds);
    }
    await engine.pause();
    await stage('paused', 3);
  } finally {
    SchedulerBinding.instance.removeTimingsCallback(collect);
    runApp(const SizedBox.shrink());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await session.close();
    input.dispose();
    rebuild.dispose();
  }
  exit(0);
}

const _part = VideoPart(
  cid: '123',
  page: 1,
  title: 'Local fixture',
  duration: Duration(seconds: 65),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: 'GPU fixture',
    coverUrl: '',
    author: 'Local',
    duration: Duration(seconds: 65),
  ),
  description: '',
  parts: [_part],
);

final class _LocalRepository implements PlaybackRepository {
  _LocalRepository(this.uri, this.arrivals, this.mode);
  final Uri uri;
  final int arrivals;
  final String mode;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(urls: [uri], codec: 'avc1', bandwidth: 10000000),
    audio: null,
    quality: 80,
    qualities: const [80],
    duration: const Duration(seconds: 65),
    headers: const {},
    kind: PlaybackMediaKind.progressive,
  );
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [
    for (var i = 0; i < 65 * arrivals; i++)
      TimedComment(
        id: '$i',
        position: Duration(microseconds: i * 1000000 ~/ arrivals),
        text: '相同素材播放与弹幕 GPU 对照 $i',
        mode: mode == 'scroll' || (mode == 'mixed' && i % 10 < 8)
            ? 1
            : (i.isEven ? 5 : 4),
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
