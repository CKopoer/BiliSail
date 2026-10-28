import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../shared/ui/storyboard_thumbnail.dart';
import '../domain/playback_timeline.dart';
import 'playback_timeline_bar.dart' show formatPlaybackTime;

/// Touch scrubbing previews locally and commands the session only on release.
class PlayerSeekControls extends StatefulWidget {
  const PlayerSeekControls({
    super.key,
    required this.enabled,
    required this.sourceGeneration,
    required this.position,
    required this.duration,
    required this.preview,
    required this.onSeek,
    required this.onPreviewRequest,
    required this.child,
    this.storyboard,
    this.storyboardLoading = false,
  });

  final bool enabled;
  final int sourceGeneration;
  // Read the confirmed clock once, without subscribing the gesture layer to it.
  final ValueGetter<Duration> position;
  final Duration duration;
  final ValueNotifier<Duration?> preview;
  // Completes after the session has confirmed the backend position.
  final Future<void> Function(Duration) onSeek;
  final VoidCallback onPreviewRequest;
  final VideoStoryboard? storyboard;
  final bool storyboardLoading;
  final Widget child;

  @override
  State<PlayerSeekControls> createState() => _PlayerSeekControlsState();
}

class _PlayerSeekControlsState extends State<PlayerSeekControls>
    with WidgetsBindingObserver {
  final _pointers = <int>{};
  bool _foreground = true;
  bool _disposed = false;
  bool _multiplePointers = false;
  bool _dragging = false;
  int _revision = 0;
  Duration _start = Duration.zero;
  Duration _total = Duration.zero;
  Size _size = Size.zero;
  double _delta = 0;

  bool get _enabled =>
      widget.enabled && _foreground && widget.duration > Duration.zero;
  bool get _current => _enabled && ModalRoute.of(context)?.isCurrent != false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final state = WidgetsBinding.instance.lifecycleState;
    _foreground = state == null || state == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_current) _cancel(defer: true);
  }

  @override
  void didUpdateWidget(covariant PlayerSeekControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceGeneration != widget.sourceGeneration ||
        oldWidget.enabled != widget.enabled ||
        oldWidget.duration != widget.duration) {
      _cancel(defer: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _foreground = state == AppLifecycleState.resumed;
      _cancel();
      _pointers.clear();
      _multiplePointers = false;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _dragging = false;
    WidgetsBinding.instance.removeObserver(this);
    // The preview notifier belongs to the presenting view and dies with it.
    super.dispose();
  }

  void _cancel({bool defer = false}) {
    if (_disposed) return;
    _dragging = false;
    final revision = ++_revision;
    if (widget.preview.value == null) return;
    if (defer) {
      // The timeline is a sibling. Never notify it during this widget's build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && revision == _revision) widget.preview.value = null;
      });
    } else {
      widget.preview.value = null;
    }
  }

  void _startDrag(DragStartDetails details, Size size) {
    if (!_current ||
        _multiplePointers ||
        _pointers.length != 1 ||
        size.width <= 0) {
      return;
    }
    _revision++;
    _dragging = true;
    _size = size;
    _total = widget.duration;
    _start = Duration(
      milliseconds: widget.position().inMilliseconds.clamp(
        0,
        _total.inMilliseconds,
      ),
    );
    _delta = 0;
    widget.preview.value = _start;
    widget.onPreviewRequest();
  }

  void _updateDrag(DragUpdateDetails details) {
    if (!_dragging) return;
    if (!_current) {
      _cancel();
      return;
    }
    _delta += details.delta.dx;
    // A full picture width covers at most two minutes, including long videos.
    // Accumulate pixels before rounding so small high-rate events are retained.
    final span = math.min(_total.inMilliseconds, 120000);
    widget.preview.value = Duration(
      milliseconds: (_start.inMilliseconds + _delta / _size.width * span)
          .round()
          .clamp(0, _total.inMilliseconds),
    );
  }

  Future<void> _endDrag() async {
    if (!_dragging) return;
    final target = widget.preview.value;
    final commit = _current && target != null && target != _start;
    if (!commit) {
      _cancel();
      return;
    }
    final revision = ++_revision;
    // Hide the central card on release, but keep the timeline at the target
    // until seek confirms it. Clearing early exposes the old playback clock.
    setState(() => _dragging = false);
    try {
      await widget.onSeek(target);
    } finally {
      // A cancelled gesture or a newer drag owns its own preview now.
      if (mounted && revision == _revision) _cancel();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (_dragging && _size != constraints.biggest) _cancel(defer: true);
      return Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) {
          if (event.kind != PointerDeviceKind.touch) return;
          _pointers.add(event.pointer);
          if (_pointers.length > 1) {
            _multiplePointers = true;
            _cancel();
          }
        },
        onPointerUp: (event) {
          _pointers.remove(event.pointer);
          if (_pointers.isEmpty) _multiplePointers = false;
        },
        onPointerCancel: (event) {
          _pointers.remove(event.pointer);
          if (_pointers.isEmpty) _multiplePointers = false;
          _cancel();
        },
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          gestures: {
            if (_enabled)
              HorizontalDragGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<
                    HorizontalDragGestureRecognizer
                  >(
                    () =>
                        HorizontalDragGestureRecognizer(
                            supportedDevices: {PointerDeviceKind.touch},
                          )
                          ..dragStartBehavior = DragStartBehavior.down
                          ..onlyAcceptDragOnThreshold = true,
                    (recognizer) {
                      recognizer.onStart = (details) =>
                          _startDrag(details, constraints.biggest);
                      recognizer.onUpdate = _updateDrag;
                      recognizer.onEnd = (_) => _endDrag();
                      recognizer.onCancel = _cancel;
                    },
                  ),
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              widget.child,
              IgnorePointer(
                child: RepaintBoundary(
                  child: ValueListenableBuilder<Duration?>(
                    valueListenable: widget.preview,
                    builder: (context, position, _) =>
                        position == null || !_dragging
                        ? const SizedBox.shrink()
                        : Center(
                            child: _SeekPreview(
                              position: position,
                              duration: _total,
                              storyboard: widget.storyboard,
                              loading: widget.storyboardLoading,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _SeekPreview extends StatelessWidget {
  const _SeekPreview({
    required this.position,
    required this.duration,
    required this.storyboard,
    required this.loading,
  });

  final Duration position, duration;
  final VideoStoryboard? storyboard;
  final bool loading;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final availableWidth = math.min(
        100.0,
        math.max(0.0, constraints.maxWidth - 16),
      );
      final textHeight = MediaQuery.textScalerOf(context).scale(13) * 1.5;
      final aspectRatio = storyboard?.aspectRatio ?? 16 / 9;
      final imageHeight = math.min(
        availableWidth / aspectRatio,
        math.max(0.0, constraints.maxHeight - textHeight - 16),
      );
      // Keep the sprite's aspect ratio when height is the limiting constraint.
      final width = imageHeight >= 24
          ? imageHeight * aspectRatio
          : availableWidth;
      final frame = storyboard?.frameAt(position);
      final placeholder = ColoredBox(
        color: const Color(0xff303030),
        child: Center(
          child: Icon(
            loading ? Icons.image_outlined : Icons.image_not_supported_outlined,
            color: Colors.white54,
            size: 24,
          ),
        ),
      );
      return SizedBox(
        key: const ValueKey('player-swipe-seek-preview'),
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (imageHeight >= 24)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: switch (storyboard) {
                  final storyboard? when frame != null => StoryboardThumbnail(
                    storyboard: storyboard,
                    frame: frame,
                    width: width,
                    height: imageHeight,
                    fallback: placeholder,
                  ),
                  _ => SizedBox(height: imageHeight, child: placeholder),
                },
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FittedBox(
                fit: BoxFit.fitWidth,
                child: Text(
                  '${formatPlaybackTime(position)} / ${formatPlaybackTime(duration)}',
                  key: const ValueKey('player-swipe-seek-time'),
                  maxLines: 1,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    shadows: [Shadow(color: Colors.black, blurRadius: 3)],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}
