import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/shortcut_coordinator.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/app_input_host.dart';
import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/shared/ui/bili_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'android_4k60_probe.dart' show Android4kRepository, Android4kProgress;
import 'android_surface_view_adapter.dart';

/// Controlled local DASH, shared product overlays, no account or saved settings.
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  const base = 'http://127.0.0.1:18965';
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
  Future<Object?> request(String path, [Map<String, Object?>? body]) async {
    final req = await client.openUrl(
      body == null ? 'GET' : 'POST',
      Uri.parse('$base$path'),
    );
    if (body != null) {
      req.headers.contentType = ContentType.json;
      final payload = utf8.encode(jsonEncode(body));
      req.contentLength = payload.length;
      req.add(payload);
    }
    final response = await req.close().timeout(const Duration(seconds: 40));
    final text = await utf8.decoder.bind(response).join();
    if (response.statusCode != 200) {
      throw StateError('Collector ${response.statusCode}');
    }
    return jsonDecode(text);
  }

  Future<void> write(Map<String, Object?> value) async {
    await request('/event', {
      'timeUtc': DateTime.now().toUtc().toIso8601String(),
      'monoUs': developer.Timeline.now,
      'pid': pid,
      ...value,
    });
  }

  var errors = 0;
  FlutterError.onError = (details) {
    errors++;
    FlutterError.presentError(details);
  };
  try {
    final rows = await request('/config') as List<Object?>;
    await write({
      'type': 'bootstrap',
      'vmUri': (await developer.Service.getInfo()).serverUri?.toString(),
    });
    for (final row in rows) {
      final config = Map<String, Object?>.from(row as Map);
      final name = config['name'] as String;
      if (!{'mpv', 'media_kit'}.contains(config['backend'])) {
        throw StateError('Unsupported benchmark backend or output');
      }
      final direct = config['direct'] == true;
      final surfaceView = config['surfaceView'] == true;
      final seconds = config['seconds'] as int? ?? 30;
      final rate = (config['rate'] as num? ?? 3).toDouble();
      final duration = Duration(
        seconds: config['durationSeconds'] as int? ?? 180,
      );
      if (seconds < 5 ||
          seconds > 60 ||
          !{1.0, 3.0}.contains(rate) ||
          duration.inSeconds < (seconds + 15) * rate + 15) {
        throw StateError('Invalid benchmark duration or rate');
      }
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
      ]);
      await Future<void>.delayed(const Duration(seconds: 1));
      final PlayerEngine engine = MediaKitEngine();
      final infoSource = engine as PlayerInformationSource;
      final failures = engine.failures.listen((failure) {
        unawaited(
          write({
            'type': 'engine-failure',
            'stage': name,
            'kind': failure.kind.name,
            'message': failure.message,
          }).catchError((Object _) {}),
        );
      });
      final composition = AndroidSurfaceViewBenchmark(engine: engine);
      final session = PlaybackSession(
        engine: engine,
        repository: Android4kRepository(
          Uri.parse(config['video'] as String),
          Uri.parse(config['audio'] as String),
          false,
          20,
          codec: 'avc1',
          duration: duration,
          withSubtitles: true,
        ),
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
        subtitlesEnabled: true,
        androidVideoOutput: direct
            ? AndroidVideoOutputPreference.directTexture
            : AndroidVideoOutputPreference.renderedTexture,
      );
      final frames = <FrameTiming>[];
      void collect(List<FrameTiming> batch) => frames.addAll(batch);
      SchedulerBinding.instance.addTimingsCallback(collect);
      MouseRegion? hover;
      bool controlsVisible() {
        final control = _find(
          (e) => e.widget.key == const ValueKey('player-controls'),
        );
        if (control == null) return false;
        var visible = true;
        control.visitAncestorElements((element) {
          if (element.widget case final FadeTransition fade
              when fade.opacity.value < .999) {
            visible = false;
          }
          if (element.widget case final IgnorePointer pointer
              when pointer.ignoring) {
            visible = false;
          }
          return true;
        });
        return visible;
      }

      Future<void> waitFor(bool Function() ready, String condition) async {
        final watch = Stopwatch()..start();
        while (!ready()) {
          if (watch.elapsed > const Duration(seconds: 45)) {
            throw StateError('Timed out: $condition');
          }
          if (engine.currentSnapshot.phase == PlaybackPhase.failed) {
            throw StateError('Playback failed: $condition');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      try {
        await write({
          'type': 'stage-config',
          'stage': name,
          'scenario': config,
        });
        runApp(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: VideoCompositionScope(
              adapter: composition,
              child: MaterialApp(
                theme: BiliTheme.light(),
                navigatorObservers: [input.routes],
                builder: (_, child) => AppInputHost<Object>(
                  dispatcher: input,
                  routes: input.routes,
                  child: child ?? const SizedBox(),
                ),
                home: Scaffold(
                  backgroundColor: Colors.black,
                  body: Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: PlaybackPanel(
                        detail: VideoDetail(
                          summary: VideoSummary(
                            id: const VideoId('BV1abc123456'),
                            title: 'Public 4K60 H.264 benchmark',
                            coverUrl: '',
                            author: 'Blender Foundation',
                            duration: duration,
                          ),
                          description: '',
                          parts: [
                            VideoPart(
                              cid: '123',
                              page: 1,
                              title: 'Public fixture',
                              duration: duration,
                            ),
                          ],
                        ),
                        part: VideoPart(
                          cid: '123',
                          page: 1,
                          title: 'Public fixture',
                          duration: duration,
                        ),
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
        await waitFor(
          () => engine.currentSnapshot.phase == PlaybackPhase.playing,
          'playing',
        );
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (!controlsVisible()) {
          final target = _find(
            (e) =>
                e.widget is Semantics &&
                (e.widget as Semantics).properties.label == '视频播放器',
          )?.widget;
          (target as Semantics?)?.properties.onTap?.call();
        }
        await waitFor(controlsVisible, 'controls before fullscreen');
        // Exercise the real full-screen transition while preserving the session.
        final button = _find(
          (e) =>
              e.widget is IconButton &&
              (e.widget as IconButton).icon is Icon &&
              ((e.widget as IconButton).icon as Icon).icon ==
                  BiliIcons.fullscreen,
        )?.widget;
        if (button is! IconButton) {
          throw StateError('Fullscreen control unavailable');
        }
        button.onPressed?.call();
        await waitFor(() => window.isFullScreen, 'fullscreen');
        await session.setRate(rate);
        await session.seek(const Duration(seconds: 15));
        await waitFor(
          () =>
              !engine.currentSnapshot.isSeeking &&
              engine.currentSnapshot.phase == PlaybackPhase.playing,
          'seek',
        );
        if (surfaceView) await composition.transfer();
        await Future<void>.delayed(const Duration(seconds: 2));
        // Keep the exact product controls visible for every measured scenario.
        final tap = _find(
          (e) =>
              e.widget is Semantics &&
              (e.widget as Semantics).properties.label == '视频播放器',
        )?.widget;
        if (!controlsVisible()) (tap as Semantics?)?.properties.onTap?.call();
        await Future<void>.delayed(const Duration(milliseconds: 400));
        _find((e) => e.widget.key == const ValueKey('player-controls'))
            ?.visitAncestorElements((e) {
              if (e.widget case final MouseRegion region
                  when region.onEnter != null) {
                hover = region;
                return false;
              }
              return true;
            });
        hover?.onEnter?.call(const PointerEnterEvent());
        await waitFor(controlsVisible, 'visible controls');
        await Future<void>.delayed(const Duration(seconds: 6));
        final initial = await infoSource.inspectPlaybackInformation();
        if (initial?.diagnostics?.hasDecodedAudio != true ||
            initial?.hardwareDecoder == null ||
            initial?.hardwareDecoder == 'no') {
          throw StateError('Audio or hardware decoder observation unavailable');
        }
        final actualDirect =
            initial?.videoOutput?.contains('direct') == true ||
            initial?.videoOutput == 'mediacodec_embed';
        if (actualDirect != direct) {
          throw StateError('Requested output mode was not active');
        }
        final nativeComposition = surfaceView
            ? await AndroidSurfaceViewBenchmark.channel
                  .invokeMapMethod<String, Object?>('composition')
            : null;
        if (config['hcpp'] == true && nativeComposition?['hcpp'] != true) {
          throw StateError('HCPP requested but not active');
        }
        await write({
          'type': 'metadata',
          'stage': name,
          'backend': initial?.backend,
          'videoOutput': initial?.videoOutput,
          'presentation': surfaceView
              ? (nativeComposition?['hcpp'] == true
                    ? 'SurfaceView / HCPP'
                    : 'SurfaceView / Hybrid Composition')
              : 'Flutter.Texture',
          'nativeComposition': nativeComposition,
          'hwdec': initial?.hardwareDecoder,
          'sourceFps': initial?.sourceFps,
          'sourceBitrate': initial?.videoNominalBitrate,
          'subtitleSelected': session.selectedSubtitle,
          'errors': errors,
        });
        await request('/ready', {'stage': name, 'seconds': seconds});
        final clock = Stopwatch()..start();
        frames.clear();
        for (var tick = 0; tick <= seconds; tick++) {
          final delay = Duration(seconds: tick) - clock.elapsed;
          if (delay > Duration.zero) await Future<void>.delayed(delay);
          final snapshot = engine.currentSnapshot;
          final info = await infoSource.inspectPlaybackInformation();
          final sampleFrames = List<FrameTiming>.of(frames);
          frames.clear();
          await write({
            'type': tick == 0
                ? 'phase-start'
                : tick == seconds
                ? 'phase-end'
                : 'sample',
            'stage': name,
            'elapsedMs': clock.elapsedMilliseconds,
            'positionMs': snapshot.position.inMilliseconds,
            'rate': snapshot.rate,
            'phase': snapshot.phase.name,
            'buffering': snapshot.isBuffering,
            'audioDecoded': info?.diagnostics?.hasDecodedAudio,
            'videoRendered': info?.diagnostics?.hasVideoOutput,
            'hwdec': info?.hardwareDecoder,
            'videoOutput': info?.videoOutput,
            'cacheBytes': info?.cacheBytes,
            'cacheSeconds': info?.cacheSeconds,
            'output': [
              info?.diagnostics?.outputWidth,
              info?.diagnostics?.outputHeight,
            ],
            'frameDrops': info?.frameDrops,
            'decoderDrops': info?.decoderDrops,
            'avsyncSeconds': info?.avSyncSeconds,
            'visible': session.danmaku.visibleCount,
            'controlsVisible': controlsVisible(),
            'subtitle': session.subtitleAt(snapshot.position)?.text,
            'dartFrames': sampleFrames.length,
            'uiUs': sampleFrames
                .map((f) => f.buildDuration.inMicroseconds)
                .toList(),
            'rasterUs': sampleFrames
                .map((f) => f.rasterDuration.inMicroseconds)
                .toList(),
            'errors': errors,
          });
          if (snapshot.phase != PlaybackPhase.playing ||
              snapshot.isBuffering ||
              snapshot.rate != rate ||
              errors > 0) {
            throw StateError('Invalid sampled playback state');
          }
        }
        await request('/finish', {'stage': name});
      } catch (error) {
        await write({
          'type': 'case-failed',
          'stage': name,
          'reason': error.toString(),
          'sessionError': session.error,
        });
        await request('/abort', {'stage': name});
        if (config['continueOnFailure'] != true) rethrow;
      } finally {
        hover?.onExit?.call(const PointerExitEvent());
        // Retain Surface/JNI references until decoder teardown is confirmed.
        if (surfaceView) await session.close();
        runApp(const SizedBox.shrink());
        await Future<void>.delayed(const Duration(milliseconds: 400));
        SchedulerBinding.instance.removeTimingsCallback(collect);
        if (!surfaceView) await session.close();
        composition.dispose();
        await failures.cancel();
        input.dispose();
        await Future<void>.delayed(const Duration(seconds: 2));
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
  Element? result;
  void visit(Element element) {
    if (result != null) return;
    if (predicate(element)) {
      result = element;
      return;
    }
    element.visitChildren(visit);
  }

  WidgetsBinding.instance.rootElement?.visitChildren(visit);
  return result;
}
