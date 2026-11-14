import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/presentation/workspace_activity.dart';
import '../../domain/video.dart';
import '../../features/video/domain/video_card_interactions.dart';
import 'card_hover_preview.dart';
import 'bili_icons.dart';
import 'scroll_aware_hover_region.dart';
import 'video_card_interaction_scope.dart';
import 'video_card_menu_sheet.dart';
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
  StreamSubscription<VideoId>? _watchLaterSubscription;

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
    if (scope?.interactions != _scope?.interactions) {
      unawaited(_watchLaterSubscription?.cancel());
      final interactions = scope?.interactions;
      _watchLaterSubscription = interactions is VideoCardWatchLaterToggle
          ? (interactions as VideoCardWatchLaterToggle).watchLaterChanges
                .listen((id) {
                  if (mounted && id == widget.video.id) setState(() {});
                })
          : null;
    }
    _scope = scope;
    _active = active;
    if (_hovered || widget.focused) _refreshWatchLater();
  }

  @override
  void dispose() {
    unawaited(_watchLaterSubscription?.cancel());
    super.dispose();
  }

  void _refreshWatchLater() {
    final interactions = _scope?.interactions;
    if (_active &&
        widget.showWatchLaterButton &&
        widget.video.id.isValid &&
        interactions is VideoCardWatchLaterToggle) {
      unawaited(
        (interactions as VideoCardWatchLaterToggle).refreshWatchLater(),
      );
    }
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
    if (_hovered || widget.focused) _refreshWatchLater();
  }

  void _hoverCover(bool hovered) {
    if (_pointerHovered == hovered) return;
    setState(() {
      _pointerHovered = hovered;
      _snapBack = !hovered && _ancestorScrolling();
    });
    if (hovered) _refreshWatchLater();
  }

  Future<void> _watchLater() async {
    final scope = _scope;
    if (scope == null || _busy) return;
    final generation = ++_writeGeneration;
    setState(() => _busy = true);
    final interactions = scope.interactions;
    final remove =
        interactions.isAdded(widget.video.id) &&
        interactions is VideoCardWatchLaterToggle;
    final result = remove
        ? await (interactions as VideoCardWatchLaterToggle).removeWatchLater(
            widget.video.id,
          )
        : await interactions.addWatchLater(widget.video.id);
    if (!mounted ||
        generation != _writeGeneration ||
        scope.interactions != _scope?.interactions) {
      return;
    }
    setState(() => _busy = false);
    final message = watchLaterResultMessage(result, removing: remove);
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
      scope?.interactions is VideoCardWatchLaterToggle
          ? (scope?.interactions as VideoCardWatchLaterToggle).isWatchLaterBusy(
              widget.video.id,
            )
          : false,
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
          CardHoverPreview(
            key: const ValueKey('video-card-hover-preview'),
            sourceKey: (
              widget.video.id,
              widget.video.previewCid,
              scope.interactions,
            ),
            load: (token) => scope.interactions.preview(
              widget.video.id,
              token,
              cid: widget.video.previewCid,
            ),
            previewKey: const ValueKey('video-card-preview'),
            progressKey: const ValueKey('video-card-preview-progress'),
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
    final interactions = _scope?.interactions;
    final toggle = interactions is VideoCardWatchLaterToggle
        ? interactions as VideoCardWatchLaterToggle
        : null;
    final busy = _busy || (toggle?.isWatchLaterBusy(widget.video.id) ?? false);
    final added = _scope?.interactions.isAdded(widget.video.id) ?? false;
    final uncertain =
        _scope?.interactions.isUncertain(widget.video.id) ?? false;
    return GestureDetector(
      // Disabled add actions must still consume taps inside a clickable card.
      onTap: () {},
      excludeFromSemantics: true,
      child: Tooltip(
        message: added
            ? toggle != null
                  ? '取消稍后再看'
                  : '已加入稍后再看'
            : uncertain
            ? '请在稍后再看列表核对操作结果'
            : '添加稍后再看',
        child: Material(
          color: const Color(0x99000000),
          borderRadius: BorderRadius.circular(5),
          child: InkWell(
            key: const ValueKey('video-card-watch-later'),
            borderRadius: BorderRadius.circular(5),
            onTap: busy || (added && toggle == null) || uncertain
                ? null
                : _watchLater,
            child: SizedBox(
              width: 30,
              height: 30,
              child: Center(
                child: busy
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
