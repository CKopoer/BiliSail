import 'dart:async';

import 'package:flutter/rendering.dart';
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
  bool _checkScheduled = false;
  bool _retryScheduled = false;
  int _attempt = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active =
        TickerMode.valuesOf(context).enabled &&
        WorkspaceActivity.isActive(context);
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
      position.removeListener(_scheduleVisibilityCheck);
    }
    for (final position in positions.difference(_positions)) {
      position.addListener(_scheduleVisibilityCheck);
    }
    _positions
      ..clear()
      ..addAll(positions);
  }

  void _scheduleVisibilityCheck() {
    if (_checkScheduled || !mounted) return;
    _checkScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkScheduled = false;
      if (!mounted) return;
      final box = context.findRenderObject();
      var visible = _active && box is RenderBox && box.hasSize;
      if (visible) {
        // Eager Wrap/Column lists still lay out offscreen children. Admit their
        // images only when they intersect a viewport, with 160 logical pixels
        // of prefetch. Check all ancestors for nested scrollable lists.
        RenderObject? ancestor = box.parent;
        while (ancestor != null) {
          if (ancestor is RenderAbstractViewport) {
            final bounds = MatrixUtils.transformRect(
              box.getTransformTo(ancestor),
              // An intrinsic-sized image may have no area until its first
              // frame. Its origin still decides whether loading can begin.
              box.paintBounds.isEmpty
                  ? Rect.fromLTWH(
                      box.paintBounds.left,
                      box.paintBounds.top,
                      1,
                      1,
                    )
                  : box.paintBounds,
            );
            if (!bounds.overlaps(ancestor.paintBounds.inflate(160))) {
              visible = false;
              break;
            }
          }
          ancestor = ancestor.parent;
        }
      }
      if (visible != _visible) {
        if (!visible) _stopWaiting();
        setState(() => _visible = visible);
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
      setState(() => ++_attempt);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  Widget _placeholder(BuildContext context) {
    final child = SizedBox(width: widget.width, height: widget.height);
    return widget.frameBuilder?.call(context, child, null, false) ?? child;
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
      return widget.errorBuilder?.call(
            context,
            const ImageLoadCancelled(),
            StackTrace.empty,
          ) ??
          const SizedBox.shrink();
    }
    return _ImageViewportProbe(
      onLayout: _scheduleVisibilityCheck,
      child: !_visible || !_active
          ? _placeholder(context)
          : Image(
              key: ValueKey(_attempt),
              image: cache == null || !ImageByteCache.isPublicImageUri(uri)
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
                    ),
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
              frameBuilder: widget.frameBuilder,
              gaplessPlayback: true,
            ),
    );
  }

  @override
  void dispose() {
    for (final position in _positions) {
      position.removeListener(_scheduleVisibilityCheck);
    }
    _stopWaiting();
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
