import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

/// Adapts retained-page history to iOS edge swipes and macOS trackpad drags.
/// These pages are not a Navigator stack, so Cupertino route pops cannot help.
class HistoryBackRegion extends StatefulWidget {
  const HistoryBackRegion({
    super.key,
    required this.enabled,
    required this.identity,
    required this.onBack,
    required this.child,
  });

  final bool enabled;
  final Object identity;
  final VoidCallback onBack;
  final Widget child;

  @override
  State<HistoryBackRegion> createState() => _HistoryBackRegionState();
}

class _HistoryBackRegionState extends State<HistoryBackRegion>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  // iOS follows viewport size; macOS keeps its fixed logical-pixel threshold.
  double get _commitDistance => _iOS
      ? (context.size?.width ?? MediaQuery.sizeOf(context).width) / 2
      : 120;
  late final _progress = AnimationController(vsync: this);
  final _windowFocus = WindowInputFocus.instance;
  InputScope<Object>? _input;
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
      _input?.routes.modal != true &&
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
    _viewId = View.of(context).viewId;
    _macOS = Theme.of(context).platform == TargetPlatform.macOS;
    _iOS = Theme.of(context).platform == TargetPlatform.iOS;
    _active =
        (_macOS || _iOS) &&
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled &&
        (ModalRoute.isCurrentOf(context) ?? true);
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
    if (!_foreground) _reset();
  }

  void _focusChanged() {
    if (_windowFocus.observed && _windowFocus.viewId != _viewId) _reset();
  }

  @override
  void didChangeMetrics() => _reset();

  void _reset() {
    _tracking = false;
    if (_disposed) return;
    _progress.stop();
    _progress.value = 0;
  }

  void _cancel() {
    _tracking = false;
    if (_disposed) return;
    if (_progress.value == 0) {
      _progress.stop();
      return;
    }
    if (MediaQuery.disableAnimationsOf(context)) {
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
    _progress.stop();
    _progress.value = 0;
    _tracking = _available;
    _distance = 0;
  }

  double _distance = 0;

  void _update(DragUpdateDetails details) {
    if (!_tracking) return;
    if (!_available) {
      _reset();
      return;
    }
    _distance += (details.primaryDelta ?? 0) * _direction;
    _progress.value = (_distance / _commitDistance).clamp(0, 1);
  }

  void _end(DragEndDetails details) {
    final velocity = (details.primaryVelocity ?? 0) * _direction;
    final commit =
        _tracking &&
        _available &&
        (_iOS && velocity.abs() >= 1000
            ? velocity > 0 && _distance > kTouchSlop
            : _distance >= _commitDistance);
    _cancel();
    if (!commit) return;
    _input?.dispatcher.beforeNavigation();
    widget.onBack();
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
              widget.child,
              // Like Cupertino's detector, reserve only the leading edge. A
              // page-wide touch recognizer would compete with paging/seek.
              if (_iOS && _active && widget.enabled)
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width:
                      (_direction > 0
                              ? MediaQuery.paddingOf(context).left
                              : MediaQuery.paddingOf(context).right)
                          .clamp(20, double.infinity),
                  child: RawGestureDetector(
                    behavior: HitTestBehavior.translucent,
                    excludeFromSemantics: true,
                    gestures: {
                      _EdgeBackDragRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            _EdgeBackDragRecognizer
                          >(() => _EdgeBackDragRecognizer(), (recognizer) {
                            recognizer
                              ..canStart = (() => _available)
                              ..onStart = _start
                              ..onUpdate = _update
                              ..onEnd = _end
                              ..onCancel = _cancel;
                          }),
                    },
                  ),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Align(
                      alignment: _direction > 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: AnimatedBuilder(
                        animation: _progress,
                        builder: (context, _) {
                          final progress = _progress.value;
                          final colors = Theme.of(context).colorScheme;
                          final ready = progress >= 1;
                          return Transform.translate(
                            offset: Offset(
                              _direction * (-48 + 64 * progress),
                              0,
                            ),
                            child: Opacity(
                              opacity: progress,
                              child: Container(
                                key: ValueKey(
                                  _iOS
                                      ? 'ios-back-indicator'
                                      : 'trackpad-back-indicator',
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
                                    // macOS keeps its physical direction; iOS
                                    // follows the leading edge in RTL.
                                    textDirection: _direction > 0
                                        ? TextDirection.ltr
                                        : TextDirection.rtl,
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

class _EdgeBackDragRecognizer extends HorizontalDragGestureRecognizer {
  _EdgeBackDragRecognizer()
    : super(supportedDevices: {PointerDeviceKind.touch}) {
    dragStartBehavior = DragStartBehavior.down;
  }

  bool Function()? canStart;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      (canStart?.call() ?? false) && super.isPointerAllowed(event);

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
