import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../core/presentation/input_scope.dart';
import '../../core/presentation/workspace_activity.dart';

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
    if (!desktop || context is! StatefulElement) return decorated;
    final scrollable = context.state;
    if (scrollable is! ScrollableState) return decorated;
    return _SmoothWheelScroll(
      scrollable: scrollable,
      axisModifiers: pointerAxisModifiers,
      horizontalMouseWheel: horizontalMouseWheel,
      child: decorated,
    );
  }
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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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
    final next = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // At an edge, let an enclosing scrollable claim the event instead.
    if (next == position.pixels) return;
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

/// Wheel impulses drive a velocity that decays while the displayed velocity
/// follows smoothly. One frame clock integrates motion without a position target.
final class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(
    ScrollPosition position,
    super.delegate,
    TickerProvider vsync,
    double delta,
  ) : _position = position {
    addDelta(delta);
    _ticker = vsync.createTicker(_tick)..start();
  }

  // Seconds. The short response smooths wheel impulses; the longer decay lets
  // successive notches build speed. An uncapped impulse integrates to its delta.
  static const _decaySeconds = .075;
  static const _responseSeconds = .020;
  static const _maxDriveVelocity = 24000.0; // Logical pixels / second.
  static const _distanceTolerance = .01; // Remaining logical pixels.
  static const _velocityTolerance = 5.0; // Logical pixels / second.
  ScrollPosition _position;
  ScrollPosition get position => _position;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;
  double _lastDelta = 0;
  double _driveVelocity = 0;
  double _velocity = 0;
  bool disposed = false;

  void addDelta(double delta) {
    if (_lastDelta != 0 && delta.sign != _lastDelta.sign) {
      _driveVelocity = 0;
      _velocity = 0;
    }
    _driveVelocity = (_driveVelocity + delta / _decaySeconds)
        .clamp(-_maxDriveVelocity, _maxDriveVelocity)
        .toDouble();
    _lastDelta = delta;
  }

  void _tick(Duration elapsed) {
    if (disposed || elapsed <= _lastElapsed) return;
    final seconds = (elapsed - _lastElapsed).inMicroseconds / 1000000;
    _lastElapsed = elapsed;
    if (!position.hasContentDimensions ||
        !position.physics.shouldAcceptUserOffset(position)) {
      stop();
      return;
    }
    final previousDrive = _driveVelocity;
    final previousVelocity = _velocity;
    final decay = math.exp(-seconds / _decaySeconds);
    final response = math.exp(-seconds / _responseSeconds);
    _driveVelocity = previousDrive * decay;
    // Exact integration of du/dt = -u/decay and dv/dt = (u-v)/response.
    // This avoids frame-rate-dependent Euler steps at 60/120Hz or delayed frames.
    _velocity =
        previousVelocity * response +
        previousDrive *
            _decaySeconds /
            (_decaySeconds - _responseSeconds) *
            (decay - response);
    var distance =
        _decaySeconds * (previousDrive - _driveVelocity) +
        _responseSeconds * (previousVelocity - _velocity);
    final remainingDistance =
        _decaySeconds * _driveVelocity + _responseSeconds * _velocity;
    final settled =
        remainingDistance.abs() < _distanceTolerance &&
        _velocity.abs() < _velocityTolerance;
    if (settled) {
      // Integrate the subpixel tail once so separate gestures do not accumulate
      // rounding loss. There is still no stored endpoint to chase or snap to.
      distance += remainingDistance;
      _driveVelocity = 0;
      _velocity = 0;
    }
    final next = (position.pixels + distance).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    final overscroll = delegate.setPixels(next);
    // A scroll listener can take ownership while setPixels dispatches updates.
    if (!disposed && (settled || _atBoundary || overscroll != 0)) stop();
  }

  bool get _atBoundary => _lastDelta > 0
      ? position.pixels >= position.maxScrollExtent
      : position.pixels <= position.minScrollExtent;

  void stop() {
    if (!disposed) delegate.goIdle();
  }

  @override
  void applyNewDimensions() {
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
