import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/presentation/input_scope.dart';
import '../../core/presentation/workspace_activity.dart';
import 'scroll_collapsing_header.dart';

/// Keeps local ScrollConfiguration overrides on the same wheel preference.
final class SmoothScrollScope extends InheritedWidget {
  const SmoothScrollScope({
    super.key,
    required this.dampingRatio,
    required super.child,
  }) : assert(dampingRatio > 0 && dampingRatio < double.infinity);

  final double dampingRatio;

  static double dampingRatioOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SmoothScrollScope>()
          ?.dampingRatio ??
      1.3;

  @override
  bool updateShouldNotify(SmoothScrollScope oldWidget) =>
      dampingRatio != oldWidget.dampingRatio;
}

/// Adds short wheel transitions without replacing a list's controller/physics.
final class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior({this.horizontalMouseWheel = false});

  /// Lets a horizontal strip use ordinary mouse wheel input when dx is zero.
  final bool horizontalMouseWheel;

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    final decorated = super.buildOverscrollIndicator(context, child, details);
    final desktop = switch (getPlatform(context)) {
      TargetPlatform.windows ||
      TargetPlatform.macOS ||
      TargetPlatform.linux => true,
      _ => false,
    };
    if (context is! StatefulElement) return decorated;
    final scrollable = context.state;
    if (scrollable is! ScrollableState) return decorated;
    final childWithWheel = desktop
        ? _SmoothWheelScroll(
            scrollable: scrollable,
            axisModifiers: pointerAxisModifiers,
            horizontalMouseWheel: horizontalMouseWheel,
            child: decorated,
          )
        : decorated;
    return _RetainedScrollActivity(
      scrollable: scrollable,
      child: childWithWheel,
    );
  }
}

/// Offstage retains ScrollPosition, but does not stop its ballistic ticker.
/// Pause hidden lists without replacing their controller or saved offset.
class _RetainedScrollActivity extends StatefulWidget {
  const _RetainedScrollActivity({
    required this.scrollable,
    required this.child,
  });
  final ScrollableState scrollable;
  final Widget child;

  @override
  State<_RetainedScrollActivity> createState() =>
      _RetainedScrollActivityState();
}

class _RetainedScrollActivityState extends State<_RetainedScrollActivity> {
  bool _active = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    if (_active && !active) {
      // goIdle dispatches scroll notifications; defer until the page finishes
      // building, and let a rapid reactivation supersede this stop.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _active || !widget.scrollable.mounted) return;
        final position = widget.scrollable.position;
        // Horizontal pagers own routed tab/snap animations independently.
        if (position.axis != Axis.vertical) return;
        if (position is ScrollActivityDelegate) {
          (position as ScrollActivityDelegate).goIdle();
          if (position.hasContentDimensions && position.outOfRange) {
            position.jumpTo(
              position.pixels.clamp(
                position.minScrollExtent,
                position.maxScrollExtent,
              ),
            );
          }
        }
      });
    }
    _active = active;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

final class _SmoothWheelScroll extends StatefulWidget {
  const _SmoothWheelScroll({
    required this.scrollable,
    required this.axisModifiers,
    required this.horizontalMouseWheel,
    required this.child,
  });

  final ScrollableState scrollable;
  final Set<LogicalKeyboardKey> axisModifiers;
  final bool horizontalMouseWheel;
  final Widget child;

  @override
  State<_SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

final class _SmoothWheelScrollState extends State<_SmoothWheelScroll> {
  _WheelScrollActivity? _motion;
  bool _enabled = true;
  bool _active = true;
  double _dampingRatio = 1.3;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dampingRatio = SmoothScrollScope.dampingRatioOf(context);
    if (dampingRatio != _dampingRatio) _stopMotion();
    _dampingRatio = dampingRatio;
    _active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    final enabled = _active && !MediaQuery.disableAnimationsOf(context);
    if (_enabled && !enabled) _stopMotion();
    _enabled = enabled;
  }

  void _stopMotion() {
    final motion = _motion;
    _motion = null;
    motion?.stop();
  }

