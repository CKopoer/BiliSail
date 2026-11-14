import 'dart:io';

import 'package:media_kit/media_kit.dart' as mk;

import 'media_kit_backend.dart';
import 'media_kit_video_output.dart';
import 'native_video_frame_queue.dart';
import 'player_diagnostics.dart';
import 'shared_player_engine.dart';

/// Call at application startup before creating an engine.
void initializePlayerBackend() => mk.MediaKit.ensureInitialized();

/// Fixed mpv entrypoint. Playback decisions live in SharedPlayerEngine.
final class MediaKitEngine extends SharedPlayerEngine {
  static int _nextDiagnosticId = 0;
  factory MediaKitEngine({
    void Function(PlayerDiagnosticEvent)? onDiagnostic,
    bool? experimentalVideoFrameQueue,
    bool? experimentalAndroidViewport,
    int? experimentalAudioAutosync,
  }) {
    if (experimentalAudioAutosync != null &&
        experimentalAudioAutosync != 0 &&
        experimentalAudioAutosync != 30) {
      throw ArgumentError.value(
        experimentalAudioAutosync,
        'experimentalAudioAutosync',
      );
    }
    final queue = resolveVideoFrameQueueEnabled(
      isAndroid: Platform.isAndroid,
      enabledOverride: experimentalVideoFrameQueue,
    );
    late final MediaKitEngine engine;
    final diagnosticId = ++_nextDiagnosticId;
    void report(PlayerDiagnosticEvent event) {
      onDiagnostic?.call(
        event.withContext(
          playerId: diagnosticId,
          diagnostics: event.kind == PlayerDiagnosticKind.openStarted
              ? null
              : engine.inspectDiagnostics(),
          readinessStage: event.kind == PlayerDiagnosticKind.openStarted
              ? null
              : engine._native?.readinessStage,
          sourceKind: event.kind == PlayerDiagnosticKind.openStarted
              ? null
              : engine._native?.diagnosticSourceKind,
        ),
      );
      if (event.kind == PlayerDiagnosticKind.openReady) {
        engine._native?.captureReadyDiagnostics();
      }
    }

    engine = MediaKitEngine._(
      idleVideoOutput: MediaKitVideoOutput(
        limitAndroidOutputToViewport: experimentalAndroidViewport,
      ),
      createBackend: () => MediaKitBackend(
        snapshot: () => engine.currentSnapshot,
        onDiagnostic: onDiagnostic == null ? null : report,
        experimentalVideoFrameQueue: queue,
        experimentalAndroidViewport: experimentalAndroidViewport,
        experimentalAudioAutosync: experimentalAudioAutosync,
      ),
      onDiagnostic: onDiagnostic == null ? null : report,
      experimentalVideoFrameQueue: queue,
      experimentalAudioAutosync: experimentalAudioAutosync,
    );
    return engine;
  }
  MediaKitEngine._({
    required super.createBackend,
    super.onDiagnostic,
    required this.experimentalVideoFrameQueue,
    this.experimentalAudioAutosync,
    required MediaKitVideoOutput idleVideoOutput,
  }) : _idleOutput = idleVideoOutput,
       super(
         seekCoalescingDelay: const Duration(milliseconds: 40),
         initialVideoOutput: idleVideoOutput,
         schemes: {'http', 'https', 'file', if (Platform.isAndroid) 'content'},
       );

  final bool experimentalVideoFrameQueue;
  final int? experimentalAudioAutosync;
  final MediaKitVideoOutput _idleOutput;
  Future<void>? _idleDisposal;
  MediaKitBackend? get _native => activeBackend as MediaKitBackend?;
  bool get videoFrameQueueActive => _native?.videoFrameQueueActive ?? false;
  double get appliedAudioGainDb => _native?.appliedAudioGainDb ?? 0;
  ({int? width, int? height})? get debugRequestedVideoViewport =>
      _native?.debugRequestedVideoViewport ??
      _idleOutput.debugRequestedViewport;
  @override
  Future<void> dispose() =>
      _idleDisposal ??= super.dispose().whenComplete(_idleOutput.dispose);
  PlayerDiagnostics inspectDiagnostics() =>
      _native?.inspectDiagnostics() ??
      PlayerDiagnostics(
        generation: currentSnapshot.generation,
        position: currentSnapshot.position,
        hasDecodedVideo: false,
        hasDecodedAudio: false,
      );
  Future<String?> inspectHardwareDecoder() async =>
      _native?.inspectHardwareDecoder();
  Future<Map<String, Object?>> inspectNativeOutputConfiguration() async =>
      await _native?.inspectNativeOutputConfiguration() ?? const {};
  Future<
    ({
      double? avsyncSeconds,
      int? frameDrops,
      int? decoderDrops,
      double? nativeRate,
      double? audioPositionSeconds,
      double? videoPositionSeconds,
    })
  >
  inspectNativePlaybackTiming({bool includeRateClocks = false}) async =>
      await _native?.inspectNativePlaybackTiming(
        includeRateClocks: includeRateClocks,
      ) ??
      (
        avsyncSeconds: null,
        frameDrops: null,
        decoderDrops: null,
        nativeRate: null,
        audioPositionSeconds: null,
        videoPositionSeconds: null,
      );
  Future<void> replaceAndroidSurfaceForBenchmark(int surface) async {
    final native = _native;
    if (native == null) {
      throw StateError('The surface experiment requires paused playback.');
    }
    await native.replaceAndroidSurfaceForBenchmark(surface);
  }
}
