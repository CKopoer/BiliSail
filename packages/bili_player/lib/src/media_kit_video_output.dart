import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_contract.dart';
import 'android_video_viewport.dart';
import 'background_playback_frame.dart';
import 'native_video_surface.dart';
import 'native_hdr_output.dart';
import 'native_player_properties.dart';
import 'video_composition.dart';
import 'video_decoder_configuration.dart';

/// Owns the current media-kit output without issuing playback commands.
final class MediaKitVideoOutput
    implements
        FlutterVideoOutput,
        VideoFrameReadiness,
        NativeVideoFrameCapture {
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
  VoidCallback? _refreshReadiness;
  bool _selectingHdr = false;
  bool _appleTextureMapped = false;

  Future<void> get videoFramePresented =>
      usesAppleMetalOutput && hasNativeSurface && _sourceFrame != null
      ? _sourceFrame!.future
      : _presentation ?? Future.error(StateError('No video output is bound.'));

  @override
  ValueListenable<bool> get frameReady => _frameReady;

  void _observeFrameReadiness() {
    final revision = ++_readinessRevision;
    for (final cleanup in _readinessCleanup) {
      cleanup();
    }
    _readinessCleanup.clear();
    _presentation = null;
    _refreshReadiness = null;
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
      if (usesAppleMetalOutput) {
        if (_hdr.value != null) {
          return hasNativeSurface &&
              !_selectingHdr &&
              _sourceFrame?.isCompleted == true;
        }
        if (_hdrDolby && _hdrProfile != '8' && !_appleTextureMapped) {
          return false;
        }
      }
      return rendered &&
          !_selectingHdr &&
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

    _refreshReadiness = update;
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
    // The SDK reports a sized texture. The current source's playback restart
    // and decoded frame are also required before removing the presentation mask.
    final presentation = Platform.isAndroid
        ? _viewportChannel.invokeMethod<void>('BiliSail.WaitForFrame', {
            'handle': controller.player.nativeHandle.toString(),
            'generation': _sourceGeneration.toString(),
          })
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
  bool _androidGpuNext = false;
  final _hdr = ValueNotifier<NativeHdrOutput?>(null);
  final _appleLayerVisible = ValueNotifier(false);
  Future<void>? _hdrAttempt;
  Timer? _hdrDisplayTimer;
  bool _hdrRetired = false;
  bool _hdrDolby = false;
  String _hdrProfile = '';
  bool _hdrSource = false;
  ({int view, String? transfer})? _hdrDisplay;
  int? _viewId;

  bool get hasNativeSurface => _hdr.value?.verified == true;
  bool get hasHdrOutput => hasNativeSurface && _hdr.value?.transfer != 'srgb';
  bool get hasHdrSource => _hdrSource;

  @override
  Future<ui.Image?>? captureNativeFrame() {
    final hdr = _hdr.value;
    final player = _player;
    if (hdr == null || player == null) return null;
    return _captureHdrFrame(player, hdr.dimensions);
  }

  Future<ui.Image?> _captureHdrFrame(
    mk.Player player,
    VideoDimensions size,
  ) async {
    // The SDK captures the decoded image before resizing. Bound that transient
    // allocation as well as the 1080p frame retained across the source change.
    if (size.width * size.height > 4096 * 2304) return null;
    final bytes = await player.screenshot();
    if (bytes == null || _disposed) return null;
    final scale = math.min(
      1.0,
      math.min(1920 / size.width, 1080 / size.height),
    );
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: math.max(1, (size.width * scale).round()),
      targetHeight: math.max(1, (size.height * scale).round()),
      allowUpscaling: false,
    );
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  }

  void identifyHdrSource({required bool hinted}) {
    final player = _player;
    if ((!Platform.isAndroid && !Platform.isWindows && !usesAppleMetalOutput) ||
        player == null ||
        _hdrRetired ||
        _disposed) {
      return;
    }
    final profile = player.getProperty(
      'current-tracks/video/dolby-vision-profile',
    );
    final matrix = player.getProperty('video-params/colormatrix');
    _hdrProfile = profile;
    _hdrSource = isNativeHdrSource(
      profile: profile,
      matrix: matrix,
      transfer: player.getProperty('video-params/gamma'),
      hdrHint: hinted,
    );
    _selectingHdr = _hdrSource && _hdrDisplay == null;
    _hdrDolby = profile == '5' || profile == '8' || matrix == 'dolbyvision';
    if (Platform.isAndroid &&
        _hdrSource &&
        player.getProperty('vo') == 'mediacodec_embed') {
      // Offline sources can lack the HDR hint which normally selects a
      // color-managed texture before opening. Establish the SDR fallback now.
      enableAndroidGpuNext();
      player.setProperty('target-prim', 'bt.709');
      player.setProperty('target-trc', 'srgb');
      player.setProperty('vo', 'gpu-next');
    }
  }

  Future<void> presentHdrIfSupported() async {
    if (!_hdrSource || _hdrRetired) return;
    _watchHdrDisplay();
    try {
      await _refreshHdrDisplay();
    } finally {
      _selectingHdr = false;
      if (!_hdrRetired) _refreshReadiness?.call();
    }
  }

  void _watchHdrDisplay() {
    if (!_hdrSource || _viewportOwner == null || _hdrRetired) return;
    // Moving a window to a display with the same scale, or changing Windows
    // HDR while paused, need not generate a Flutter layout/metrics change.
    _hdrDisplayTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(
        _refreshHdrDisplay().catchError((Object e) {
          debugPrint('Could not refresh HDR display: ${e.runtimeType}');
        }),
      );
    });
  }

  Future<void> _refreshHdrDisplay() {
    final running = _hdrAttempt;
    if (running != null) return running;
    return _hdrAttempt = _selectHdrDisplay().whenComplete(
      () => _hdrAttempt = null,
    );
  }

  Future<void> _selectHdrDisplay() async {
    final player = _player;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final view = _viewId ?? (views.length == 1 ? views.first.viewId : null);
    if (player == null || view == null || _hdrRetired || _disposed) return;
    final transfer = await NativeHdrOutput.supportedTransfer(view);
    if (_hdrRetired || _disposed || !identical(player, _player)) return;
    final display = (view: view, transfer: transfer);
    if (display == _hdrDisplay) return;
    final size = nativeVideoSurfaceDimensions(player.getProperty) ?? dimensions;
    if (size == null || size.width < 2 || size.height < 2) return;
    _hdrDisplay = display;
    final old = _hdr.value;
    if (usesAppleMetalOutput && (old != null || transfer != null)) {
      _frameReady.value = false;
    }
    if (old != null) {
      try {
        await old.restore(player);
      } finally {
        _hdr.value = null;
      }
    }
    if (transfer != null && !_hdrRetired) {
      Future<NativeHdrOutput?> open(String targetTransfer) =>
          NativeHdrOutput.tryOpen(
            player,
            size,
            view,
            targetTransfer,
            dolby: _hdrDolby,
            profile: _hdrProfile,
            mountAppleLayer: (target) {
              _appleLayerVisible.value = false;
              _hdr.value = target;
            },
            showNegotiatedAppleLayer: () => _appleLayerVisible.value = true,
          );
      _hdr.value = await open(transfer);
      if (usesAppleMetalOutput &&
          transfer == 'pq' &&
          _hdr.value == null &&
          !_hdrRetired) {
        _hdr.value = await open('srgb');
      }
    }
    if (usesAppleMetalOutput && !_hdrRetired) {
      if (_hdr.value == null) _appleLayerVisible.value = false;
      _refreshReadiness?.call();
    }
  }

  Future<void> retireHdr() async {
    _hdrRetired = true;
    _hdrDisplayTimer?.cancel();
    try {
      await _hdrAttempt;
    } on Object {
      // A failed promotion must not prevent releasing the native player.
    }
  }

  Future<void> releaseHdrOutput() async {
    final output = _hdr.value;
    _hdr.value = null;
    if (output != null) await output.release();
  }

  Future<void> _androidSurfaceSize = Future.value();
  bool _androidSurfaceSizeFailed = false;
  int _androidSurfaceRevision = 0;
  AndroidVideoSurfaceSizer? _androidViewportSizer;

  bool get _usesAndroidViewport =>
      Platform.isAndroid &&
      limitAndroidOutputToViewport &&
      _hdr.value == null &&
      !_androidGpuNext;

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

  void enableAndroidGpuNext() {
    _androidGpuNext = true;
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
        .invokeMethod<void>('VideoOutputManager.SetSurfaceSize', {
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
    if (_hdr.value case final target?) return target.dimensions;
    final rect = _controller.value?.rect.value;
    return rect == null
        ? null
        : VideoDimensions(rect.width.toInt(), rect.height.toInt());
  }

  bool get hasVideoOutput {
    final size = dimensions;
    // A new controller publishes its placeholder texture before this source
    // decodes. A retained texture can also still contain the previous source.
    return _sourceFrame?.isCompleted == true &&
        _controller.value?.id.value != null &&
        size != null &&
        size.width > 0 &&
        size.height > 0;
  }

  Future<void> waitForDecodedOutput() async {
    final controller = _controller.value;
    if (controller == null) {
      throw StateError('No video output is bound.');
    }
    // Predidit completes its Android "first frame" on a dimensions change.
    // A SurfaceTexture pre-sized to the decoded dimensions skips that event.
    // Presentation waits separately for this generation's consumed buffer.
    if (!Platform.isAndroid && !(usesAppleMetalOutput && hasNativeSurface)) {
      await controller.waitUntilFirstFrameRendered;
    }
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
    final existing = _controller.value;
    final controller =
        existing ??
        mkv.VideoController(
          player,
          configuration: videoDecoderConfiguration(
            isAndroid: Platform.isAndroid,
            decoding: decoding,
            androidOutput: androidOutput,
            usesDolbyVisionRenderer: () => _androidGpuNext,
          ),
        );
    WidgetsBinding.instance.ensureVisualUpdate();
    if (existing == null) {
      // media_kit creates its platform controller from a post-frame callback.
      requestBackgroundPlaybackFrame();
    }
    await controller.platform.future;
    if (_disposed ||
        revision != _bindingRevision ||
        !identical(_player, player)) {
      return;
    }
    if (Platform.isAndroid) {
      await _viewportChannel.invokeMethod<void>('BiliSail.BeginFrames', {
        'handle': player.nativeHandle.toString(),
        'generation': generation.toString(),
      });
      // Idle VO dimensions must not size a newly loaded source.
      await player.setPropertyAsync('force-window', 'no');
      if (await player.getPropertyAsync('force-window') != 'no') {
        throw StateError(
          'The native backend rejected idle video output policy.',
        );
      }
      if (_disposed ||
          revision != _bindingRevision ||
          !identical(_player, player)) {
        return;
      }
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
    if (Platform.isAndroid && _androidGpuNext && dimensions != null) {
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
              .invokeMethod<void>('VideoOutputManager.SetSurfaceSize', {
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
    // The Predidit desktop controller applies decoded dimensions itself.
    // Reapply a fitted viewport when that source size changes.
    if (Platform.isWindows && controller != null) _updateViewportCap();
  }

  void advanceGeneration(int generation) {
    _sourceGeneration = generation;
    _viewportRevision++;
  }

  void confirmSourceFrame({bool appleTextureMapped = false}) {
    _appleTextureMapped = appleTextureMapped;
    final frame = _sourceFrame;
    if (frame != null && !frame.isCompleted) frame.complete();
    if (usesAppleMetalOutput && hasNativeSurface) _refreshReadiness?.call();
  }

  void resetSource() {
    _appleTextureMapped = false;
    _hdrDolby = false;
    _hdrSource = false;
    _selectingHdr = false;
    _hdrDisplay = null;
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
    _androidGpuNext = false;
    _androidSurfaceSize = Future.value();
    _androidSurfaceSizeFailed = false;
    _androidSurfaceRevision++;
  }

  void cancelPendingViewport() => _viewportShrinkTimer?.cancel();

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _hdrDisplayTimer?.cancel();
    cancelPendingViewport();
    clearPlayer();
    _frameReady.dispose();
    _appleLayerVisible.dispose();
    _hdr.dispose();
    _controller.dispose();
  }

  @override
  Widget buildVideoSurface() => ValueListenableBuilder<mkv.VideoController?>(
    valueListenable: _controller,
    builder: (context, controller, _) {
      final view = View.of(context).viewId;
      if (view != _viewId) {
        _viewId = view;
        if (_hdrSource && !_selectingHdr && !_hdrRetired) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_viewId == view && !_hdrRetired && !_disposed) {
              unawaited(presentHdrIfSupported());
            }
          });
        }
      }
      return controller == null
          ? const ColoredBox(color: Color(0xFF000000))
          // The backend is a visual layer. Its built-in InteractiveViewer must
          // not consume wheel signals or gestures owned by the host controls.
          : ValueListenableBuilder<bool>(
              valueListenable: _frameReady,
              child: ValueListenableBuilder<NativeHdrOutput?>(
                valueListenable: _hdr,
                builder: (_, hdr, texture) {
                  if (hdr == null) return texture!;
                  // A new window may be built before its native plane is bound.
                  if (hdr.viewId != view) {
                    return const ColoredBox(color: Color(0xff000000));
                  }
                  return hdr.build();
                },
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
              ),
              builder: (_, ready, child) => usesAppleMetalOutput
                  ? ValueListenableBuilder<bool>(
                      valueListenable: _appleLayerVisible,
                      child: child,
                      builder: (_, visible, surface) => Stack(
                        fit: StackFit.expand,
                        children: [
                          ?surface,
                          if (!ready && !visible)
                            const ColoredBox(color: Color(0xff000000)),
                        ],
                      ),
                    )
                  : _VideoFrameMask(
                      key: const ValueKey('video-first-frame-mask'),
                      ready: ready,
                      child: child,
                    ),
            );
    },
  );

  @override
  void attach(Object owner) {
    if ((!Platform.isWindows && !Platform.isAndroid && !usesAppleMetalOutput) ||
        _disposed) {
      return;
    }
    _viewportOwner = owner;
    _watchHdrDisplay();
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
    _hdrDisplayTimer?.cancel();
    _hdrDisplayTimer = null;
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
      if (_disposed ||
          generation != _sourceGeneration ||
          revision != _viewportRevision ||
          !identical(_player, player) ||
          !identical(_controller.value, controller)) {
        return;
      }
      // Native setSize takes an exact output size. Fit the decoded picture
      // inside our rounded cap so rounding cannot change its aspect ratio.
      final source = _videoDimensions;
      final width = cap.width;
      final height = cap.height;
      if (source == null || width == null || height == null) {
        await controller.setSize().timeout(deadline);
      } else {
        final scale = math.min(
          1.0,
          math.min(width / source.width, height / source.height),
        );
        await controller
            .setSize(
              width: math.max(1, (source.width * scale).round()),
              height: math.max(1, (source.height * scale).round()),
            )
            .timeout(deadline);
      }
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
