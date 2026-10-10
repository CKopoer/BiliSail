import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/presentation/app_image_provider.dart';
import '../../core/presentation/workspace_activity.dart';
import '../../core/storage/image_byte_cache.dart';

final class AppImageCacheScope extends InheritedNotifier<AppImageCache> {
  const AppImageCacheScope({
    super.key,
    required AppImageCache cache,
    required super.child,
  }) : super(notifier: cache);

  static AppImageCache? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<AppImageCacheScope>()
      ?.notifier;
}

/// A retained page keeps ready frames while an ancestor horizontal pager moves
/// it offscreen. Its own scroll viewports still release offscreen frames, and
/// image requests still require visibility in every ancestor viewport.
final class AppImagePageViewport extends SingleChildRenderObjectWidget {
  const AppImagePageViewport({super.key, required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAppImagePageViewport();
}

final class _RenderAppImagePageViewport extends RenderProxyBox {}

/// Public covers and avatars share one provider across tabs. No caller headers
/// are accepted, so account credentials cannot leak to CDN image requests.
final class AppNetworkImage extends StatefulWidget {
  const AppNetworkImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit,
    this.alignment = Alignment.center,
    this.errorBuilder,
    this.loadingBuilder,
    this.frameBuilder,
    this.excludeFromSemantics = false,
    this.semanticLabel,
    this.cacheWidth,
    this.cacheHeight,
  });
  final String url;
  final double? width, height;
  final BoxFit? fit;
  final AlignmentGeometry alignment;
  final ImageErrorWidgetBuilder? errorBuilder;
  final ImageLoadingBuilder? loadingBuilder;
  final ImageFrameBuilder? frameBuilder;
  final bool excludeFromSemantics;
  final String? semanticLabel;
  final int? cacheWidth, cacheHeight;

  @override
  State<AppNetworkImage> createState() => _AppNetworkImageState();
}

