import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/presentation/workspace_activity.dart';

/// Adds short wheel transitions without replacing a list's controller/physics.
final class SmoothScrollBehavior extends MaterialScrollBehavior {
  const SmoothScrollBehavior();

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
    if (!desktop || context is! StatefulElement) return decorated;
    final scrollable = context.state;
    if (scrollable is! ScrollableState) return decorated;
    return _SmoothWheelScroll(
      scrollable: scrollable,
      axisModifiers: pointerAxisModifiers,
      child: decorated,
    );
  }
}

final class _SmoothWheelScroll extends StatefulWidget {
  const _SmoothWheelScroll({
    required this.scrollable,
    required this.axisModifiers,
    required this.child,
  });

  final ScrollableState scrollable;
  final Set<LogicalKeyboardKey> axisModifiers;
  final Widget child;

  @override
  State<_SmoothWheelScroll> createState() => _SmoothWheelScrollState();
}

final class _SmoothWheelScrollState extends State<_SmoothWheelScroll> {
  _WheelScrollActivity? _motion;
  bool _enabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final enabled =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled &&
        !MediaQuery.disableAnimationsOf(context);
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
    if (!_enabled ||
        event is! PointerScrollEvent ||
        event.kind != PointerDeviceKind.mouse ||
        !widget.scrollable.mounted) {
      return;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isMetaPressed) {
      return;
    }
    final position = widget.scrollable.position;
    if (position is! ScrollActivityDelegate ||
        !position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      return;
    }
    final flip = keyboard.logicalKeysPressed.any(widget.axisModifiers.contains);
    final axis = flip ? flipAxis(position.axis) : position.axis;
    var delta = axis == Axis.vertical
        ? event.scrollDelta.dy
        : event.scrollDelta.dx;
    if (axisDirectionIsReversed(position.axisDirection)) delta = -delta;
    if (!delta.isFinite || delta == 0) return;
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // At an edge, let an enclosing scrollable claim the event instead.
    if (next == position.pixels) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted ||
          !_enabled ||
          !widget.scrollable.mounted ||
          !identical(position, widget.scrollable.position)) {
        return;
      }
      _scrollBy(position, delta);
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
      );
      _motion = activity;
      position.beginActivity(activity);
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

/// A single frame clock follows a retargetable, critically damped spring.
/// Retargeting preserves velocity and never inserts a new animation's zero frame.
final class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(
    ScrollPosition position,
    super.delegate,
    TickerProvider vsync,
    double delta,
  ) : _position = position,
      _target = position.pixels {
    addDelta(delta);
    _ticker = vsync.createTicker(_tick)..start();
  }

  // Critical damping avoids bounce. A 120px notch reaches ~99% in 210ms.
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 1024,
    damping: 64,
  );
  static const _tolerance = Tolerance(distance: .1, velocity: 5);
  ScrollPosition _position;
  ScrollPosition get position => _position;
  late final Ticker _ticker;
  late ScrollSpringSimulation _simulation;
  Duration _lastElapsed = Duration.zero;
  Duration _simulationStart = Duration.zero;
  double _target;
  double _lastDelta = 0;
  double _velocity = 0;
  bool disposed = false;

  void addDelta(double delta) {
    final reversing = delta * _lastDelta < 0;
    if (reversing) _velocity = 0;
    final start = reversing ? position.pixels : _target;
    _target = (start + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _lastDelta = delta;
    _retarget();
  }

  void _retarget() {
    _simulationStart = _lastElapsed;
    _simulation = ScrollSpringSimulation(
      _spring,
      position.pixels,
      _target,
      _velocity,
      tolerance: _tolerance,
    );
  }

  void _tick(Duration elapsed) {
    if (disposed || elapsed == _lastElapsed) return;
    _lastElapsed = elapsed;
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      stop();
      return;
    }
    final seconds = (elapsed - _simulationStart).inMicroseconds / 1000000;
    final pixels = position.pixels;
    var next = _simulation.x(seconds);
    _velocity = _simulation.dx(seconds);
    // A resized viewport can move the target behind the remaining momentum.
    // Clamp between the displayed offset and target rather than overshooting.
    next = next.clamp(math.min(pixels, _target), math.max(pixels, _target));
    final settled = _simulation.isDone(seconds);
    final reached = next == _target;
    final overscroll = delegate.setPixels(settled ? _target : next);
    // A scroll listener can take ownership while setPixels dispatches updates.
    if (!disposed && (settled || reached || overscroll != 0)) stop();
  }

  void stop() {
    if (!disposed) delegate.goIdle();
  }

  @override
  void applyNewDimensions() {
    _target = _target
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (_velocity * (_target - position.pixels) < 0) _velocity = 0;
    _retarget();
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
