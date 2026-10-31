import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_contract.dart';
import 'video_composition.dart';
import 'video_decoder_configuration.dart';

/// Owns the current media-kit output without issuing playback commands.
final class MediaKitVideoOutput
    implements FlutterVideoOutput, VideoFrameReadiness {
  MediaKitVideoOutput() {
    _controller.addListener(_observeFrameReadiness);
  }

  final ValueNotifier<mkv.VideoController?> _controller = ValueNotifier(null);
  final ValueNotifier<bool> _frameReady = ValueNotifier(false);
  final List<VoidCallback> _readinessCleanup = [];
  int _readinessRevision = 0;

  @override
  ValueListenable<bool> get frameReady => _frameReady;

  void _observeFrameReadiness() {
    final revision = ++_readinessRevision;
    for (final cleanup in _readinessCleanup) {
      cleanup();
    }
    _readinessCleanup.clear();
    _frameReady.value = false;
    final controller = _controller.value;
    if (controller == null || _disposed) return;
    var rendered = false;
    var scheduled = false;
    bool isCurrent() => !_disposed && revision == _readinessRevision;
    bool canPresent() {
      final rect = controller.rect.value;
      final state = controller.player.state;
      // Match Video's visibility gate and its mask over the initial 1px texture.
      return rendered &&
          controller.id.value != null &&
          rect != null &&
          rect.width > 0 &&
          rect.height > 0 &&
          (rect.width > 1 || rect.height > 1) &&
          (state.width ?? 0) > 0 &&
          (state.height ?? 0) > 0;
    }

    void update() {
      if (!isCurrent()) return;
      if (!canPresent()) {
        _frameReady.value = false;
        return;
      }
      if (_frameReady.value || scheduled) return;
      scheduled = true;
      // Video consumes asynchronous size notifications in its own state.
      // Let that surface paint before admitting foreground content.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        scheduled = false;
        if (isCurrent() && canPresent()) _frameReady.value = true;
      });
      WidgetsBinding.instance.ensureVisualUpdate();
    }

    controller.id.addListener(update);
    controller.rect.addListener(update);
    final width = controller.player.stream.width.listen((_) => update());
    final height = controller.player.stream.height.listen((_) => update());
    _readinessCleanup.addAll([
      () => controller.id.removeListener(update),
      () => controller.rect.removeListener(update),
      () => unawaited(width.cancel()),
      () => unawaited(height.cancel()),
    ]);
    unawaited(
      controller.waitUntilFirstFrameRendered.then(
        (_) {
          rendered = true;
          update();
        },
        onError: (Object error, StackTrace stack) {
          // The engine handles output failure within its bounded open wait.
          if (isCurrent()) _frameReady.value = false;
        },
      ),
    );
  }

  static const _viewportChannel = MethodChannel(
    'com.alexmercerind/media_kit_video',
  );
  Object? _viewportOwner;
  ({double width, double height, double dpr})? _viewportLayout;
  ({int? width, int? height})? _requestedViewport;
  ({int? width, int? height})? get debugRequestedViewport => _requestedViewport;
  Timer? _viewportShrinkTimer;
  int _viewportRevision = 0;
  bool _viewportFailureLogged = false;
  mk.Player? _player;
  int _sourceGeneration = 0;
  bool _disposed = false;
  VideoDimensions? _videoDimensions;

  VideoDimensions? get dimensions {
    final rect = _controller.value?.rect.value;
    return rect == null
        ? null
        : VideoDimensions(rect.width.toInt(), rect.height.toInt());
  }

  bool get hasVideoOutput {
    final size = dimensions;
    return _controller.value?.id.value != null &&
        size != null &&
        size.width > 0 &&
        size.height > 0;
  }

  Future<void> get firstFrameRendered {
    final controller = _controller.value;
    if (controller == null) {
      return Future.error(StateError('No video output is bound.'));
    }
    return controller.waitUntilFirstFrameRendered;
  }

  void bindPlayer(
    mk.Player player, {
    required int generation,
    required VideoDecodingMode decoding,
  }) {
    if (_disposed) throw StateError('Video output is disposed.');
    _player = player;
    _sourceGeneration = generation;
    final controller = mkv.VideoController(
      player,
      configuration: videoDecoderConfiguration(
        isAndroid: Platform.isAndroid,
        decoding: decoding,
      ),
    );
    // Retain early initialization errors for the engine's bounded output wait.
    controller.platform.future.ignore();
    _controller.value = controller;
    final cap = _requestedViewport;
    if (Platform.isWindows && cap != null) _commitViewport(cap);
    // A preview waits for output before mounting a surface. Initialization is
    // post-frame, so an otherwise idle Flutter window must request that frame.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void updateVideoDimensions(VideoDimensions? dimensions) {
    if (_videoDimensions == dimensions) return;
    _videoDimensions = dimensions;
    _updateViewportCap();
  }

  void advanceGeneration(int generation) {
    _sourceGeneration = generation;
    _viewportRevision++;
  }

  void clearPlayer() {
    _sourceGeneration++;
    _viewportRevision++;
    _controller.value = null;
    _player = null;
  }

  void cancelPendingViewport() => _viewportShrinkTimer?.cancel();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    cancelPendingViewport();
    clearPlayer();
    _frameReady.dispose();
    _controller.dispose();
  }

  @override
  Widget buildVideoSurface() => ValueListenableBuilder<mkv.VideoController?>(
    valueListenable: _controller,
    builder: (context, controller, _) => controller == null
        ? const ColoredBox(color: Color(0xFF000000))
        : mkv.Video(
            // VideoState subscribes to its initial player's dimensions. A
            // same-frame clear/rebind must not retain the old subscriptions.
            key: ObjectKey(controller),
            controller: controller,
            controls: mkv.NoVideoControls,
            // PlaybackSession owns lifecycle and the user's pause intent.
            // The old surface may still be mounted while switching to audio.
            pauseUponEnteringBackgroundMode: false,
            resumeUponEnteringForegroundMode: false,
          ),
  );

  @override
  void attach(Object owner) {
    if (!Platform.isWindows || _disposed) return;
    _viewportOwner = owner;
    _viewportLayout = null;
    _viewportShrinkTimer?.cancel();
    // An inline surface may have left a small cap. Remove it immediately when
    // a new surface claims the same player, before its first layout callback.
    _requestViewport((width: null, height: null), force: true);
  }

  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    if (!Platform.isWindows ||
        _disposed ||
        !identical(_viewportOwner, owner) ||
        !logicalWidth.isFinite ||
        !logicalHeight.isFinite ||
        !devicePixelRatio.isFinite ||
        logicalWidth <= 0 ||
        logicalHeight <= 0 ||
        devicePixelRatio <= 0) {
      return;
    }
    _viewportLayout = (
      width: logicalWidth,
      height: logicalHeight,
      dpr: devicePixelRatio,
    );
    _updateViewportCap();
  }

  @override
  void detach(Object owner) {
    if (!identical(_viewportOwner, owner)) return;
    _viewportOwner = null;
    _viewportLayout = null;
    _viewportShrinkTimer?.cancel();
    _viewportRevision++;
  }

  void _updateViewportCap() {
    final layout = _viewportLayout;
    if (!Platform.isWindows || layout == null || _viewportOwner == null) return;
    final physicalWidth = (layout.width * layout.dpr).ceil().clamp(1, 16384);
    final physicalHeight = (layout.height * layout.dpr).ceil().clamp(1, 16384);
    final source = _videoDimensions;
    var neededWidth = physicalWidth;
    var neededHeight = physicalHeight;
    if (source != null && source.width > 0 && source.height > 0) {
      final scale = math.min(
        1.0,
        math.min(physicalWidth / source.width, physicalHeight / source.height),
      );
      neededWidth = (source.width * scale).ceil();
      neededHeight = (source.height * scale).ceil();
    }
    int roundUp(int value) => ((value + 63) ~/ 64) * 64;
    final cap = (
      width: source == null
          ? roundUp(neededWidth)
          : math.min(source.width, roundUp(neededWidth)),
      height: source == null
          ? roundUp(neededHeight)
          : math.min(source.height, roundUp(neededHeight)),
    );
    _requestViewport(cap);
  }

  void _requestViewport(({int? width, int? height}) cap, {bool force = false}) {
    _viewportShrinkTimer?.cancel();
    final previous = _requestedViewport;
    if (!force && previous == cap) return;
    if (!force &&
        previous?.width != null &&
        previous?.height != null &&
        cap.width != null &&
        cap.height != null &&
        cap.width! <= previous!.width! &&
        cap.height! <= previous.height!) {
      final owner = _viewportOwner;
      _viewportShrinkTimer = Timer(const Duration(milliseconds: 300), () {
        if (identical(_viewportOwner, owner)) _commitViewport(cap);
      });
      return;
    }
    _commitViewport(cap);
  }

  void _commitViewport(({int? width, int? height}) cap) {
    if (_disposed) return;
    _requestedViewport = cap;
    final controller = _controller.value;
    final player = _player;
    if (controller == null || player == null) return;
    final revision = ++_viewportRevision;
    final generation = _sourceGeneration;
    unawaited(_applyViewport(controller, player, generation, cap, revision));
  }

  Future<void> _applyViewport(
    mkv.VideoController controller,
    mk.Player player,
    int generation,
    ({int? width, int? height}) cap,
    int revision,
  ) async {
    try {
      const deadline = Duration(seconds: 5);
      await controller.platform.future.timeout(deadline);
      final handle = await player.handle.timeout(deadline);
      if (_disposed ||
          generation != _sourceGeneration ||
          revision != _viewportRevision ||
          !identical(_player, player) ||
          !identical(_controller.value, controller)) {
        return;
      }
      await _viewportChannel
          .invokeMethod<void>('VideoOutputManager.SetViewportSize', {
            'handle': handle.toString(),
            'width': cap.width?.toString() ?? 'null',
            'height': cap.height?.toString() ?? 'null',
            'revision': revision.toString(),
          })
          .timeout(deadline);
    } on Object catch (error) {
      if (!_viewportFailureLogged) {
        _viewportFailureLogged = true;
        debugPrint(
          'Windows video viewport update failed: ${error.runtimeType}',
        );
      }
    }
  }
}
