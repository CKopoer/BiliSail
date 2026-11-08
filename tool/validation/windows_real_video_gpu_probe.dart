import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/bili_app.dart';
import 'package:bilisail/app/dependencies.dart';
import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/shared/ui/bili_icons.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

/// Actual BiliApp/VideoScreen/PlaybackPanel, DASH/CDN and matching server comments.
/// Only progress ports are inert; settings and credentials are copied in memory.
Future<void> main() async {
  BiliWidgetsBinding.ensureInitialized();
  final env = Platform.environment;
  final label = env['BILI_REAL_LABEL'];
  var bvid = env['BILI_REAL_BVID'] ?? 'home';
  final start = int.parse(env['BILI_REAL_START'] ?? '30');
  if (label == null || !RegExp(r'^[a-zA-Z0-9_-]+$').hasMatch(label)) {
    throw StateError('A fresh BILI_REAL_LABEL is required');
  }
  final file = File('build/validation/windows-real-playback-$label.jsonl');
  await file.parent.create(recursive: true);
  if (await file.exists()) throw StateError('Playback label already exists');
  var errors = 0;
  var checkpoint = 'bootstrap';
  FlutterError.onError = (_) => errors++;
  WidgetsBinding.instance.platformDispatcher.onError = (_, _) {
    errors++;
    return true;
  };
  final memoryDb = AppDatabase(NativeDatabase.memory());
  await memoryDb.readSetting('schema_probe');
  final support = await getApplicationSupportDirectory();
  final settingsFile = File('${support.path}/bilisail.sqlite');
  var copiedPreferences = false;
  if (await settingsFile.exists()) {
    final readOnly = AppDatabase(
      NativeDatabase(
        settingsFile,
        setup: (db) => db.execute('PRAGMA query_only = ON'),
      ),
    );
    try {
      final preferences = await readOnly.readSetting('preferences.v1');
      if (preferences != null) {
        await memoryDb.writeSetting('preferences.v1', preferences);
        copiedPreferences = true;
      }
    } finally {
      await readOnly.close();
    }
  }
  final saved = await SystemCredentialStore().read();
  final dependencies = await AppDependencies.create(
    credentials: _MemoryCredentials(saved),
    databaseOverride: memoryDb,
  );
  final loaded = await dependencies.settings.load();
  // Audible output and automatic resume/next would spoil matched time windows.
  await dependencies.settings.save(
    loaded.copyWith(
      autoPlay: true,
      resumePlayback: false,
      continuousPlayback: false,
      defaultVolume: 0,
      danmakuEnabled: true,
      danmakuOpacity: env['BILI_REAL_OPACITY'] == null
          ? loaded.danmakuOpacity
          : double.parse(env['BILI_REAL_OPACITY']!),
      preferredQuality: env['BILI_REAL_QUALITY'] == null
          ? loaded.preferredQuality
          : int.parse(env['BILI_REAL_QUALITY']!),
    ),
  );
  await windowManager.setSize(const Size(1280, 720));
  // A hidden/minimized runner has no representative Flutter frame cadence.
  await windowManager.show();
  final repository = _ObservedRepository(dependencies);
  PlaybackSession? playing;
  final manager = PlaybackManager(
    createSession: (sleepTimer) => playing = PlaybackSession(
      sleepTimer: sleepTimer,
      engine: MediaKitEngine(),
      repository: repository,
      metadataRepository: repository,
      accountScope: () => dependencies.session.accountScope,
      sessionEpoch: () => dependencies.requests.sessionEpoch,
      progress: _InertProgress(),
    ),
  );
  final timings = <FrameTiming>[];
  void collect(List<FrameTiming> frames) => timings.addAll(frames);
  SchedulerBinding.instance.addTimingsCallback(collect);
  runApp(
    dependencies.scope(
      ProviderScope(
        overrides: [playbackManagerProvider.overrideWithValue(manager)],
        child: BiliApp(dependencies: dependencies),
      ),
    ),
  );

  Future<void> write(Map<String, Object?> value) => file.writeAsString(
    '${jsonEncode({'timeUtc': DateTime.now().toUtc().toIso8601String(), 'pid': pid, ...value})}\n',
    mode: FileMode.append,
  );
  ConsumerState<PlaybackPanel> panel() {
    final found = _findElement((element) {
      return element is StatefulElement &&
          element.state is ConsumerState<PlaybackPanel>;
    });
    if (found is! StatefulElement ||
        found.state is! ConsumerState<PlaybackPanel>) {
      throw StateError('Production PlaybackPanel is missing');
    }
    return found.state as ConsumerState<PlaybackPanel>;
  }

  Future<void> waitFor(bool Function() ready, String condition) async {
    final deadline = DateTime.now().add(const Duration(seconds: 45));
    while (!ready()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Probe condition timed out: $condition');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  try {
    await WidgetsBinding.instance.waitUntilFirstFrameRasterized;
    await waitFor(
      () => !dependencies.session.current.isBusy,
      'session restoration',
    );
    final fromHome = bvid == 'home';
    if (fromHome) {
      bool suitableCard(Element element) {
        final widget = element.widget;
        return widget is VideoCard && widget.video.duration.inSeconds >= 120;
      }

      await waitFor(() => _findElement(suitableCard) != null, 'homepage cards');
      final selected = _findElement(suitableCard)?.widget;
      if (selected is! VideoCard) throw StateError('Homepage card is missing');
      bvid = selected.video.id.value;
      selected.onTap();
    } else {
      final context = _findElement(
        (element) => GoRouter.maybeOf(element) != null,
      );
      if (context == null) throw StateError('Production router is missing');
      GoRouter.of(context).go('/video/$bvid');
    }
    await waitFor(() => playing?.media != null, 'DASH source');
    final session = playing;
    if (session == null || session.engine is! MediaKitEngine) {
      throw StateError('Native session is missing');
    }
    final engine = session.engine as MediaKitEngine;
    await waitFor(
      () =>
          engine.inspectDiagnostics().hasDecodedAudio &&
          engine.inspectDiagnostics().hasVideoOutput &&
          session.snapshots.value.phase == PlaybackPhase.playing &&
          !session.snapshots.value.isBuffering,
      'playing decoded audio and video',
    );
    await write({
      'type': 'metadata',
      'bvid': bvid,
      'cid': session.part?.cid,
      'fromHome': fromHome,
      'title': session.detail?.summary.title,
      'signedIn': dependencies.session.current.isSignedIn,
      'copiedPreferences': copiedPreferences,
      'requestedQuality': session.requestedQuality,
      'actualQuality': session.media?.quality,
      'mediaKind': session.media?.kind.name,
      'videoCodec': session.media?.video.codec,
      'audioCodec': session.media?.audio?.codec,
      'opacity': (await dependencies.settings.load()).danmakuOpacity,
      'fontScale': loaded.danmakuFontScale,
      'font': loaded.danmakuFont.name,
      'effect': loaded.danmakuStyle.name,
      'bold': loaded.danmakuBold,
      'area': loaded.danmakuArea,
      'speed': loaded.danmakuSpeed,
      'maxPerSecond': loaded.danmakuMaxPerSecond,
      'maxOnScreen': loaded.danmakuMaxOnScreen,
      'mergeDuplicates': loaded.danmakuMergeDuplicates,
      'filteredKeywordCount': loaded.danmakuBlockedWords.length,
      'controlsMode': loaded.playerControlsMode.name,
      'subtitlesEnabled': loaded.subtitlesEnabled,
      'profile': const bool.fromEnvironment('dart.vm.profile'),
      'release': const bool.fromEnvironment('dart.vm.product'),
    });

    Future<void> measure(String stage, bool fullscreen, bool comments) async {
      checkpoint = '$stage-fullscreen';
      if (dependencies.window.isFullScreen != fullscreen) {
        bool isFullscreenButton(Element element) {
          final widget = element.widget;
          return widget is IconButton &&
              widget.onPressed != null &&
              widget.icon is Icon &&
              (widget.icon as Icon).icon ==
                  (fullscreen ? BiliIcons.fullscreen : Icons.fullscreen_exit);
        }

        var button = _findElement(isFullscreenButton);
        if (button == null) {
          final surfaceTap = _findElement((element) {
            final widget = element.widget;
            return widget is Semantics &&
                widget.properties.label == '视频播放器' &&
                widget.properties.onTap != null;
          })?.widget;
          if (surfaceTap is Semantics) surfaceTap.properties.onTap?.call();
          await waitFor(
            () => _findElement(isFullscreenButton) != null,
            'visible fullscreen control',
          );
          button = _findElement(isFullscreenButton);
        }
        if (button?.widget case final IconButton buttonWidget) {
          buttonWidget.onPressed?.call();
        } else {
          throw StateError('Production fullscreen control is missing');
        }
        await waitFor(
          () => dependencies.window.isFullScreen == fullscreen,
          'fullscreen transition',
        );
      }
      checkpoint = '$stage-seek';
      await panel().ref
          .read(settingsControllerProvider.notifier)
          .setDanmakuEnabled(comments);
      await session.seek(Duration(seconds: (start - 8).clamp(0, 100000)));
      // A seek may still be buffering while playback intent remains true.
      // Toggling based on phase would pause it and invalidate the measurement.
      if (!session.snapshots.value.desiredPlaying) {
        await session.togglePlaying();
      }
      await waitFor(
        () =>
            session.snapshots.value.phase == PlaybackPhase.playing &&
            !session.snapshots.value.isBuffering &&
            !session.snapshots.value.isSeeking,
        'playing after seek',
      );
      await Future<void>.delayed(const Duration(seconds: 8));
      if (comments && repository.segments.isEmpty) {
        throw StateError('Real comment segments were not loaded');
      }
      await write({'type': 'phase-start', 'stage': stage});
      checkpoint = '$stage-sampling';
      final clock = Stopwatch()..start();
      timings.clear();
      for (var tick = 1; tick <= 30; tick++) {
        final until = Duration(seconds: tick) - clock.elapsed;
        if (until > Duration.zero) await Future<void>.delayed(until);
        final snapshot = session.snapshots.value;
        final diagnostic = engine.inspectDiagnostics();
        final native = await engine.inspectNativePlaybackTiming();
        final cache = session.danmaku.rasterStatistics;
        final surface = _findElement(
          (element) =>
              element.widget is VideoSurface &&
              identical((element.widget as VideoSurface).engine, engine),
        );
        final render = surface?.findRenderObject();
        final size = render is RenderBox ? render.size : Size.zero;
        final panelState = panel();
        if (!panelState.mounted) throw StateError('PlaybackPanel unmounted');
        final view = View.of(panelState.context);
        await write({
          'type': 'sample',
          'stage': stage,
          'elapsedMs': clock.elapsedMilliseconds,
          'positionMs': snapshot.position.inMilliseconds,
          'fullscreen': fullscreen,
          'comments': comments,
          'phase': snapshot.phase.name,
          'buffering': snapshot.isBuffering,
          'seeking': snapshot.isSeeking,
          'rate': snapshot.rate,
          'decoded': [diagnostic.videoWidth, diagnostic.videoHeight],
          'output': [diagnostic.outputWidth, diagnostic.outputHeight],
          'surfaceLogical': [size.width, size.height],
          'dpr': view.devicePixelRatio,
          'viewPhysical': [view.physicalSize.width, view.physicalSize.height],
          'hwdec': await engine.inspectHardwareDecoder(),
          'visible': session.danmaku.visibleCount,
          'pending': session.danmaku.pendingCount,
          'droppedComments': session.danmaku.dropped,
          'commentFontScale': session.commentFontScale,
          'imagePaints': cache.imagePaints,
          'cacheHits': cache.cacheHits,
          'rasterBuilds': cache.rasterBuilds,
          'directPaints': cache.directPaints,
          'rasterBytes': session.danmaku.textRasterBytes,
          'dartFrames': timings.length,
          'uiUs': timings.map((f) => f.buildDuration.inMicroseconds).toList(),
          'rasterUs': timings
              .map((f) => f.rasterDuration.inMicroseconds)
              .toList(),
          'frameDrops': native.frameDrops,
          'decoderDrops': native.decoderDrops,
          'avsyncSeconds': native.avsyncSeconds,
          'errors': errors,
        });
        timings.clear();
      }
      await write({
        'type': 'phase-end',
        'stage': stage,
        'elapsedMs': clock.elapsedMilliseconds,
      });
    }

    await measure('inline-off', false, false);
    await measure('inline-on', false, true);
    await measure('fullscreen-off', true, false);
    await measure('fullscreen-on', true, true);
    await write({
      'type': 'comments-summary',
      'segments': repository.segments
          .map(
            (segment) => {
              'segment': segment.$1,
              'count': segment.$2.length,
              'sampleCount': segment.$2
                  .where(
                    (c) =>
                        c.position.inSeconds >= start &&
                        c.position.inSeconds < start + 30,
                  )
                  .length,
              'modes': {
                for (final mode in [1, 4, 5])
                  '$mode': segment.$2
                      .where(
                        (c) =>
                            c.mode == mode &&
                            c.position.inSeconds >= start &&
                            c.position.inSeconds < start + 30,
                      )
                      .length,
              },
            },
          )
          .toList(),
    });
    if (errors != 0) throw StateError('Flutter errors occurred');
  } catch (error) {
    final reason =
        error is StateError &&
            (error.message.toString().startsWith('Production fullscreen') ||
                error.message.toString().startsWith(
                  'Probe condition timed out:',
                ))
        ? error.message.toString()
        : error.runtimeType.toString();
    await write({
      'type': 'failed',
      'checkpoint': checkpoint,
      'reason': reason,
      'errors': errors,
    });
    exitCode = 1;
  } finally {
    runApp(const SizedBox.shrink());
    await WidgetsBinding.instance.endOfFrame;
    SchedulerBinding.instance.removeTimingsCallback(collect);
    await manager.close();
    await dependencies.close();
  }
  exit(exitCode);
}

Element? _findElement(bool Function(Element) predicate) {
  Element? found;
  void visit(Element element) {
    if (found != null) return;
    if (predicate(element)) {
      found = element;
    } else {
      element.visitChildElements(visit);
    }
  }

  final root = WidgetsBinding.instance.rootElement;
  if (root != null) visit(root);
  return found;
}

final class _MemoryCredentials implements CredentialStore {
  _MemoryCredentials(this.value);
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async => value = next;
  @override
  Future<void> delete() async => value = null;
}

final class _InertProgress implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;
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

final class _ObservedRepository extends ApiPlaybackRepository {
  _ObservedRepository(AppDependencies dependencies)
    : super(
        dependencies.api,
        dependencies.requests,
        cdnPreference: () async =>
            (await dependencies.settings.load()).mediaCdn,
        imageDimensions: dependencies.images.dimensions,
      );
  final segments = <(int, List<TimedComment>)>[];
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async {
    final result = await super.comments(
      cid,
      segment,
      cancellation: cancellation,
    );
    segments.add((segment, result));
    return result;
  }
}