final class _AppNetworkImageState extends State<AppNetworkImage> {
  final _positions = <ScrollPosition>{};
  StreamSubscription<void>? _capacitySubscription;
  AppImageCache? _waitingCache;
  bool _active = true;
  bool _visible = false;
  bool _visibilityChecked = false;
  bool _checkScheduled = false;
  bool _retryScheduled = false;
  bool _hasFrame = false;
  ImageProvider<Object>? _provider;
  _RetainedImageProvider? _source;
  int _attempt = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wasActive = _active;
    _active =
        TickerMode.valuesOf(context).enabled &&
        WorkspaceActivity.isActive(context);
    if (_active && !wasActive) _visibilityChecked = false;
    // Observe viewport changes without rebuilding the whole list on scroll.
    MediaQuery.maybeSizeOf(context);
    Scrollable.maybeOf(context);
    _syncScrollPositions();
    if (!_active) {
      _visible = false;
      _stopWaiting();
    }
    _scheduleVisibilityCheck();
  }

  @override
  void didUpdateWidget(AppNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncScrollPositions();
    if (oldWidget.url != widget.url ||
        oldWidget.cacheWidth != widget.cacheWidth ||
        oldWidget.cacheHeight != widget.cacheHeight) {
      _stopWaiting();
      _hasFrame = false;
      _provider = null;
      _releaseSource();
      ++_attempt;
    }
    _scheduleVisibilityCheck();
  }

  void _syncScrollPositions() {
    final positions = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        positions.add((element.state as ScrollableState).position);
      }
      return true;
    });
    for (final position in _positions.difference(positions)) {
      position.removeListener(_onScrollChanged);
    }
    for (final position in positions.difference(_positions)) {
      position.addListener(_onScrollChanged);
    }
    _positions
      ..clear()
      ..addAll(positions);
  }

  void _onScrollChanged() {
    // A still-mounted image can return before the post-layout check (notably
    // SingleChildScrollView). Re-admit only decoded frames here; new requests
    // continue to wait for the authoritative check after layout.
    final provider = _provider;
    if (mounted &&
        !_visible &&
        SchedulerBinding.instance.schedulerPhase !=
            SchedulerPhase.persistentCallbacks &&
        provider is AppImageProvider &&
        provider.hasDecodedFrame &&
        _readVisibility().visible) {
      setState(() => _visible = true);
    }
    _scheduleVisibilityCheck();
  }

  ({bool visible, bool visibleInPage}) _readVisibility() {
    final box = context.findRenderObject();
    var visible = _active && box is RenderBox && box.hasSize;
    var visibleInPage = visible;
    if (visible) {
      // Check every ancestor viewport, including nested lists, with the same
      // 160 logical-pixel prefetch range used for new requests.
      RenderObject? ancestor = box.parent;
      var insidePage = true;
      while (ancestor != null) {
        if (ancestor is _RenderAppImagePageViewport) insidePage = false;
        if (ancestor is RenderAbstractViewport) {
          final bounds = MatrixUtils.transformRect(
            box.getTransformTo(ancestor),
            // Intrinsic-sized images can have no area before their first frame.
            box.paintBounds.isEmpty
                ? Rect.fromLTWH(box.paintBounds.left, box.paintBounds.top, 1, 1)
                : box.paintBounds,
          );
          final viewport = ancestor.paintBounds.inflate(160);
          if (!bounds.overlaps(viewport)) visible = false;
          // Keep a ready frame during page swipes, but release it for inner
          // scrolling or outer vertical clipping.
          if (insidePage
              ? !bounds.overlaps(viewport)
              : bounds.bottom <= viewport.top ||
                    bounds.top >= viewport.bottom) {
            visibleInPage = false;
          }
        }
        ancestor = ancestor.parent;
      }
    }
    return (visible: visible, visibleInPage: visibleInPage);
  }

  void _scheduleVisibilityCheck() {
    if (_checkScheduled || !mounted) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final (:visible, :visibleInPage) = _readVisibility();
      _visibilityChecked = true;
      // A cached animation can report an error before frameBuilder runs.
      // Release its admitted stream too, even when only the error is painted.
      final releaseFrame =
          _active &&
          !visibleInPage &&
          (_hasFrame || _source?.hasCachedFrame == true);
      if (visible != _visible || releaseFrame) {
        if (!visible) _stopWaiting();
        setState(() {
          _visible = visible;
          if (releaseFrame) _hasFrame = false;
        });
      }
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _stopWaiting() {
    final subscription = _capacitySubscription;
    _capacitySubscription = null;
    _waitingCache = null;
    if (subscription != null) unawaited(subscription.cancel());
  }

  void _waitForCapacity(AppImageCache cache) {
    if (!_active || !_visible) return;
    if (!identical(cache, _waitingCache)) {
      _stopWaiting();
      _waitingCache = cache;
      _capacitySubscription = cache.bytes.capacityChanges.listen(
        (_) => _retryWhenAvailable(cache),
      );
    }
    // Cover a completion that occurred between admission failure and listening.
    _retryWhenAvailable(cache);
  }

  void _retryWhenAvailable(AppImageCache cache) {
    if (_retryScheduled || !cache.bytes.hasCapacity) return;
    _retryScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _retryScheduled = false;
      if (!mounted ||
          !_active ||
          !_visible ||
          !identical(cache, _waitingCache) ||
          !cache.bytes.hasCapacity) {
        return;
      }
      _stopWaiting();
      // The failed completer was evicted by AppImageProvider. A fresh Image
      // state resolves the same URL again; ordinary rebuilds keep their stream.
      setState(() {
        _hasFrame = false;
        _releaseSource();
        ++_attempt;
      });
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _placeholder(BuildContext context) {
    final child = SizedBox(width: widget.width, height: widget.height);
    return widget.frameBuilder?.call(context, child, null, false) ?? child;
  }

  void _releaseSource() {
    _source?.release();
    _source = null;
  }

  @override
  Widget build(BuildContext context) {
    final cache = AppImageCacheScope.maybeOf(context);
    final source = Uri.tryParse(widget.url);
    final normalized = source != null && source.scheme == 'http'
        ? source.replace(scheme: 'https').toString()
        : widget.url;
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty ||
        uri.host.isEmpty) {
      _provider = null;
      return widget.errorBuilder?.call(
            context,
            const ImageLoadCancelled(),
            StackTrace.empty,
          ) ??
          const SizedBox.shrink();
    }
    final provider = cache == null || !ImageByteCache.isPublicImageUri(uri)
        ? ResizeImage.resizeIfNeeded(
            widget.cacheWidth,
            widget.cacheHeight,
            NetworkImage(
              normalized,
              headers: const {'Referer': 'https://www.bilibili.com/'},
            ),
          )
        : AppImageProvider(
            cache: cache,
            url: normalized,
            cacheWidth: widget.cacheWidth,
            cacheHeight: widget.cacheHeight,
          );
    if (_source case final previous? when previous.provider != provider) {
      _releaseSource();
      _hasFrame = false;
      ++_attempt;
    }
    _provider = provider;
    // Cached pixels can appear in the first build of a lazy-list child. The
    // first layout still releases an offscreen frame, preventing permanent
    // leases outside the viewport or loading any uncached hidden image.
    final cachedFirstFrame =
        _active &&
        !_visibilityChecked &&
        provider is AppImageProvider &&
        provider.hasDecodedFrame;
    final showImage = (_visible && _active) || _hasFrame || cachedFirstFrame;
    final retained = showImage
        ? (_source ??= _RetainedImageProvider(provider))
        : null;
    if (!showImage) _releaseSource();
    return _ImageViewportProbe(
      onLayout: _scheduleVisibilityCheck,
      // A retained page can still be painted by the horizontal pager before
      // its routed selection changes. Keep its ready frame, while TickerMode
      // pauses the stream listener. Offscreen images on active lists still
      // release their frames, so retention is limited to the departing view.
      child: TickerMode(
        enabled: _active,
        child: retained == null
            ? _placeholder(context)
            : _buildImage(retained, cache),
      ),
    );
  }

  Widget _buildImage(_RetainedImageProvider retained, AppImageCache? cache) {
    final image = Image(
      key: ValueKey(_attempt),
      image: retained.image,
      width: widget.width,
      height: widget.height,
      fit: widget.fit,
      alignment: widget.alignment,
      excludeFromSemantics: widget.excludeFromSemantics,
      semanticLabel: widget.semanticLabel,
      errorBuilder: (context, error, stack) {
        if (error is ImageQueueFull && cache != null) {
          _waitForCapacity(cache);
          return _placeholder(context);
        }
        final builder = widget.errorBuilder;
        if (builder != null) return builder(context, error, stack);
        Error.throwWithStackTrace(error, stack ?? StackTrace.current);
      },
      loadingBuilder: widget.loadingBuilder,
      frameBuilder: (context, child, frame, synchronous) {
        _hasFrame = frame != null;
        return widget.frameBuilder?.call(context, child, frame, synchronous) ??
            child;
      },
      gaplessPlayback: true,
    );
    return retained.hasCachedFrame
        ? _CachedStreamImage(key: image.key, image: image, provider: retained)
        : image;
  }

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_onScrollChanged);
    }
    _stopWaiting();
    _releaseSource();
    super.dispose();
  }
}

