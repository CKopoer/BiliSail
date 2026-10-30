import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:bili_player/bili_player.dart';

import '../../core/presentation/workspace_activity.dart';
import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../domain/video.dart';
import '../../features/video/domain/video_card_interactions.dart';
import '../../features/video/application/video_card_preview_playback.dart';
import 'bili_icons.dart';
import 'scroll_aware_hover_region.dart';
import 'video_card_interaction_scope.dart';
import 'video_access_badge.dart';

const _coverHoverScale = 1.05;

/// Desktop cover interaction shared by grid and horizontal video cards.
class VideoCardCover extends StatefulWidget {
  const VideoCardCover({
    super.key,
    required this.video,
    required this.child,
    this.focused = false,
    this.borderRadius = 6,
    this.hovered,
    this.showWatchLaterButton = true,
  });
  final VideoSummary video;
  final Widget child;
  final bool focused;
  final double borderRadius;
  final bool? hovered;
  final bool showWatchLaterButton;
  @override
  State<VideoCardCover> createState() => _VideoCardCoverState();
}

class _VideoCardCoverState extends State<VideoCardCover> {
  bool _pointerHovered = false;
  bool _snapBack = false;
  bool _busy = false;
  bool _active = true;
  VideoCardInteractionScope? _scope;
  int _writeGeneration = 0;
  Object? _coverConfiguration;
  Widget? _cover;

  bool get _hovered => _active && (widget.hovered ?? _pointerHovered);

  bool _ancestorScrolling() {
    // Only inspect on a hover exit to snap the shared cover animation back.
    // Idle/static cards do not subscribe to scroll activity here.
    var scrolling = false;
    context.visitAncestorElements((element) {
      if (element is StatefulElement &&
          element.state is ScrollableState &&
          (element.state as ScrollableState)
              .position
              .isScrollingNotifier
              .value) {
        scrolling = true;
      }
      return !scrolling;
    });
    return scrolling;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = VideoCardInteractionScope.maybeOf(context);
    final active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    if (scope?.interactions != _scope?.interactions || !active) {
      _busy = false;
      ++_writeGeneration;
    }
    _scope = scope;
    _active = active;
  }

