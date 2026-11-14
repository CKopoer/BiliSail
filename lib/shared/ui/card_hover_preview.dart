import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../domain/app_failure.dart';
import '../../domain/request_cancellation.dart';
import '../../features/playback/application/card_preview_playback.dart';

// Mounted only for an enabled, visible hover. Static covers own no preview
// lifecycle observer, ancestor scroll subscriptions, timer or cancellation.
class CardHoverPreview extends StatefulWidget {
  const CardHoverPreview({
    super.key,
    required this.sourceKey,
    required this.load,
    this.showProgress = true,
    this.paintScale = 1.05,
    this.previewKey,
    this.progressKey,
  });
  final Object sourceKey;
  final Future<CardPreviewSession?> Function(RequestCancellation) load;
  final bool showProgress;
  final double paintScale;
  final Key? previewKey, progressKey;

  @override
  State<CardHoverPreview> createState() => _CardHoverPreviewState();
}

class _CardHoverPreviewState extends State<CardHoverPreview>
    with WidgetsBindingObserver {
  CardPreviewSession? _preview;
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
  void didUpdateWidget(CardHoverPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceKey != widget.sourceKey) {
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
      final result = await widget.load(token);
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
        child: _CardPlaybackPreview(
          key: widget.previewKey,
          preview: preview,
          showProgress: widget.showProgress,
          paintScale: widget.paintScale,
          progressKey: widget.progressKey,
        ),
      ),
    );
  }
}

class _CardPlaybackPreview extends StatelessWidget {
  const _CardPlaybackPreview({
    super.key,
    required this.preview,
    required this.showProgress,
    required this.paintScale,
    this.progressKey,
  });
  final CardPreviewSession preview;
  final bool showProgress;
  final double paintScale;
  final Key? progressKey;

  @override
  Widget build(BuildContext context) {
    final surface = VideoSurface(
      engine: preview.engine,
      paintScale: paintScale,
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
            if (showProgress)
              Align(
                alignment: Alignment.bottomCenter,
                child: LinearProgressIndicator(
                  key: progressKey,
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
