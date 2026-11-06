import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

typedef PredictiveBackRegionBuilder = Widget Function(
  BuildContext context,
  Animation<double> progress,
  SwipeEdge edge,
  bool previewing,
);

typedef _BackGestureMetrics = ({
  Size physicalSize,
  double devicePixelRatio,
  EdgeInsets padding,
  EdgeInsets viewPadding,
  EdgeInsets viewInsets,
});

/// Drives retained pages from Android's system gesture without popping a route.
class PredictiveBackRegion extends StatefulWidget {
  const PredictiveBackRegion({
    super.key,
    required this.enabled,
    required this.identity,
    this.destinationIdentity,
    this.onStart,
    this.onEnd,
    required this.onBack,
    required this.builder,
  });

  final bool enabled;
  final Object identity;
  final Object? destinationIdentity;
  final bool Function()? onStart;
  final VoidCallback? onEnd;
  final VoidCallback onBack;
  final PredictiveBackRegionBuilder builder;

  @override
  State<PredictiveBackRegion> createState() => _PredictiveBackRegionState();
}

class _PredictiveBackRegionState extends State<PredictiveBackRegion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final _progress = AnimationController(vsync: this);
  SwipeEdge _edge = SwipeEdge.left;
  bool _previewing = false;
  bool _tracking = false;
  bool _committing = false;
  Object? _expectedIdentity;
  _BackGestureMetrics? _gestureMetrics;
  int _generation = 0;

  _BackGestureMetrics get _windowMetrics {
    final view = View.of(context);
    // Compare physical inset values rather than ViewPadding object identity.
    return (
      physicalSize: view.physicalSize,
      devicePixelRatio: view.devicePixelRatio,
      padding: EdgeInsets.fromViewPadding(view.padding, 1),
      viewPadding: EdgeInsets.fromViewPadding(view.viewPadding, 1),
      viewInsets: EdgeInsets.fromViewPadding(view.viewInsets, 1),
    );
  }

  bool get _routeAvailable =>
      Theme.of(context).platform == TargetPlatform.android &&
      (ModalRoute.isCurrentOf(context) ?? true) &&
      // Scaffold removes consumed keyboard insets from its body's MediaQuery.
      View.of(context).viewInsets.bottom == 0;

  bool get _canStart => widget.enabled && _routeAvailable;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didUpdateWidget(PredictiveBackRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_committing && widget.identity == _expectedIdentity) return;
    if (oldWidget.identity != widget.identity || !widget.enabled) _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_previewing &&
        (!_routeAvailable || (!_committing && !widget.enabled))) {
      _reset();
    }
  }

  @override
  void didChangeMetrics() {
    // Applying the previewed page's system bar style can re-publish identical
    // metrics on Android. Cancel only when the gesture's geometry has changed.
    if (_previewing && _gestureMetrics != _windowMetrics) setState(_reset);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_previewing && state != AppLifecycleState.resumed) setState(_reset);
  }

  void _reset() {
    if (_previewing) widget.onEnd?.call();
    _generation++;
    _tracking = _previewing = false;
    _committing = false;
    _expectedIdentity = null;
    _gestureMetrics = null;
    _progress.stop();
    _progress.value = 0;
  }

  @override
  bool handleStartBackGesture(PredictiveBackEvent backEvent) {
    if (!_canStart || _previewing || backEvent.isButtonEvent) return false;
    if (widget.onStart?.call() == false) return false;
    setState(() {
      _generation++;
      _tracking = _previewing = true;
      _edge = backEvent.swipeEdge;
      _expectedIdentity = widget.destinationIdentity;
      _gestureMetrics = _windowMetrics;
      _progress.value = backEvent.progress;
    });
    return true;
  }

  @override
  void handleUpdateBackGestureProgress(PredictiveBackEvent backEvent) {
    if (_tracking) _progress.value = backEvent.progress;
  }

  @override
  void handleCancelBackGesture() {
    if (_tracking) unawaited(_finish(commit: false));
  }

  @override
  void handleCommitBackGesture() {
    if (_tracking) unawaited(_finish(commit: true));
  }

  Future<void> _finish({required bool commit}) async {
    _tracking = false;
    final generation = _generation;
    try {
      final duration = MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180);
      await _progress
          .animateTo(
            commit ? 1 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (!mounted || generation != _generation) return;
      final shouldReturn = commit && _canStart;
      if (shouldReturn) {
        _committing = true;
        widget.onBack();
        // Keep the prepared destination at its final position while its live
        // tree and window chrome finish the committed layout and paint.
        for (var frame = 0; frame < 2; frame++) {
          WidgetsBinding.instance.scheduleFrame();
          await WidgetsBinding.instance.endOfFrame;
          if (!mounted || generation != _generation) return;
        }
      }
      setState(_reset);
    } on TickerCanceled {
      // Navigation, account changes and disposal invalidate this gesture.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_previewing) widget.onEnd?.call();
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Subscribe even while idle so a newly opened modal invalidates a gesture.
    ModalRoute.isCurrentOf(context);
    return IgnorePointer(
      ignoring: _previewing,
      child: ClipRect(
        child: widget.builder(context, _progress, _edge, _previewing),
      ),
    );
  }
}

/// Repaints the page transform while keeping its feature tree out of frame ticks.
class PredictiveBackPageTransition extends StatelessWidget {
  const PredictiveBackPageTransition({
    super.key,
    required this.progress,
    required this.edge,
    this.incoming = false,
    required this.child,
  });

  final Animation<double> progress;
  final SwipeEdge edge;
  final bool incoming;
  final Widget child;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: progress,
    child: child,
    builder: (context, child) {
      final value = progress.value;
      final reduced = MediaQuery.disableAnimationsOf(context);
      final direction = edge == SwipeEdge.left ? 1.0 : -1.0;
      // Adjacent full-size pages share a moving edge. Fractional translation
      // follows the viewport width without relayout or resizing video surfaces.
      return FractionalTranslation(
        translation: Offset(
          reduced ? 0 : direction * (value - (incoming ? 1 : 0)),
          0,
        ),
        child: child,
      );
    },
  );
}
