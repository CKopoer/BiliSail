import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

import '../../../core/platform/window_service.dart';
import '../application/playback_session.dart';
import 'playback_snapshot_builder.dart';

class MiniPlayerActions extends InheritedWidget {
  const MiniPlayerActions({
    super.key,
    required this.onEnter,
    required this.window,
    required super.child,
  });
  final VoidCallback onEnter;
  final WindowService window;
  static MiniPlayerActions? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MiniPlayerActions>();
  @override
  bool updateShouldNotify(MiniPlayerActions oldWidget) =>
      onEnter != oldWidget.onEnter || window != oldWidget.window;
}

/// Compact controls deliberately omit comments, menus and content navigation.
/// The page retains the session; only its video surface changes presentation.
class MiniPlayer extends StatefulWidget {
  const MiniPlayer({
    super.key,
    required this.session,
    required this.window,
    required this.onRestore,
    required this.onClose,
    this.systemPip = false,
  });
  final PlaybackSession session;
  final WindowService window;
  final VoidCallback onRestore;
  final VoidCallback onClose;
  final bool systemPip;
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  bool _visible = true;
  double? _seekPosition;
  int? _seekGeneration;
  Timer? _hide;
  void _show() {
    if (!mounted) return;
    setState(() => _visible = true);
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void initState() {
    super.initState();
    _show();
  }

  @override
  void dispose() {
    _hide?.cancel();
    super.dispose();
  }

  Widget _button(
    String label,
    IconData icon,
    VoidCallback action, {
    bool selected = false,
  }) => IconButton(
    tooltip: label,
    onPressed: action,
    isSelected: selected,
    style: IconButton.styleFrom(
      foregroundColor: selected ? const Color(0xffff9ab8) : Colors.white,
      backgroundColor: Colors.black38,
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.all(8),
    ),
    icon: Icon(icon, size: 20),
  );

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('mini-player'),
    color: Colors.black,
    child: MouseRegion(
      onEnter: (_) => _show(),
      onHover: (_) => _show(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _show,
        onPanStart: widget.window.hasDesktopWindow
            ? (_) => widget.window.startDraggingPlaybackWindow()
            : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(child: VideoSurface(engine: widget.session.engine)),
            PlaybackSnapshotBuilder(
              snapshots: widget.session.snapshots,
              select: (s) => (s.phase, s.isBuffering, s.isSeeking),
              builder: (context, snapshot) =>
                  snapshot.isBuffering ||
                      snapshot.isSeeking ||
                      snapshot.phase == PlaybackPhase.buffering
                  ? const Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white70,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
            if (!widget.systemPip)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !_visible,
                  child: AnimatedOpacity(
                    opacity: _visible ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    child: Stack(
                      children: [
                        const Positioned.fill(
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.black54,
                                    Colors.transparent,
                                    Colors.black54,
                                  ],
                                  stops: [0, .45, 1],
                                ),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          right: 4,
                          child: Row(
                            children: [
                              if (widget.window.hasDesktopWindow)
                                ValueListenableBuilder<bool>(
                                  valueListenable: widget.window.alwaysOnTop,
                                  builder: (context, pinned, _) => _button(
                                    pinned ? '取消置顶' : '置顶',
                                    pinned
                                        ? Icons.push_pin_rounded
                                        : Icons.push_pin_outlined,
                                    () => unawaited(
                                      widget.window.setAlwaysOnTop(!pinned),
                                    ),
                                    selected: pinned,
                                  ),
                                ),
                              Expanded(
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onDoubleTap: widget.onRestore,
                                  onPanStart: widget.window.hasDesktopWindow
                                      ? (_) => widget.window
                                            .startDraggingPlaybackWindow()
                                      : null,
                                  child: SizedBox(
                                    height: 40,
                                    child: Center(
                                      child: Text(
                                        widget.session.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              _button(
                                '还原播放页',
                                Icons.open_in_full_rounded,
                                widget.onRestore,
                              ),
                              const SizedBox(width: 4),
                              _button(
                                '关闭小窗',
                                Icons.close_rounded,
                                widget.onClose,
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 4,
                          right: widget.window.hasMiniPlayerResizeHandle
                              ? 28
                              : 4,
                          bottom: 0,
                          child: PlaybackSnapshotBuilder(
                            snapshots: widget.session.snapshots,
                            select: (s) => (
                              s.phase,
                              s.desiredPlaying,
                              s.position.inSeconds,
                              s.duration.inSeconds,
                            ),
                            builder: (context, snapshot) => Row(
                              children: [
                                _button(
                                  snapshot.desiredPlaying ? '暂停' : '播放',
                                  snapshot.desiredPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  () => unawaited(
                                    snapshot.desiredPlaying
                                        ? widget.session.pause()
                                        : widget.session.play(),
                                  ),
                                ),
                                Expanded(
                                  child: widget.session.isLive
                                      ? const Padding(
                                          padding: EdgeInsets.symmetric(
                                            horizontal: 12,
                                          ),
                                          child: Text(
                                            '直播中',
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 11,
                                            ),
                                          ),
                                        )
                                      : SliderTheme(
                                          data: SliderTheme.of(context).copyWith(
                                            trackHeight: 2,
                                            thumbShape:
                                                const RoundSliderThumbShape(
                                                  enabledThumbRadius: 5,
                                                ),
                                            overlayShape:
                                                const RoundSliderOverlayShape(
                                                  overlayRadius: 12,
                                                ),
                                          ),
                                          child: Slider(
                                            semanticFormatterCallback: (v) =>
                                                '${(v / 1000).round()} 秒',
                                            min: 0,
                                            max: snapshot
                                                .duration
                                                .inMilliseconds
                                                .toDouble()
                                                .clamp(1, double.infinity),
                                            value:
                                                (_seekGeneration ==
                                                            widget
                                                                .session
                                                                .sourceGeneration
                                                        ? _seekPosition ??
                                                              snapshot
                                                                  .position
                                                                  .inMilliseconds
                                                                  .toDouble()
                                                        : snapshot
                                                              .position
                                                              .inMilliseconds
                                                              .toDouble())
                                                    .clamp(
                                                      0,
                                                      snapshot
                                                          .duration
                                                          .inMilliseconds
                                                          .toDouble()
                                                          .clamp(
                                                            1,
                                                            double.infinity,
                                                          ),
                                                    ),
                                            onChanged:
                                                snapshot.duration >
                                                    Duration.zero
                                                ? (v) {
                                                    _show();
                                                    setState(
                                                      () => _seekPosition = v,
                                                    );
                                                  }
                                                : null,
                                            onChangeStart: (_) =>
                                                _seekGeneration = widget
                                                    .session
                                                    .sourceGeneration,
                                            onChangeEnd: (value) {
                                              final current =
                                                  _seekGeneration ==
                                                  widget
                                                      .session
                                                      .sourceGeneration;
                                              setState(() {
                                                _seekPosition = null;
                                                _seekGeneration = null;
                                              });
                                              if (current) {
                                                unawaited(
                                                  widget.session.seek(
                                                    Duration(
                                                      milliseconds: value
                                                          .round(),
                                                    ),
                                                  ),
                                                );
                                              }
                                            },
                                          ),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (widget.window.hasMiniPlayerResizeHandle)
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Semantics(
                              label: '调整小窗大小',
                              child: MouseRegion(
                                cursor: SystemMouseCursors.resizeDownRight,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onPanStart: (_) =>
                                      widget.window.startResizingMiniPlayer(),
                                  child: const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Icon(
                                      Icons.south_east_rounded,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Safe-area bounded mobile fallback. Pointer events outside the card continue
/// to the playback page, so details and comments remain usable.
class FloatingMiniPlayer extends StatefulWidget {
  const FloatingMiniPlayer({
    super.key,
    required this.child,
    required this.aspectRatio,
  });
  final Widget child;
  final double aspectRatio;
  @override
  State<FloatingMiniPlayer> createState() => _FloatingMiniPlayerState();
}

class _FloatingMiniPlayerState extends State<FloatingMiniPlayer> {
  Offset? _offset;
  double _width = 280;
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 0 || constraints.maxHeight <= 0) {
            return const SizedBox.shrink();
          }
          final ratio = widget.aspectRatio.isFinite && widget.aspectRatio > 0
              ? widget.aspectRatio.clamp(.6, 2.39)
              : 16 / 9;
          final maxWidth = constraints.maxWidth
              .clamp(0.0, constraints.maxHeight * ratio)
              .clamp(0.0, double.infinity);
          final width = _width
              .clamp(maxWidth.clamp(1.0, 200.0), maxWidth)
              .toDouble();
          final height = width / ratio;
          final offset =
              _offset ?? Offset(constraints.maxWidth - width - 12, 12);
          final position = Offset(
            offset.dx.clamp(
              0,
              (constraints.maxWidth - width).clamp(0, double.infinity),
            ),
            offset.dy.clamp(
              0,
              (constraints.maxHeight - height).clamp(0, double.infinity),
            ),
          );
          return Stack(
            children: [
              Positioned(
                left: position.dx,
                top: position.dy,
                width: width,
                height: height,
                child: GestureDetector(
                  onPanUpdate: (event) =>
                      setState(() => _offset = position + event.delta),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: const [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 16,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          widget.child,
                          Positioned(
                            right: 0,
                            bottom: 0,
                            child: Semantics(
                              label: '调整小窗大小',
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onPanUpdate: (event) => setState(
                                  () => _width = (width + event.delta.dx).clamp(
                                    200,
                                    maxWidth.clamp(200, double.infinity),
                                  ),
                                ),
                                child: const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Align(
                                    alignment: Alignment.bottomRight,
                                    child: Icon(
                                      Icons.south_east_rounded,
                                      size: 16,
                                      color: Colors.white70,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}
