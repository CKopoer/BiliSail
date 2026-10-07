import 'dart:async';

import 'package:flutter/material.dart';
import 'package:bili_player/bili_player.dart';

import '../../core/presentation/workspace_activity.dart';
import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../domain/video.dart';
import '../../features/video/domain/video_card_interactions.dart';
import '../../features/video/application/video_card_preview_playback.dart';
import 'bili_icons.dart';
import 'video_card_interaction_scope.dart';

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

class _VideoCardCoverState extends State<VideoCardCover>
    with WidgetsBindingObserver {
  bool _coverHovered = false;
  bool _pointerHovered = false;
  bool _busy = false;
  bool _active = true;
  VideoCardInteractionScope? _scope;
  VideoCardPreviewSession? _preview;
  RequestCancellation? _previewCancellation;
  Timer? _hoverDelay;
  int _writeGeneration = 0;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _stopPreview();
      setState(() {
        _preview = null;
        _coverHovered = false;
      });
    } else {
      _hoverCover(widget.hovered ?? _pointerHovered);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = VideoCardInteractionScope.maybeOf(context);
    final active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    final scopeChanged = scope?.interactions != _scope?.interactions;
    final becameActive = active && !_active;
    if (scopeChanged || !active) {
      _stopPreview();
      _coverHovered = false;
      _preview = null;
      _busy = false;
      ++_writeGeneration;
    }
    _scope = scope;
    _active = active;
    if ((scopeChanged || becameActive) &&
        active &&
        _foreground &&
        (widget.hovered ?? _pointerHovered)) {
      _hoverCover(true);
    }
  }

  @override
  void didUpdateWidget(VideoCardCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.video.id != widget.video.id) {
      _stopPreview();
      _preview = null;
      _coverHovered = false;
      _busy = false;
      ++_writeGeneration;
    }
    if (widget.hovered != null &&
        (oldWidget.hovered != widget.hovered ||
            oldWidget.video.id != widget.video.id)) {
      _hoverCover(widget.hovered!);
    }
  }

  void _stopPreview() {
    _hoverDelay?.cancel();
    _hoverDelay = null;
    _previewCancellation?.cancel();
    _previewCancellation = null;
  }

  void _hoverCover(bool hovered) {
    _pointerHovered = hovered;
    if (!_active || !_foreground) return;
    _stopPreview();
    setState(() {
      _coverHovered = hovered;
      _preview = null;
    });
    if (!hovered || _scope == null || !widget.video.id.isValid) return;
    _hoverDelay = Timer(const Duration(milliseconds: 200), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final scope = _scope;
    if (scope == null || !_coverHovered || !_active || !_foreground) return;
    final token = RequestCancellation();
    _previewCancellation = token;
    try {
      final result = await scope.interactions.preview(
        widget.video.id,
        token,
        cid: widget.video.previewCid,
      );
      if (!mounted ||
          token.isCancelled ||
          !_coverHovered ||
          !_active ||
          scope.interactions != _scope?.interactions) {
        return;
      }
      setState(() => _preview = result);
    } on AppFailure {
      // Preview is optional; a read failure leaves the clickable cover intact.
    }
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
  void dispose() {
    _stopPreview();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final preview = _preview;
      return MouseRegion(
        onEnter: widget.hovered == null ? (_) => _hoverCover(true) : null,
        onExit: widget.hovered == null ? (_) => _hoverCover(false) : null,
        child: AnimatedScale(
          key: const ValueKey('video-card-cover-scale'),
          scale: _coverHovered ? 1.05 : 1,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Stack(
              fit: StackFit.expand,
              children: [
                widget.child,
                if (preview != null)
                  IgnorePointer(
                    child: _VideoCardPlaybackPreview(
                      key: const ValueKey('video-card-preview'),
                      preview: preview,
                    ),
                  ),
                if (widget.showWatchLaterButton &&
                    _active &&
                    _scope != null &&
                    widget.video.id.isValid &&
                    (_coverHovered || widget.focused))
                  Positioned(top: 8, right: 8, child: _watchLaterButton()),
              ],
            ),
          ),
        ),
      );
    },
  );

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

class _VideoCardPlaybackPreview extends StatelessWidget {
  const _VideoCardPlaybackPreview({super.key, required this.preview});
  final VideoCardPreviewSession preview;

  @override
  Widget build(BuildContext context) {
    final surface = VideoSurface(engine: preview.engine);
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
        return Stack(
          fit: StackFit.expand,
          children: [
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