  void _onEvent(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerPanZoomStartEvent ||
        event is PointerScrollInertiaCancelEvent) {
      _stopMotion();
      return;
    }
    if (!_active ||
        (!_enabled && !widget.horizontalMouseWheel) ||
        event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        !widget.scrollable.mounted) {
      return;
    }
    // Use the same blur-safe modifiers as shortcuts instead of Flutter's cache.
    if (InputModifierScope.anyPressedOf(context, const [
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.altLeft,
      LogicalKeyboardKey.altRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    ])) {
      return;
    }
    final position = widget.scrollable.position;
    if (position is! ScrollActivityDelegate ||
        !position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final flip = InputModifierScope.anyPressedOf(context, widget.axisModifiers);
    final axis = flip ? flipAxis(position.axis) : position.axis;
    var delta = axis == Axis.vertical
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (widget.horizontalMouseWheel &&
        position.axis == Axis.horizontal &&
        !flip &&
        delta == 0) {
      delta = event.scrollDelta.dy;
    }
    if (axisDirectionIsReversed(position.axisDirection)) delta = -delta;
    if (!delta.isFinite || delta == 0) return;
    final header = HeaderScrollController.offsetFor(position);
    final pixels = header?.pixels ?? position.pixels;
    final next = (pixels + delta).clamp(
      header?.minScrollExtent ?? position.minScrollExtent,
      header?.maxScrollExtent ?? position.maxScrollExtent,
    );
    // At an edge, let an enclosing scrollable claim the event instead.
    if (next == pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted ||
          !_active ||
          !widget.scrollable.mounted ||
          !identical(position, widget.scrollable.position)) {
        return;
      }
      if (_enabled) {
        _scrollBy(position, delta);
      } else {
        position.pointerScroll(delta);
      }
      event.respond(allowPlatformDefault: false);
    });
  }

  void _scrollBy(ScrollPosition position, double delta) {
    final motion = _motion;
    if (motion != null &&
        !motion.disposed &&
        identical(position, motion.position)) {
      motion.addDelta(delta);
      return;
    }
    if (position case final ScrollActivityDelegate delegate) {
      final activity = _WheelScrollActivity(
        position,
        delegate,
        widget.scrollable.vsync,
        delta,
        dampingRatio: _dampingRatio,
      );
      _motion = activity;
      activity.begin();
    }
  }

  @override
  Widget build(BuildContext context) =>
      _WheelSignalListener(onEvent: _onEvent, child: widget.child);

  @override
  void dispose() {
    final motion = _motion;
    _motion = null;
    if (motion != null && !motion.disposed) {
      // The list's notification context may already be unmounted. Its position
      // will dispose the activity too; stop the ticker without dispatching then.
      if (motion.position.context.notificationContext?.mounted ?? false) {
        motion.stop();
      } else {
        motion.dispose();
      }
    }
    super.dispose();
  }
}

