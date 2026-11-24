import 'dart:async';

import 'motion_preferences.dart';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';

import 'input_scope.dart';
import 'window_input_focus.dart';
import 'workspace_activity.dart';

/// Protects controls whose render objects only forward mouse/touch downs.
/// Flutter's Slider, for example, does not forward pan/zoom starts to its drag.
class TrackpadBackBlocker extends StatelessWidget {
  const TrackpadBackBlocker({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Theme.of(context).platform == TargetPlatform.macOS
      ? GestureDetector(
          supportedDevices: const {PointerDeviceKind.trackpad},
          onHorizontalDragStart: (_) {},
          excludeFromSemantics: true,
          child: child,
        )
      : child;
}

/// Handles iOS edge swipes and macOS trackpad drags for custom back steps.
class HistoryBackRegion extends StatefulWidget {
  const HistoryBackRegion({
    super.key,
    required this.enabled,
    required this.identity,
    required this.onBack,
    this.iosTransitionBuilder,
    this.iosEdgeOnly = false,
    this.iosPreviewAvailable = false,
    required this.child,
  });

  final bool enabled;
  final Object identity;
  final VoidCallback onBack;
  final bool iosEdgeOnly, iosPreviewAvailable;
  final Widget Function(
    Animation<double> progress,
    bool previewing,
    Widget child,
  )?
  iosTransitionBuilder;
  final Widget child;

  @override
  State<HistoryBackRegion> createState() => _HistoryBackRegionState();
}

class _HistoryBackRegionState extends State<HistoryBackRegion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  double get _width => context.size!.width;
  // Bound slow drags as well as normalizing flick speed to the viewport.
  double get _commitDistance => _iOS ? (_width / 3).clamp(0, 140) : 120;
  bool _previewing = false;
  MediaQueryData? _gestureMetrics;
  late final _progress = AnimationController(vsync: this);
  final _windowFocus = WindowInputFocus.instance;
  InputScope<Object>? _input;
  ModalRoute<Object?>? _route;
  bool _active = false;
  bool _macOS = false;
  bool _iOS = false;
  bool _tracking = false;
  bool _foreground = true;
  bool _disposed = false;
  int? _viewId;
  double get _direction =>
      _iOS && Directionality.of(context) == TextDirection.rtl ? -1 : 1;

  bool get _available =>
      widget.enabled &&
      _active &&
      _foreground &&
      (!_windowFocus.observed || _windowFocus.viewId == _viewId) &&
      (_input?.routes.modal != true || identical(_input?.routes.top, _route)) &&
      (_input?.dispatcher.barriers ?? 0) == 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _windowFocus.addListener(_focusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _input = InputScope.of<Object>(context);
    _route = ModalRoute.of(context);
    _viewId = View.of(context).viewId;
    _macOS = Theme.of(context).platform == TargetPlatform.macOS;
    _iOS = Theme.of(context).platform == TargetPlatform.iOS;
    _active =
        (_macOS || _iOS) &&
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled &&
        (_route?.isCurrent ?? true);
    if (!_available) _reset();
  }

  @override
  void didUpdateWidget(HistoryBackRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.identity != widget.identity || !widget.enabled) _reset();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _invalidate();
  }

  void _focusChanged() {
    if (_windowFocus.observed && _windowFocus.viewId != _viewId) _invalidate();
  }

  @override
  void didChangeMetrics() {
    if (_iOS &&
        (!_previewing ||
            MediaQueryData.fromView(View.of(context)) == _gestureMetrics)) {
      return;
    }
    _invalidate();
  }

  void _invalidate() {
    if (_previewing) {
      setState(_reset);
    } else {
      _reset();
    }
  }

  void _reset() {
    _tracking = _previewing = false;
    _gestureMetrics = null;
    if (_disposed) return;
    _progress.stop();
    _progress.value = 0;
  }