/// Image resolves again when TickerMode changes. Reuse this widget's admitted
/// stream even with caching disabled, so hiding a ready frame cannot initiate
/// another transfer. The lease ends with the image's viewport/source lifetime.
final class _RetainedImageProvider extends ImageProvider<Object> {
  _RetainedImageProvider(this.provider) {
    final source = provider;
    if (source is AppImageProvider && source.hasDecodedFrame) {
      final stream = source.createStream(ImageConfiguration.empty);
      final completer = stream.completer;
      if (completer != null) {
        _retain(completer);
        _hasCachedFrame = true;
      }
    }
  }

  final ImageProvider<Object> provider;
  final _lease = _ImageStreamLease();
  bool _hasCachedFrame = false;
  bool get hasCachedFrame => _hasCachedFrame;

  // NetworkImage already reuses Flutter's decoded cache. The app provider
  // needs a widget lease because its cache can be explicitly disabled.
  ImageProvider<Object> get image =>
      provider is AppImageProvider ? this : provider;

  @override
  Future<Object> obtainKey(ImageConfiguration configuration) =>
      provider.obtainKey(configuration);

  @override
  ImageStream createStream(ImageConfiguration configuration) {
    final retained = _lease.completer;
    final stream = retained == null
        ? provider.createStream(configuration)
        : (ImageStream()..setCompleter(retained));
    final completer = stream.completer;
    if (completer != null) _retain(completer);
    return stream;
  }

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    Object key,
    ImageErrorListener handleError,
  ) {
    if (stream.completer != null) return;
    final completer = _lease.completer;
    if (completer != null) {
      stream.setCompleter(completer);
      return;
    }
    provider.resolveStreamForKey(configuration, stream, key, handleError);
    final resolved = stream.completer;
    if (resolved != null) _retain(resolved);
  }

  void _retain(ImageStreamCompleter completer) {
    if (identical(completer, _lease.completer)) return;
    release();
    _lease.completer = completer;
    _lease.handle = completer.keepAlive();
  }

  void release() {
    _lease.handle?.dispose();
    _lease.handle = null;
    _lease.completer = null;
  }
}