  @override
  void didUpdateWidget(VideoCardCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _busy = false;
      ++_writeGeneration;
    }
    if (oldWidget.hovered != widget.hovered) {
      _snapBack = widget.hovered == false && _ancestorScrolling();
    }
  }

  void _hoverCover(bool hovered) {
    if (_pointerHovered == hovered) return;
    setState(() {
      _pointerHovered = hovered;
      _snapBack = !hovered && _ancestorScrolling();
    });
  }

  Future<void> _watchLater() async {
    final scope = _scope;
    if (scope == null || _busy) return;
    final generation = ++_writeGeneration;
    setState(() => _busy = true);
    final result = await scope.interactions.addWatchLater(widget.video.id);
    if (!mounted ||
        generation != _writeGeneration ||
        scope.interactions != _scope?.interactions) {
      return;
    }
    setState(() => _busy = false);
    final message = switch (result) {
      WatchLaterResult.added => '已加入稍后再看',
      WatchLaterResult.alreadyAdded => '已加入稍后再看',
      WatchLaterResult.signIn => '请先登录后再添加稍后再看',
      WatchLaterResult.uncertain => '添加结果暂时无法确认，请在稍后再看列表核对',
      WatchLaterResult.failed => '添加失败，请稍后重试',
      WatchLaterResult.busy || WatchLaterResult.cancelled => null,
    };
    if (message != null && _active) scope.onNotice(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final scope = _scope;
    final hovered = _hovered;
    final showAction =
        widget.showWatchLaterButton &&
        _active &&
        scope != null &&
        (hovered || widget.focused) &&
        widget.video.id.isValid;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final configuration = (
      widget.child,
      widget.video,
      widget.borderRadius,
      widget.hovered == null,
      hovered,
      showAction,
      _snapBack,
      _busy,
      scope?.interactions,
      scope?.hoverPlaybackEnabled,
      showAction ? scope.interactions.isAdded(widget.video.id) : null,
      showAction ? scope.interactions.isUncertain(widget.video.id) : null,
      reduceMotion,
      Theme.of(context),
    );
    final cached = _cover;
    if (cached != null && _coverConfiguration == configuration) return cached;
    _coverConfiguration = configuration;
    // Activity still cancels pending actions/previews above. An idle cover's
    // rendered content does not change when its retained page is hidden.
    final contents = Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (hovered &&
            scope != null &&
            scope.hoverPlaybackEnabled &&
            widget.video.id.isValid)
          _VideoCardHoverPreview(
            key: const ValueKey('video-card-hover-preview'),
            video: widget.video,
            interactions: scope.interactions,
          ),
        if (widget.video.access.label != null)
          Positioned(
            top: 6,
            left: 6,
            right: 48,
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                child: VideoAccessBadge(access: widget.video.access),
              ),
            ),
          ),
        if (showAction)
          Positioned(top: 8, right: 8, child: _watchLaterButton()),
      ],
    );
    final cover = AnimatedScale(
      key: const ValueKey('video-card-cover-scale'),
      scale: hovered ? _coverHoverScale : 1,
      duration: _snapBack || reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: contents,
      ),
    );
    return _cover = widget.hovered == null
        ? ScrollAwareHoverRegion(onHover: _hoverCover, child: cover)
        : cover;
  }

  Widget _watchLaterButton() {
    final added = _scope?.interactions.isAdded(widget.video.id) ?? false;
    final uncertain =
        _scope?.interactions.isUncertain(widget.video.id) ?? false;
    return GestureDetector(
      // Disabled add actions must still consume taps inside a clickable card.
      onTap: () {},
      excludeFromSemantics: true,
      child: Tooltip(
        message: added
            ? '已加入稍后再看'
            : uncertain
            ? '请在稍后再看列表核对添加结果'
            : '添加稍后再看',
        child: Material(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            key: const ValueKey('video-card-watch-later'),
            borderRadius: BorderRadius.circular(5),
            onTap: _busy || added || uncertain ? null : _watchLater,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: _busy
                    ? const SizedBox(
                        width: 17,
                        height: 17,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        added ? Icons.check_rounded : BiliIcons.watchLater,
                        size: 23,
                        color: Colors.white,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// Mounted only for an enabled, visible hover. Static covers own no preview
// lifecycle observer, ancestor scroll subscriptions, timer or cancellation.
class _VideoCardHoverPreview extends StatefulWidget {
  const _VideoCardHoverPreview({
    super.key,
    required this.video,
    required this.interactions,
  });
  final VideoSummary video;
  final VideoCardOperations interactions;

  @override
  State<_VideoCardHoverPreview> createState() => _VideoCardHoverPreviewState();
}

class _VideoCardHoverPreviewState extends State<_VideoCardHoverPreview>
    with WidgetsBindingObserver {
  VideoCardPreviewSession? _preview;
  RequestCancellation? _cancellation;
  Timer? _hoverDelay;
  bool _foreground = true;
  bool _scrollCheckScheduled = false;
  bool _initialized = false;
  final _scrollPositions = <ScrollPosition>{};

  bool get _scrolling =>
      _scrollPositions.any((position) => position.isScrollingNotifier.value);

  @override
  void initState() {
    super.initState();
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Scrollable.maybeOf(context);
    final positions = <ScrollPosition>{};
    context.visitAncestorElements((element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        positions.add((element.state as ScrollableState).position);
      }
      return true;
    });
    final changed =
        !_initialized ||
        positions.length != _scrollPositions.length ||
        !positions.containsAll(_scrollPositions);
    if (!changed) return;
    for (final position in _scrollPositions.difference(positions)) {
      position.isScrollingNotifier.removeListener(_onScrollActivityChanged);
    }
    for (final position in positions.difference(_scrollPositions)) {
      position.isScrollingNotifier.addListener(_onScrollActivityChanged);
    }
    _scrollPositions
      ..clear()
      ..addAll(positions);
    _initialized = true;
    _restartPreview();
  }

  @override
  void didUpdateWidget(_VideoCardHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id ||
        oldWidget.video.previewCid != widget.video.previewCid ||
        oldWidget.interactions != widget.interactions) {
      _restartPreview();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _restartPreview();
  }

  void _onScrollActivityChanged() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_scrollCheckScheduled) return;
      _scrollCheckScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollCheckScheduled = false;
        if (mounted) _restartPreview();
      });
    } else {
      _restartPreview();
    }
  }

  void _stopPreview() {
    _hoverDelay?.cancel();
    _hoverDelay = null;
    _cancellation?.cancel();
    _cancellation = null;
  }

  void _restartPreview() {
    _stopPreview();
    setState(() => _preview = null);
    if (_foreground && !_scrolling) {
      _hoverDelay = Timer(const Duration(milliseconds: 200), _loadPreview);
    }
  }

  Future<void> _loadPreview() async {
    if (!_foreground || _scrolling) return;
    final token = RequestCancellation();
    _cancellation = token;
    try {
      final result = await widget.interactions.preview(
        widget.video.id,
        token,
        cid: widget.video.previewCid,
      );
      if (!mounted || token.isCancelled || !_foreground || _scrolling) return;
      setState(() => _preview = result);
    } on AppFailure {
      // Preview is optional; a read failure leaves the clickable cover intact.
    }
  }

  @override
  void dispose() {
    _stopPreview();
    for (final position in _scrollPositions) {
      position.isScrollingNotifier.removeListener(_onScrollActivityChanged);
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    // Keep the cover under the first-frame fade; cancellation removes the
    // surface immediately instead of retaining it for an exit animation.
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        key: ObjectKey(preview),
        tween: Tween(begin: 0, end: 1),
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.linear,
        builder: (context, opacity, child) =>
            Opacity(opacity: opacity, child: child),
        child: _VideoCardPlaybackPreview(
          key: const ValueKey('video-card-preview'),
          preview: preview,
        ),
      ),
    );
  }
}

class _VideoCardPlaybackPreview extends StatelessWidget {
  const _VideoCardPlaybackPreview({super.key, required this.preview});
  final VideoCardPreviewSession preview;

  @override
  Widget build(BuildContext context) {
    final surface = VideoSurface(
      engine: preview.engine,
      paintScale: _coverHoverScale,
    );
    return StreamBuilder<PlaybackSnapshot>(
      stream: preview.engine.snapshots,
      initialData: preview.engine.currentSnapshot,
      builder: (context, event) {
        final snapshot = event.data ?? preview.engine.currentSnapshot;
        if (preview.closed ||
            snapshot.phase == PlaybackPhase.idle ||
            snapshot.phase == PlaybackPhase.failed ||
            snapshot.phase == PlaybackPhase.disposed) {
          return const SizedBox.shrink();
        }
        final total = snapshot.duration.inMilliseconds;
        return VideoCompositionScope.of(context).compose(
          context,
          layers: [
            surface,
            Align(
              alignment: Alignment.bottomCenter,
              child: LinearProgressIndicator(
                key: const ValueKey('video-card-preview-progress'),
                value: total <= 0
                    ? 0
                    : (snapshot.position.inMilliseconds / total).clamp(
                        0.0,
                        1.0,
                      ),
                minHeight: 2,
                color: Colors.white,
                backgroundColor: Colors.black38,
              ),
            ),
          ],
        );
      },
    );
  }
}