  void _cancel() {
    if (_iOS) {
      if (_tracking) unawaited(_finishIos(false));
      return;
    }
    _tracking = false;
    if (_disposed) return;
    if (_progress.value == 0) {
      _progress.stop();
      return;
    }
    if (shouldReduceMotion(context)) {
      _progress.value = 0;
    } else {
      _progress.animateBack(
        0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _start(DragStartDetails details) {
    if (_iOS && _previewing) return;
    _progress.stop();
    _progress.value = 0;
    _tracking = _available;
    if (_iOS && _tracking) {
      _gestureMetrics = MediaQueryData.fromView(View.of(context));
      setState(() => _previewing = true);
    }
    _distance = 0;
  }

  double _distance = 0;

  void _update(DragUpdateDetails details) {
    if (!_tracking) return;
    if (!_available) {
      setState(_reset);
      return;
    }
    _distance += (details.primaryDelta ?? 0) * _direction;
    _progress.value = (_distance / (_iOS ? _width : _commitDistance)).clamp(
      0,
      1,
    );
  }

  void _end(DragEndDetails details) {
    if (!_tracking) return;
    final velocity = (details.primaryVelocity ?? 0) * _direction;
    final commit =
        _available &&
        (_iOS && velocity.abs() >= _width
            ? velocity > 0 && _distance > kTouchSlop
            : _distance >= _commitDistance);
    if (_iOS) {
      unawaited(_finishIos(commit));
      return;
    }
    _cancel();
    if (!commit) return;
    _input?.dispatcher.beforeNavigation();
    widget.onBack();
  }

  Future<void> _finishIos(bool commit) async {
    _tracking = false;
    final target = commit && widget.iosPreviewAvailable ? 1.0 : 0.0;
    try {
      // Local details and fullscreen share the current view. Never reveal a
      // workspace page behind them or navigate it while settling a local step.
      if (!commit || target == 1) {
        await _progress
            .animateTo(
              target,
              duration: shouldReduceMotion(context)
                  ? Duration.zero
                  : Duration(
                      milliseconds: (200 * (target - _progress.value).abs())
                          .round(),
                    ),
              curve: Curves.easeOutCubic,
            )
            .orCancel;
      }
      if (!mounted || !_previewing) return;
      if (commit && _available) {
        _input?.dispatcher.beforeNavigation();
        widget.onBack();
      }
      setState(_reset);
    } on TickerCanceled {
      // The route, page identity or window changed while settling.
    }
  }

  GestureRecognizerFactory<_IosBackDragRecognizer> _iosDrag({
    required bool edge,
  }) => GestureRecognizerFactoryWithHandlers<_IosBackDragRecognizer>(
    _IosBackDragRecognizer.new,
    (recognizer) {
      recognizer
        ..direction = _direction
        ..canStart = (event) {
          if (!_available || _previewing) return false;
          if (edge) return true;
          final box = context.findRenderObject()! as RenderBox;
          final x = box.globalToLocal(event.position).dx;
          return (_direction > 0 ? x : box.size.width - x) > _edgeWidth;
        }
        ..onStart = _start
        ..onUpdate = _update
        ..onEnd = _end
        ..onCancel = _cancel;
    },
  );

  double get _edgeWidth =>
      (_direction > 0
              ? MediaQuery.paddingOf(context).left
              : MediaQuery.paddingOf(context).right)
          .clamp(20, double.infinity);

  Widget _iosContent() {
    final builder = widget.iosTransitionBuilder;
    return AnimatedBuilder(
      animation: _progress,
      child:
          builder?.call(
            _progress,
            _previewing &&
                widget.iosPreviewAvailable &&
                !shouldReduceMotion(context),
            widget.child,
          ) ??
          widget.child,
      builder: (context, child) => Transform.translate(
        // Only a small displacement for in-place steps with no separate page.
        offset: Offset(
          widget.iosPreviewAvailable || shouldReduceMotion(context)
              ? 0
              : _direction * 32 * _progress.value,
          0,
        ),
        child: child,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _windowFocus.removeListener(_focusChanged);
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => !_macOS && !_iOS
      ? widget.child
      : RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          excludeFromSemantics: true,
          gestures: {
            if (_iOS && _active && widget.enabled && !widget.iosEdgeOnly)
              _IosBackDragRecognizer: _iosDrag(edge: false),
            if (_macOS && _active && widget.enabled)
              _BackDragRecognizer:
                  GestureRecognizerFactoryWithHandlers<_BackDragRecognizer>(
                    () => _BackDragRecognizer(),
                    (recognizer) {
                      recognizer
                        ..canStart = (() => _available)
                        ..onStart = _start
                        ..onUpdate = _update
                        ..onEnd = _end
                        ..onCancel = _cancel;
                    },
                  ),
          },
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              if (_iOS) _iosContent() else widget.child,
              // The edge takes precedence over paging; elsewhere the ancestor
              // competes normally and a descendant horizontal control wins.
              if (_iOS && _active && widget.enabled)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: _edgeWidth,
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    excludeFromSemantics: true,
                    gestures: {_IosBackDragRecognizer: _iosDrag(edge: true)},
                  ),
                ),
              if (_macOS)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ExcludeSemantics(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: AnimatedBuilder(
                          animation: _progress,
                          builder: (context, _) {
                            final progress = _progress.value;
                            final colors = Theme.of(context).colorScheme;
                            final ready = progress >= 1;
                            return Transform.translate(
                              offset: Offset(-48 + 64 * progress, 0),
                              child: Opacity(
                                opacity: progress,
                                child: Container(
                                  key: const ValueKey(
                                    'trackpad-back-indicator',
                                  ),
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: ready
                                        ? colors.primaryContainer
                                        : colors.surfaceContainerHigh,
                                    boxShadow: const [
                                      BoxShadow(
                                        blurRadius: 8,
                                        color: Color(0x26000000),
                                      ),
                                    ],
                                  ),
                                  child: Transform.scale(
                                    scale: .75 + .25 * progress,
                                    child: Icon(
                                      Icons.arrow_back_rounded,
                                      textDirection: TextDirection.ltr,
                                      color: ready
                                          ? colors.onPrimaryContainer
                                          : colors.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
}

class _IosBackDragRecognizer extends HorizontalDragGestureRecognizer {
  _IosBackDragRecognizer()
    : super(supportedDevices: {PointerDeviceKind.touch}) {
    dragStartBehavior = DragStartBehavior.down;
    onlyAcceptDragOnThreshold = true;
  }

  late bool Function(PointerEvent) canStart;
  double direction = 1;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canStart(event) && super.isPointerAllowed(event);

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind kind,
    double? deviceTouchSlop,
  ) => globalDistanceMoved * direction > computeHitSlop(kind, gestureSettings);

  @override
  void handleEvent(PointerEvent event) {
    // An accepted Flutter drag reports onEnd even for pointer cancellation.
    // Clear the pending navigation before it can be mistaken for a release.
    if (event is PointerCancelEvent) onCancel?.call();
    super.handleEvent(event);
  }
}

/// Keep Flutter's drag lifecycle and arena arbitration, narrowing only intent.
/// Inner horizontal lists/sliders enter first and win at the normal drag slop.
class _BackDragRecognizer extends HorizontalDragGestureRecognizer {
  _BackDragRecognizer()
    : super(supportedDevices: {PointerDeviceKind.trackpad}) {
    dragStartBehavior = DragStartBehavior.down;
    onlyAcceptDragOnThreshold = true;
  }

  bool Function()? canStart;
  Offset _pan = Offset.zero;
  bool _directionLocked = false;
  bool _invalid = false;

  @override
  bool isPointerPanZoomAllowed(PointerPanZoomStartEvent event) =>
      (canStart?.call() ?? false) && super.isPointerPanZoomAllowed(event);

  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {
    _pan = Offset.zero;
    _directionLocked = _invalid = false;
    super.addAllowedPointerPanZoom(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerPanZoomUpdateEvent) {
      if (_invalid) return;
      _pan = event.pan;
      if ((event.scale - 1).abs() > .02 ||
          event.rotation.abs() > .02 ||
          (!_directionLocked &&
              (_pan.dx < -kTouchSlop ||
                  (_pan.dy.abs() > kTouchSlop &&
                      _pan.dx < _pan.dy.abs() * 1.5)))) {
        _invalid = true;
        onCancel?.call();
        resolve(GestureDisposition.rejected);
        return;
      }
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    _directionLocked =
        _pan.dx > _pan.dy.abs() * 1.5 &&
        super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind,
          deviceTouchSlop,
        );
    return _directionLocked;
  }
}
