import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_contract.dart';
import 'android_video_viewport.dart';
import 'native_video_surface.dart';
import 'native_player_properties.dart';
import 'video_composition.dart';
import 'video_decoder_configuration.dart';

/// Owns the current media-kit output without issuing playback commands.
final class MediaKitVideoOutput
    implements FlutterVideoOutput, VideoFrameReadiness {
  MediaKitVideoOutput({bool? limitAndroidOutputToViewport})
    : limitAndroidOutputToViewport =
          limitAndroidOutputToViewport ??
          const bool.fromEnvironment('BILISAIL_ANDROID_VIEWPORT') {
    _controller.addListener(_observeFrameReadiness);
  }

  /// Keep this candidate opt-in until device resize/color acceptance completes.
  final bool limitAndroidOutputToViewport;

  final ValueNotifier<mkv.VideoController?> _controller = ValueNotifier(null);
  final ValueNotifier<bool> _frameReady = ValueNotifier(false);
  final List<VoidCallback> _readinessCleanup = [];
  int _readinessRevision = 0;
  Future<void>? _presentation;
  Completer<void>? _sourceFrame;

  Future<void> get videoFramePresented =>
      _presentation ?? Future.error(StateError('No video output is bound.'));

  @override
  ValueListenable<bool> get frameReady => _frameReady;

  void _observeFrameReadiness() {
    final revision = ++_readinessRevision;
    for (final cleanup in _readinessCleanup) {
      cleanup();
    }
    _readinessCleanup.clear();
    _presentation = null;
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
      if (controller.rect.value case final rect?
          when rect.width > 1 && rect.height > 1) {
        _updateAndroidViewport();
      }
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
    // Android's SDK signal also finishes paused preparation. Presentation
    // must wait for a sized video buffer without blocking that preparation.
    final presentation = Platform.isAndroid
        ? _viewportChannel.invokeMethod<void>(
            'VideoOutputManager.WaitForVideoFrame',
            {'handle': controller.player.nativeHandle.toString()},
          )
        : controller.waitUntilFirstFrameRendered;
    final sourceFrame = _sourceFrame;
    final currentPresentation = presentation.then((_) => sourceFrame?.future);
    _presentation = currentPresentation;
    unawaited(
      currentPresentation.then(
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
  bool _androidDolbyVision = false;
  Future<void> _androidSurfaceSize = Future.value();
  bool _androidSurfaceSizeFailed = false;
  int _androidSurfaceRevision = 0;
  AndroidVideoSurfaceSizer? _androidViewportSizer;

  bool get _usesAndroidViewport =>
      Platform.isAndroid &&
      limitAndroidOutputToViewport &&
      !_androidDolbyVision;

  VideoDimensions _androidTarget(VideoDimensions source) {
    if (!_usesAndroidViewport) return source;
    final layout = _viewportLayout;
    if (layout == null) return source;
    return androidVideoViewport(
      source,
      physicalWidth: layout.width * layout.dpr,
      physicalHeight: layout.height * layout.dpr,
    );
  }

  void _updateAndroidViewport() {
    if (!_usesAndroidViewport || _viewportOwner == null) return;
    final source = _videoDimensions;
    final player = _player;
    final sizer = _androidViewportSizer;
    if (source == null || player == null || sizer == null) return;
    final target = _androidTarget(source);
    // The pinned controller restores decoded-size buffers on videoParams.
    // Its final rect notification follows that write. Repair both sizes here;
    // our own VO resize can notify again, so first check the native value.
    final matches =
        player.getProperty('android-surface-size') ==
        '${target.width}x${target.height}';
    if (matches && sizer.applied == target) return;
    _androidSurfaceSizeFailed = false;
    _androidSurfaceSize = sizer.request(target, force: !matches).catchError((
      Object error,
    ) {
      if (identical(_androidViewportSizer, sizer)) {
        _androidSurfaceSizeFailed = true;
        debugPrint('Android video viewport failed: ${error.runtimeType}');
      }
    });
  }

  void enableAndroidDolbyVision() {
    _androidDolbyVision = true;
    _androidViewportSizer?.invalidate();
    _androidViewportSizer = null;
  }

  Future<void> prepareAndroidSurface(String Function(String) read) async {
    if (!Platform.isAndroid) return;
    final player = _player;
    final revision = _bindingRevision;
    final dimensions = nativeVideoSurfaceDimensions(read);
    if (_disposed || player == null || dimensions == null) return;
    await _sizeAndroidSurface(player, _androidTarget(dimensions), revision);
  }

  Future<void> _sizeAndroidSurface(
    mk.Player player,
    VideoDimensions dimensions,
    int revision, {
    bool viewport = false,
  }) async {
    final owner = _viewportOwner;
    bool viewportCurrent() {
      final source = _videoDimensions;
      return _usesAndroidViewport &&
          identical(owner, _viewportOwner) &&
          source != null &&
          _androidTarget(source) == dimensions;
    }

    if (viewport && !viewportCurrent()) return;
    // Android attaches the Surface before MediaCodec is created. Its default
    // 1x1 buffer would turn the paused first frame into a stretched solid color.
    // Initial binding sizes the surface before loading; track discovery refines
    // it while presentation is still gated by the current source's readiness.
    await _viewportChannel
        .invokeMethod<void>('VideoOutputManager.SetSurfaceTextureSize', {
          'handle': player.nativeHandle.toString(),
          'width': dimensions.width.toString(),
          'height': dimensions.height.toString(),
        })
        .timeout(const Duration(seconds: 2));
    if (_disposed ||
        revision != _bindingRevision ||
        (viewport && !viewportCurrent()) ||
        !identical(_player, player)) {
      return;
    }
    player.setProperty(
      'android-surface-size',
      '${dimensions.width}x${dimensions.height}',
    );
    if (viewport &&
        player.getProperty('android-surface-size') !=
            '${dimensions.width}x${dimensions.height}') {
      throw StateError(
        'The native backend rejected the Android viewport size.',
      );
    }
  }

  VideoDimensions? get dimensions {
    if (_androidViewportSizer?.applied case final size?
        when _usesAndroidViewport) {
      return size;
    }
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

  Future<void> get firstFrameRendered async {
    final controller = _controller.value;
    if (controller == null) {
      throw StateError('No video output is bound.');
    }
    await controller.waitUntilFirstFrameRendered;
    Future<void> pending;
    do {
      pending = _androidSurfaceSize;
      await pending;
    } while (!identical(pending, _androidSurfaceSize));
    if (_androidSurfaceSizeFailed) {
      throw StateError('Android Dolby Vision surface sizing failed.');
    }
  }

  int _bindingRevision = 0;

  Future<void> bindPlayer(
    mk.Player player, {
    required int generation,
    required VideoDecodingMode decoding,
    AndroidVideoOutputMode androidOutput =
        AndroidVideoOutputMode.renderedTexture,
  }) async {
    if (_disposed) throw StateError('Video output is disposed.');
    _player = player;
    _sourceGeneration = generation;
    final revision = ++_bindingRevision;
    _androidViewportSizer?.invalidate();
    _androidViewportSizer = _usesAndroidViewport
        ? AndroidVideoSurfaceSizer(
            isCurrent: () =>
                !_disposed &&
                revision == _bindingRevision &&
                identical(_player, player),
            apply: (size) =>
                _sizeAndroidSurface(player, size, revision, viewport: true),
          )
        : null;
    final controller =
        _controller.value ??
        mkv.VideoController(
          player,
          configuration: videoDecoderConfiguration(
            isAndroid: Platform.isAndroid,
            decoding: decoding,
            androidOutput: androidOutput,
            usesDolbyVisionRenderer: () => _androidDolbyVision,
          ),
        );
    WidgetsBinding.instance.ensureVisualUpdate();
    await controller.platform.future;
    if (_disposed ||
        revision != _bindingRevision ||
        !identical(_player, player)) {
      return;
    }
    if (Platform.isAndroid) {
      // Size SurfaceTexture before the SDK attaches it to the decoder. Track
      // discovery is too late for the GPU's initial buffer while paused.
      final layout = _viewportLayout;
      final viewSize =
          WidgetsBinding.instance.platformDispatcher.implicitView?.physicalSize;
      int pixels(double? value, int fallback) =>
          value != null && value.isFinite && value > 1
          ? value.ceil().clamp(2, 8192)
          : fallback;
      final width = pixels(
        layout == null ? viewSize?.width : layout.width * layout.dpr,
        640,
      );
      final height = pixels(
        layout == null ? viewSize?.height : layout.height * layout.dpr,
        360,
      );
      await _sizeAndroidSurface(
        player,
        VideoDimensions(width, height),
        revision,
      );
      if (_disposed ||
          revision != _bindingRevision ||
          !identical(_player, player)) {
        return;
      }
    }
    final reused = identical(_controller.value, controller);
    _controller.value = controller;
    if (reused) _observeFrameReadiness();
    _updateDecodedSize();
    final cap = _requestedViewport;
    if (Platform.isWindows && cap != null) _commitViewport(cap);
    // A preview can initialize before mounting a surface. Ensure an otherwise
    // idle window presents the newly bound texture and readiness callbacks.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void updateVideoDimensions(VideoDimensions? dimensions) {
    if (_videoDimensions == dimensions) return;
    _videoDimensions = dimensions;
    _updateDecodedSize();
    _updateViewportCap();
  }

  void _updateDecodedSize() {
    _updateAndroidViewport();
    final controller = _controller.value;
    final dimensions = _videoDimensions;
    if (Platform.isAndroid && _androidDolbyVision && dimensions != null) {
      final player = _player;
      if (player == null) return;
      final revision = _bindingRevision;
      final sizeRevision = ++_androidSurfaceRevision;
      bool current() =>
          !_disposed &&
          revision == _bindingRevision &&
          sizeRevision == _androidSurfaceRevision &&
          identical(_player, player);
      _androidSurfaceSizeFailed = false;
      _androidSurfaceSize = () async {
        try {
          await _viewportChannel
              .invokeMethod<void>('VideoOutputManager.SetSurfaceTextureSize', {
                'handle': player.nativeHandle.toString(),
                'width': dimensions.width.toString(),
                'height': dimensions.height.toString(),
              })
              .timeout(const Duration(seconds: 2));
          if (!current()) return;
          player.setProperty(
            'android-surface-size',
            '${dimensions.width}x${dimensions.height}',
          );
        } on Object catch (error) {
          if (current()) {
            _androidSurfaceSizeFailed = true;
            debugPrint('Android video size failed: ${error.runtimeType}');
          }
        }
      }();
      return;
    }
    if (!Platform.isWindows || controller == null || dimensions == null) return;
    // PiliPlus's controller does not forward player size events. Our native
    // viewport patch deliberately avoids synchronous mpv reads on this thread.
    final result = controller.setSize(
      width: dimensions.width,
      height: dimensions.height,
    );
    unawaited(
      result.catchError((Object error) {
        debugPrint('Windows decoded video size failed: ${error.runtimeType}');
      }),
    );
  }

  void advanceGeneration(int generation) {
    _sourceGeneration = generation;
    _viewportRevision++;
  }

  void confirmSourceFrame() {
    final frame = _sourceFrame;
    if (frame != null && !frame.isCompleted) frame.complete();
  }

  void resetSource() {
    _sourceFrame = Completer<void>();
    _videoDimensions = null;
    _frameReady.value = false;
    _presentation = null;
    _viewportRevision++;
    cancelPendingViewport();
    _observeFrameReadiness();
  }

  void clearPlayer() {
    _androidViewportSizer?.invalidate();
    _androidViewportSizer = null;
    _bindingRevision++;
    _sourceGeneration++;
    _viewportRevision++;
    _controller.value = null;
    _sourceFrame = null;
    _player = null;
    _videoDimensions = null;
    _androidDolbyVision = false;
    _androidSurfaceSize = Future.value();
    _androidSurfaceSizeFailed = false;
    _androidSurfaceRevision++;
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
        // The backend is a visual layer. Its built-in InteractiveViewer must
        // not consume wheel signals or gestures owned by the host controls.
        : ValueListenableBuilder<bool>(
            valueListenable: _frameReady,
            child: IgnorePointer(
              child: mkv.Video(
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
            ),
            builder: (_, ready, child) => _VideoFrameMask(
              key: const ValueKey('video-first-frame-mask'),
              ready: ready,
              child: child,
            ),
          ),
  );

  @override
  void attach(Object owner) {
    if ((!Platform.isWindows && !Platform.isAndroid) || _disposed) return;
    _viewportOwner = owner;
    _viewportLayout = null;
    _viewportShrinkTimer?.cancel();
    _androidViewportSizer?.invalidate();
    // An inline surface may have left a small cap. Remove it immediately when
    // a new surface claims the same player, before its first layout callback.
    if (Platform.isWindows) {
      _requestViewport((width: null, height: null), force: true);
    }
  }

  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    if ((!Platform.isWindows && !Platform.isAndroid) ||
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
    _androidViewportSizer?.invalidate();
    _viewportRevision++;
  }

  void _updateViewportCap() {
    if (_usesAndroidViewport) {
      _updateAndroidViewport();
      return;
    }
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
      final handle = player.nativeHandle;
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

/// Consume native buffers while hiding their uninitialized RGB contents. An
/// opaque layer above Texture can prevent buffer consumption and stall paused
/// startup. The filter is removed from painting as soon as the frame is ready.
final class _VideoFrameMask extends SingleChildRenderObjectWidget {
  const _VideoFrameMask({super.key, required this.ready, super.child});

  final bool ready;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderVideoFrameMask(ready);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderVideoFrameMask renderObject,
  ) => renderObject.ready = ready;
}

final class _RenderVideoFrameMask extends RenderProxyBox {
  _RenderVideoFrameMask(this._ready);

  bool _ready;
  bool get ready => _ready;
  set ready(bool value) {
    if (_ready == value) return;
    _ready = value;
    markNeedsCompositingBitsUpdate();
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => !_ready && child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_ready) {
      layer = null;
      super.paint(context, offset);
      return;
    }
    layer = context.pushColorFilter(
      offset,
      const ColorFilter.matrix([
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      super.paint,
      oldLayer: layer as ColorFilterLayer?,
    );
  }
}