final class _ImageStreamLease {
  ImageStreamCompleter? completer;
  ImageStreamCompleterHandle? handle;
}

/// Image's implicit ScrollAwareImageProvider cannot see our decoded cache.
/// Only already decoded streams take this path; pending and uncached images
/// keep Flutter's scroll deferral, error and download-progress handling.
final class _CachedStreamImage extends StatefulWidget {
  const _CachedStreamImage({
    super.key,
    required this.image,
    required this.provider,
  });

  final Image image;
  final _RetainedImageProvider provider;

  @override
  State<_CachedStreamImage> createState() => _CachedStreamImageState();
}

final class _CachedStreamImageState extends State<_CachedStreamImage> {
  ImageStream? _stream;
  ImageInfo? _info;
  int? _frame;
  bool _synchronous = false;
  bool _listening = false;
  Object? _error;
  StackTrace? _stack;
  late final _listener = ImageStreamListener(
    _onFrame,
    reportErrors: false,
    onError: (error, stack) => setState(() {
      _error = error;
      _stack = stack;
    }),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(_CachedStreamImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.provider, widget.provider)) _resolve();
  }

  void _resolve() {
    final image = widget.image;
    final next = widget.provider.resolve(
      createLocalImageConfiguration(
        context,
        size: image.width != null && image.height != null
            ? Size(image.width!, image.height!)
            : null,
      ),
    );
    if (_stream?.key != next.key) {
      _stopListening();
      _replaceInfo(null);
      _frame = null;
      _synchronous = false;
      _error = null;
      _stack = null;
      _stream = next;
    }
    if (TickerMode.valuesOf(context).enabled) {
      if (!_listening) {
        _listening = true;
        next.addListener(_listener);
      }
    } else {
      _stopListening();
    }
  }

  void _stopListening() {
    if (_listening) _stream?.removeListener(_listener);
    _listening = false;
  }

  void _replaceInfo(ImageInfo? info) {
    final previous = _info;
    _info = info;
    if (previous != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
    }
  }

  void _onFrame(ImageInfo info, bool synchronous) => setState(() {
    _replaceInfo(info);
    _frame = (_frame ?? -1) + 1;
    _synchronous = _synchronous || synchronous;
    _error = null;
    _stack = null;
  });

  @override
  Widget build(BuildContext context) {
    final image = widget.image;
    if (_error case final error?) {
      return image.errorBuilder?.call(context, error, _stack) ??
          const SizedBox.shrink();
    }
    Widget child = RawImage(
      image: _info?.image,
      width: image.width,
      height: image.height,
      scale: _info?.scale ?? 1,
      fit: image.fit,
      alignment: image.alignment,
      invertColors: MediaQuery.maybeInvertColorsOf(context) ?? false,
      filterQuality: image.filterQuality,
    );
    if (!image.excludeFromSemantics) {
      child = Semantics(
        container: image.semanticLabel != null,
        image: true,
        label: image.semanticLabel ?? '',
        child: child,
      );
    }
    child =
        image.frameBuilder?.call(context, child, _frame, _synchronous) ?? child;
    return image.loadingBuilder?.call(context, child, null) ?? child;
  }

  @override
  void dispose() {
    _stopListening();
    _replaceInfo(null);
    super.dispose();
  }
}

/// Forward intrinsic/dry layout like the original Image. LayoutBuilder would
/// prevent consumers such as rich text and IntrinsicHeight rows from measuring.
final class _ImageViewportProbe extends SingleChildRenderObjectWidget {
  const _ImageViewportProbe({required this.onLayout, required super.child});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderImageViewportProbe(onLayout);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderImageViewportProbe renderObject,
  ) {
    renderObject.onLayout = onLayout;
  }
}

final class _RenderImageViewportProbe extends RenderProxyBox {
  _RenderImageViewportProbe(this.onLayout);
  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}
