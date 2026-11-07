import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/platform_defaults.dart';
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
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Local media only; the loopback controller records telemetry and starts traces.
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  const base = String.fromEnvironment(
    'ANDROID_4K_BASE',
    defaultValue: 'http://127.0.0.1:18965',
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<Object?> request(String path, [Map<String, Object?>? data]) async {
    final req = await client.openUrl(
      data == null ? 'GET' : 'POST',
      Uri.parse('$base$path'),
    );
    if (data != null) {
      req.headers.contentType = ContentType.json;
      final payload = utf8.encode(jsonEncode(data));
      req.contentLength = payload.length;
      req.add(payload);
    }
    final res = await req.close().timeout(const Duration(seconds: 30));
    final body = await utf8.decoder.bind(res).join();
    if (res.statusCode != 200) {
      throw StateError('Collector returned ${res.statusCode}');
    }
    return jsonDecode(body);
  }

  Future<void> write(Map<String, Object?> row) async {
    await request('/event', {
      'timeUtc': DateTime.now().toUtc().toIso8601String(),
      'monoUs': developer.Timeline.now,
      'pid': pid,
      ...row,
    });
  }

  final config = await request('/config');
  if (config is! List<Object?>) throw StateError('Scenario list required');
  final vm = await developer.Service.getInfo();
  await write({
    'type': 'bootstrap',
    'vmUri': vm.serverUri?.toString(),
    'profile': const bool.fromEnvironment('dart.vm.profile'),
    'release': const bool.fromEnvironment('dart.vm.product'),
  });
  var errors = 0;
  FlutterError.onError = (details) {
    errors++;
    FlutterError.presentError(details);
  };
  try {
    for (final value in config) {
      if (value is! Map<String, Object?>) throw StateError('Invalid scenario');
      final name = value['name'] as String;
      final portrait = value['portrait'] == true;
      final panel = value['panel'] == true;
      final comments = value['comments'] == true;
      final show = value['controls'] == true;
      final seconds = value['seconds'] as int? ?? 30;
      final arrivals = value['arrivals'] as int? ?? 20;
      final rate = (value['rate'] as num? ?? 1).toDouble();
      final seekSeconds = value['seekSeconds'] as int? ?? 37;
      final holdCycles = value['holdCycles'] as int? ?? 0;
      final holdMs = value['holdMs'] as int? ?? 1500;
      final gapMs = value['gapMs'] as int? ?? 1200;
      final progressive = value['progressive'] == true;
      Uri mediaUri(String path) {
        final uri = Uri.parse(path);
        return uri.hasScheme ? uri : Uri.file(path);
      }

      final video = mediaUri(value['video'] as String);
      final audio = mediaUri(value['audio'] as String);
      final duration = Duration(
        seconds: value['durationSeconds'] as int? ?? 634,
      );
      // Leave room for trace setup after the eight-second playback warmup.
      if (!rate.isFinite ||
          rate <= 0 ||
          rate > 3 ||
          holdCycles < 0 ||
          holdCycles > 12 ||
          (holdCycles > 0 &&
              (!panel || rate != 1 || holdMs < 600 || gapMs < 500)) ||
          seekSeconds < 0 ||
          seekSeconds + (8 + seconds + 5) * rate >= duration.inSeconds) {
        throw StateError('Invalid rate or insufficient media duration: $name');
      }
      final part = VideoPart(
        cid: '123',
        page: 1,
        title: 'Public fixture',
        duration: duration,
      );
      final detail = VideoDetail(
        summary: VideoSummary(
          id: const VideoId('BV1abc123456'),
          title: 'Public 4K60 benchmark',
          coverUrl: '',
          author: 'Blender Foundation',
          duration: duration,
        ),
        description: '',
        parts: [part],
      );
      await SystemChrome.setPreferredOrientations([
        portrait
            ? DeviceOrientation.portraitUp
            : DeviceOrientation.landscapeLeft,
      ]);
      await Future<void>.delayed(const Duration(seconds: 1));
      final repository = Android4kRepository(
        video,
        audio,
        progressive,
        arrivals,
        codec: value['codec'] as String? ?? 'avc1',
        duration: duration,
      );
      final engine = MediaKitEngine(
        experimentalVideoFrameQueue: value['queue'] as bool?,
        experimentalAndroidViewport: value['viewport'] as bool?,
        experimentalAudioAutosync: value['autosync'] as int?,
      );
      final session = PlaybackSession(
        engine: engine,
        repository: repository,
        progress: Android4kProgress(),
        accountScope: () => 'guest',
      );
      final input = ShortcutCoordinator();
      final window = WindowService();
      final settings = const AppSettings.defaults().copyWith(
        autoPlay: true,
        resumePlayback: false,
        continuousPlayback: false,
        defaultVolume: 0,
        defaultPlaybackRate: rate,
        danmakuEnabled: comments,
        danmakuArea: defaultDanmakuArea,
        danmakuFontScale: defaultDanmakuFontScale,
        showCollapsedProgress: value['progress'] != false,
      );
      final timings = <FrameTiming>[];
      void collect(List<FrameTiming> frames) => timings.addAll(frames);
      SchedulerBinding.instance.addTimingsCallback(collect);
      MouseRegion? hovered;
      final touches = <Map<String, Object?>>[];
      final observations = <Map<String, Object?>>[];
      var cycle = 0;
      var observing = false;
      Future<void>? observer;
      Future<void>? holds;
      Object? holdError;
      var exerciseActive = true;
      Object? observationError;
      void recordTouch(String action) {
        if (!observing) return;
        touches.add({
          'action': action,
          'cycle': cycle,
          'monoUs': developer.Timeline.now,
          'positionMs': engine.currentSnapshot.position.inMilliseconds,
          'rate': engine.currentSnapshot.rate,
        });
      }

      bool controlsVisible() {
        final control = _find(
          (e) => e.widget.key == const ValueKey('player-controls'),
        );
        if (control == null) return false;
        var visible = true;
        control.visitAncestorElements((e) {
          if (e.widget case final FadeTransition fade
              when fade.opacity.value < .999) {
            visible = false;
          }
          if (e.widget case final IgnorePointer pointer when pointer.ignoring) {
            visible = false;
          }
          return true;
        });
        return visible;
      }

      Future<void> waitFor(
        bool Function() ready,
        String condition, {
        Duration timeout = const Duration(seconds: 40),
      }) async {
        final watch = Stopwatch()..start();
        while (!ready()) {
          if (watch.elapsed > timeout) {
            throw StateError('Timed out: $condition');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      Future<void> observeRates() async {
        while (observing) {
          final readStartedUs = developer.Timeline.now;
          final native = await engine.inspectNativePlaybackTiming(
            includeRateClocks: true,
          );
          final snapshot = engine.currentSnapshot;
          observations.add({
            'monoUs': developer.Timeline.now,
            'nativeReadStartedUs': readStartedUs,
            'positionMs': snapshot.position.inMilliseconds,
            'rate': snapshot.rate,
            'phase': snapshot.phase.name,
            'buffering': snapshot.isBuffering,
            'seeking': snapshot.isSeeking,
            'frameDrops': native.frameDrops,
            'decoderDrops': native.decoderDrops,
            'avsyncSeconds': native.avsyncSeconds,
            'nativeRate': native.nativeRate,
            'audioPositionSeconds': native.audioPositionSeconds,
            'videoPositionSeconds': native.videoPositionSeconds,
          });
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      Future<void> exerciseHolds() async {
        await Future<void>.delayed(const Duration(seconds: 2));
        final element = _find(
          (e) => e.widget.key == const ValueKey('player-surface-tap-target'),
        );
        final box = element?.findRenderObject();
        if (box is! RenderBox) throw StateError('Touch surface missing');
        final point = box.localToGlobal(
          Offset(box.size.width * .7, box.size.height * .4),
        );
        final dpr = WidgetsBinding
            .instance
            .platformDispatcher
            .views
            .first
            .devicePixelRatio;
        Future<void> touch(String action) async {
          await request('/touch', {
            'action': action,
            'x': (point.dx * dpr).round(),
            'y': (point.dy * dpr).round(),
          });
        }

        for (cycle = 1; cycle <= holdCycles && exerciseActive; cycle++) {
          try {
            await touch('DOWN');
            await waitFor(
              () => engine.currentSnapshot.rate == 2,
              'long press enters 2x',
              timeout: const Duration(seconds: 2),
            );
            final down = touches.lastWhere((e) => e['action'] == 'down');
            final remaining =
                Duration(milliseconds: holdMs) -
                Duration(
                  microseconds:
                      developer.Timeline.now - (down['monoUs'] as int),
                );
            if (remaining > Duration.zero) {
              await Future<void>.delayed(remaining);
            }
          } finally {
            await touch('UP');
          }
          await waitFor(
            () => engine.currentSnapshot.rate == 1,
            'release restores 1x',
            timeout: const Duration(seconds: 2),
          );
          await Future<void>.delayed(Duration(milliseconds: gapMs));
        }
      }

      Future<void> controls(bool visible) async {
        hovered?.onExit?.call(const PointerExitEvent());
        hovered = null;
        if (controlsVisible() != visible) {
          final target = _find(
            (e) =>
                e.widget is Semantics &&
                (e.widget as Semantics).properties.label == '视频播放器' &&
                (e.widget as Semantics).properties.onTap != null,
          )?.widget;
          if (target is! Semantics) throw StateError('Tap target missing');
          target.properties.onTap?.call();
        }
        await waitFor(() => controlsVisible() == visible, 'controls=$visible');
        if (visible) {
          _find((e) => e.widget.key == const ValueKey('player-controls'))
              ?.visitAncestorElements((e) {
                if (e.widget case final MouseRegion region
                    when region.onEnter != null) {
                  hovered = region;
                  return false;
                }
                return true;
              });
          if (hovered == null) {
            throw StateError('Control retention target missing');
          }
          hovered?.onEnter?.call(const PointerEnterEvent());
        }
      }

      Future<Map<String, Object?>> sample(String type, Stopwatch clock) async {
        final s = engine.currentSnapshot;
        final d = engine.inspectDiagnostics();
        final n = await engine.inspectNativePlaybackTiming();
        final hardware = await engine.inspectHardwareDecoder();
        final cache = session.danmaku.rasterStatistics;
        final view = WidgetsBinding.instance.platformDispatcher.views.first;
        final element = _find((e) => e.widget is VideoSurface);
        final box = element?.findRenderObject();
        final size = box is RenderBox ? box.size : Size.zero;
        final frames = List<FrameTiming>.of(timings);
        timings.clear();
        return {
          'type': type,
          'stage': name,
          'elapsedMs': clock.elapsedMilliseconds,
          'positionMs': s.position.inMilliseconds,
          'bufferedMs': s.buffered.inMilliseconds,
          'phase': s.phase.name,
          'buffering': s.isBuffering,
          'seeking': s.isSeeking,
          'rate': s.rate,
          'decoded': [d.videoWidth, d.videoHeight],
          'output': [d.outputWidth, d.outputHeight],
          'audioDecoded': d.hasDecodedAudio,
          'videoCodec': d.videoCodec,
          'surface': [size.width, size.height],
          'view': [view.physicalSize.width, view.physicalSize.height],
          'dpr': view.devicePixelRatio,
          'refreshRate': view.display.refreshRate,
          'hwdec': hardware,
          'queueActive': engine.videoFrameQueueActive,
          'controlsVisible': controlsVisible(),
          'visible': session.danmaku.visibleCount,
          'pending': session.danmaku.pendingCount,
          'droppedComments': session.danmaku.dropped,
          'rasterBytes': session.danmaku.textRasterBytes,
          'rasterBuilds': cache.rasterBuilds,
          'cacheHits': cache.cacheHits,
          'imagePaints': cache.imagePaints,
          'directPaints': cache.directPaints,
          'dartFrames': frames.length,
          'uiUs': frames.map((f) => f.buildDuration.inMicroseconds).toList(),
          'rasterUs': frames
              .map((f) => f.rasterDuration.inMicroseconds)
              .toList(),
          'totalUs': frames.map((f) => f.totalSpan.inMicroseconds).toList(),
          'vsyncStartUs': frames
              .map((f) => f.timestampInMicroseconds(FramePhase.vsyncStart))
              .toList(),
          'frameDrops': n.frameDrops,
          'decoderDrops': n.decoderDrops,
          'avsyncSeconds': n.avsyncSeconds,
          'errors': errors,
        };
      }

      try {
        await write({'type': 'stage-config', 'stage': name, 'scenario': value});
        final startup = Stopwatch()..start();
        runApp(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: MaterialApp(
              theme: BiliTheme.light(),
              navigatorObservers: [input.routes],
              builder: (context, child) => Listener(
                onPointerDown: (_) => recordTouch('down'),
                onPointerUp: (_) => recordTouch('up'),
                child: AppInputHost<Object>(
                  dispatcher: input,
                  routes: input.routes,
                  child: child ?? const SizedBox(),
                ),
              ),
              home: Scaffold(
                backgroundColor: Colors.black,
                body: Center(
                  child: AspectRatio(
                    aspectRatio: 16 / 9,
                    child: panel
                        ? PlaybackPanel(
                            detail: detail,
                            part: part,
                            settings: settings,
                            onToggleComments: () {},
                            window: window,
                          )
                        : VideoSurface(engine: engine),
                  ),
                ),
              ),
            ),
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!panel) {
          final policy = MediaRequestPolicy();
          await engine.open(
            progressive
                ? ProgressiveSource(
                    MediaTrack(uri: video, requestPolicy: policy),
                  )
                : DashPairSource(
                    video: MediaTrack(uri: video, requestPolicy: policy),
                    audio: MediaTrack(uri: audio, requestPolicy: policy),
                  ),
            const OpenOptions(play: true, volume: 0),
          );
        }
        await waitFor(
          () =>
              engine.currentSnapshot.phase == PlaybackPhase.playing &&
              engine.inspectDiagnostics().hasDecodedAudio,
          'decoded audio/video',
        );
        await write({
          'type': 'startup',
          'stage': name,
          'firstPlayingMs': startup.elapsedMilliseconds,
        });
        if (panel && !portrait) {
          await controls(true);
          final button = _find(
            (e) =>
                e.widget is IconButton &&
                (e.widget as IconButton).icon is Icon &&
                ((e.widget as IconButton).icon as Icon).icon ==
                    BiliIcons.fullscreen,
          )?.widget;
          if (button is! IconButton) {
            throw StateError('Fullscreen control missing');
          }
          hovered?.onExit?.call(const PointerExitEvent());
          hovered = null;
          button.onPressed?.call();
          await waitFor(() => window.isFullScreen, 'fullscreen');
          await Future<void>.delayed(const Duration(seconds: 1));
        }
        if (panel) {
          await session.setRate(rate);
        } else {
          await engine.setRate(rate);
        }
        await engine.seek(Duration(seconds: seekSeconds));
        await waitFor(
          () =>
              (value['allowBuffering'] == true
                  ? [
                      PlaybackPhase.playing,
                      PlaybackPhase.buffering,
                    ].contains(engine.currentSnapshot.phase)
                  : engine.currentSnapshot.phase == PlaybackPhase.playing &&
                        !engine.currentSnapshot.isBuffering) &&
              !engine.currentSnapshot.isSeeking,
          'playing after seek',
        );
        if (panel) await controls(show);
        await Future<void>.delayed(const Duration(seconds: 8));
        await write({
          'type': 'metadata',
          'stage': name,
          'settings': {
            'area': settings.danmakuArea,
            'fontScale': settings.danmakuFontScale,
            'opacity': settings.danmakuOpacity,
            'arrivals': arrivals,
            'holdRate': settings.shortcuts.holdRate,
            'holdDelayMs': settings.shortcuts.holdDelayMs,
          },
          'scenario': value,
          'nativeOutput': await engine.inspectNativeOutputConfiguration(),
        });
        await request('/ready', {'stage': name, 'seconds': seconds});
        final clock = Stopwatch()..start();
        await write(await sample('phase-start', clock));
        timings.clear();
        if (holdCycles > 0) {
          observing = true;
          observer = observeRates().catchError((Object error) {
            observationError = error;
          });
          holds = exerciseHolds().catchError((Object error) {
            holdError = error;
          });
        }
        for (var tick = 1; tick <= seconds; tick++) {
          final delay = Duration(seconds: tick) - clock.elapsed;
          if (delay > Duration.zero) await Future<void>.delayed(delay);
          final row = await sample('sample', clock);
          await write(row);
          if ((value['allowBuffering'] == true
                  ? !['playing', 'buffering'].contains(row['phase'])
                  : row['phase'] != 'playing' || row['buffering'] != false) ||
              row['seeking'] != false ||
              (holdCycles == 0 &&
                  ((row['rate'] as double) - rate).abs() > .001) ||
              row['audioDecoded'] != true ||
              (panel && row['controlsVisible'] != show) ||
              errors != 0) {
            throw StateError('Invalid sampled state: $name');
          }
        }
        await holds;
        if (holdError != null) throw StateError('Touch exercise: $holdError');
        if (observationError != null) {
          throw StateError('Rate observation: $observationError');
        }
        if (engine.currentSnapshot.rate != rate) {
          throw StateError('Final rate did not restore');
        }
        await write(await sample('phase-end', clock));
        await request('/finish', {'stage': name});
      } catch (error) {
        await write({
          'type': 'case-failed',
          'stage': name,
          'reason': error.toString(),
          'hwdec': await engine.inspectHardwareDecoder(),
          'phase': engine.currentSnapshot.phase.name,
        });
        await request('/abort', {'stage': name});
        if (value['continueOnFailure'] != true) rethrow;
      } finally {
        exerciseActive = false;
        await holds;
        observing = false;
        await observer;
        if (holdCycles > 0) {
          await write({
            'type': 'hold-observations',
            'stage': name,
            'touches': touches,
            'observations': observations,
          });
        }
        hovered?.onExit?.call(const PointerExitEvent());
        runApp(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        SchedulerBinding.instance.removeTimingsCallback(collect);
        await session.close();
        input.dispose();
        await Future<void>.delayed(const Duration(seconds: 1));
      }
    }
    await write({'type': 'complete'});
  } catch (error, stack) {
    await write({'type': 'failed', 'reason': error.toString()});
    debugPrint('$error\n$stack');
  } finally {
    client.close();
  }
}

Element? _find(bool Function(Element) predicate) {
  Element? found;
  void visit(Element e) {
    if (found != null) return;
    if (predicate(e)) {
      found = e;
      return;
    }
    e.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return found;
}

final class Android4kRepository implements PlaybackRepository {
  Android4kRepository(
    this.video,
    this.audio,
    this.progressive,
    this.arrivals, {
    required this.codec,
    required this.duration,
    this.withSubtitles = false,
  });
  final Uri video, audio;
  final bool progressive;
  final int arrivals;
  final String codec;
  final Duration duration;
  final bool withSubtitles;
  @override
  Future<PlaybackMedia> resolve(
    VideoId id,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(urls: [video], codec: codec, bandwidth: 8000000),
    audio: progressive
        ? null
        : PlaybackTrack(urls: [audio], codec: 'mp4a', bandwidth: 160000),
    quality: 120,
    qualities: const [120],
    duration: duration,
    headers: const {},
    kind: progressive ? PlaybackMediaKind.progressive : PlaybackMediaKind.dash,
  );
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [
    for (var i = 0; i < duration.inSeconds * arrivals; i++)
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
    VideoId id,
    String cid, {
    required RequestCancellation cancellation,
  }) async => withSubtitles
      ? [SubtitleTrack('公开测试字幕', Uri.parse('fixture:subtitles'))]
      : [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => withSubtitles
      ? [
          for (var second = 0; second < duration.inSeconds; second += 2)
            SubtitleCue(
              Duration(seconds: second),
              Duration(seconds: second + 2),
              'Flutter 字幕叠加验证 $second',
            ),
        ]
      : [];
}

final class Android4kProgress implements PlaybackProgressStore {
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