/// Retargets Flutter's scroll spring on one continuous frame clock.
final class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(
    ScrollPosition position,
    super.delegate,
    TickerProvider vsync,
    double delta, {
    required double dampingRatio,
  }) : _position = position,
       _header = HeaderScrollController.offsetFor(position),
       _spring = SpringDescription.withDampingRatio(
         mass: 1,
         stiffness: 1600,
         ratio: dampingRatio,
       ) {
    addDelta(delta);
    _ticker = vsync.createTicker(_tick)..start();
  }

  // The default ratio of 1.3 is overdamped for a softer stop without a rebound.
  final SpringDescription _spring;
  static const _maxPendingDistance = 1500.0; // Logical pixels.
  ScrollPosition _position;
  ScrollPosition get position => _position;
  final HeaderScrollOffset? _header;
  bool get coordinated => _header != null;
  double get _pixels => _header?.pixels ?? position.pixels;
  double get _min => _header?.minScrollExtent ?? position.minScrollExtent;
  double get _max => _header?.maxScrollExtent ?? position.maxScrollExtent;
  late final Ticker _ticker;
  late ScrollSpringSimulation _simulation;
  Duration _lastElapsed = Duration.zero;
  Duration _simulationStartedAt = Duration.zero;
  double _targetDistance = 0;
  double _lastSimulationPosition = 0;
  double _lastDelta = 0;
  double _velocity = 0;
  bool disposed = false;

  void begin() {
    if (_header case final header?) {
      header.beginActivity(this);
    } else {
      position.beginActivity(this);
    }
  }

  void addDelta(double delta) {
    final remaining = _targetDistance - _lastSimulationPosition;
    // Elastic ratios can already be rebounding when a new notch arrives.
    // Fresh input takes priority over motion or an endpoint behind that input.
    final reversing =
        (_lastDelta != 0 && delta.sign != _lastDelta.sign) ||
        (_velocity != 0 && delta.sign != _velocity.sign) ||
        (remaining != 0 && delta.sign != remaining.sign);
    if (reversing) _velocity = 0;
    _targetDistance =
        ((reversing ? 0 : remaining) +
                delta.clamp(-_maxPendingDistance, _maxPendingDistance))
            .clamp(-_maxPendingDistance, _maxPendingDistance)
            .toDouble();
    _simulation = ScrollSpringSimulation(
      _spring,
      0,
      _targetDistance,
      _velocity,
      // Match the display scale, ending within half a physical pixel instead
      // of chasing hundredths of a logical pixel. The simulator owns settling.
      tolerance: Tolerance(
        distance: .5 / position.devicePixelRatio,
        velocity: position.physics.toleranceFor(position).velocity,
      ),
    );
    _lastSimulationPosition = 0;
    _simulationStartedAt = _lastElapsed;
    _lastDelta = delta;
  }

  void _tick(Duration elapsed) {
    if (disposed || elapsed <= _lastElapsed) return;
    _lastElapsed = elapsed;
    if (!position.hasContentDimensions) {
      stop();
      return;
    }
    if (position.outOfRange) {
      // A resize can leave pixels outside the new extent while the activity is
      // moving. Correct on this frame, outside layout, before releasing it.
      delegate.setPixels(
        position.pixels.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        ),
      );
      if (!disposed) stop();
      return;
    }
    if (!position.physics.shouldAcceptUserOffset(position)) {
      stop();
      return;
    }
    final simulation = _simulation;
    final seconds = (elapsed - _simulationStartedAt).inMicroseconds / 1000000;
    final value = simulation.x(seconds);
    final distance = value - _lastSimulationPosition;
    _lastSimulationPosition = value;
    _velocity = simulation.dx(seconds);
    // Apply only the frame's displacement so layout can still correct pixels.
    final next = (_pixels + distance).clamp(_min, _max);
    final double overscroll;
    if (_header case final header?) {
      header.applyDelta(next - _pixels);
      overscroll = 0;
    } else {
      overscroll = delegate.setPixels(next);
    }
    // A scroll listener can take ownership while setPixels dispatches updates.
    if (!disposed &&
        ((identical(simulation, _simulation) && simulation.isDone(seconds)) ||
            _atBoundary ||
            overscroll != 0)) {
      stop();
    }
  }

  bool get _atBoundary => _lastDelta > 0 ? _pixels >= _max : _pixels <= _min;

  void stop() {
    if (disposed) return;
    if (_header case final header?) {
      header.goIdle();
    } else {
      delegate.goIdle();
    }
  }

  @override
  void applyNewDimensions() {
    // Some physics defer out-of-range correction while velocity is nonzero.
    // Keep the next tick so it can clamp to the new extent before stopping.
    if (position.outOfRange) return;
    // Layout owns any offset correction. Keep momentum if there is still room;
    // at an edge discard it even if more content may arrive later.
    if (_atBoundary || !position.physics.shouldAcceptUserOffset(position)) {
      stop();
    }
  }

  @override
  void updateDelegate(ScrollActivityDelegate value) {
    super.updateDelegate(value);
    if (value case final ScrollPosition position) {
      _position = position;
    } else {
      stop();
    }
  }

  @override
  bool get shouldIgnorePointer => false;

  @override
  bool get isScrolling => true;

  @override
  double get velocity => _velocity;

  @override
  void dispose() {
    if (disposed) return;
    disposed = true;
    _ticker.dispose();
    super.dispose();
  }
}

/// Register just before this Scrollable's native wheel listener. A normal outer
/// Listener runs too late, while an overlay would steal events from inner lists
/// and controls. Keep descendant hit targets and their transforms in order.
final class _WheelSignalListener extends SingleChildRenderObjectWidget {
  const _WheelSignalListener({required this.onEvent, required super.child});
  final void Function(PointerEvent) onEvent;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWheelSignalListener(onEvent);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWheelSignalListener renderObject,
  ) {
    renderObject.target.onEvent = onEvent;
  }
}

final class _WheelSignalTarget implements HitTestTarget {
  _WheelSignalTarget(this.onEvent);
  void Function(PointerEvent) onEvent;

  @override
  void handleEvent(PointerEvent event, HitTestEntry entry) => onEvent(event);
}

final class _RenderWheelSignalListener extends RenderProxyBox {
  _RenderWheelSignalListener(void Function(PointerEvent) onEvent)
    : target = _WheelSignalTarget(onEvent);
  final _WheelSignalTarget target;

  RenderPointerListener? _findListener(RenderObject node) {
    if (node is RenderPointerListener && node.onPointerSignal != null) {
      return node;
    }
    RenderPointerListener? listener;
    node.visitChildren((child) {
      listener ??= _findListener(child);
    });
    return listener;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final content = child;
    final listener = content == null ? null : _findListener(content);
    return super.hitTestChildren(
      listener == null ? result : _WheelHitTestResult(result, listener, target),
      position: position,
    );
  }
}

final class _WheelHitTestResult extends BoxHitTestResult {
  _WheelHitTestResult(super.result, this.listener, this.target) : super.wrap();
  final RenderPointerListener listener;
  final _WheelSignalTarget target;

  @override
  void add(HitTestEntry entry) {
    if (identical(entry.target, listener)) super.add(HitTestEntry(target));
    super.add(entry);
  }
}
