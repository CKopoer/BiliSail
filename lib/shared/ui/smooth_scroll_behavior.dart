import '../../core/presentation/motion_preferences.dart';

import 'dart:collection';

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:scroll_animator/scroll_animator.dart';
import 'package:smooth_scroll_multiplatform/smooth_scroll_multiplatform.dart';

import '../../core/presentation/input_scope.dart';
import '../../core/presentation/workspace_activity.dart';
import '../../domain/wheel_scroll_animation.dart';
import 'scroll_collapsing_header.dart';

/// Keeps local ScrollConfiguration overrides on the same wheel preference.
final class SmoothScrollScope extends InheritedWidget {
  const SmoothScrollScope({
    super.key,
    required this.dampingRatio,
    this.animation = defaultWheelScrollAnimation,
    this.chromiumCurve = ChromiumScrollCurve.easeInOut,
    this.distanceMultiplier = 1,
    this.durationMultiplier = defaultWheelScrollDurationMultiplier,
    required super.child,
  }) : assert(dampingRatio > 0 && dampingRatio < double.infinity),
       assert(distanceMultiplier > 0 && distanceMultiplier < double.infinity),
       assert(durationMultiplier > 0 && durationMultiplier < double.infinity);

  final double dampingRatio;
  final WheelScrollAnimation animation;
  final ChromiumScrollCurve chromiumCurve;
  final double distanceMultiplier;
  final double durationMultiplier;

  static SmoothScrollScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SmoothScrollScope>();

  static WheelScrollAnimation animationOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SmoothScrollScope>()
          ?.animation ??
      defaultWheelScrollAnimation;

  static double dampingRatioOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<SmoothScrollScope>()
          ?.dampingRatio ??
      1.3;

  @override
  bool updateShouldNotify(SmoothScrollScope oldWidget) =>
      dampingRatio != oldWidget.dampingRatio ||
      animation != oldWidget.animation ||
      chromiumCurve != oldWidget.chromiumCurve ||
      distanceMultiplier != oldWidget.distanceMultiplier ||
      durationMultiplier != oldWidget.durationMultiplier;
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
    final nested = context.findAncestorStateOfType<NestedScrollViewState>();
    // The outer position can finish a fling while the body keeps scrolling.
    // Stretching that viewport would briefly move its pinned headers too.
    final isNestedOuter =
        nested != null && identical(details.controller, nested.outerController);
    final decorated = isNestedOuter
        ? child
        : super.buildOverscrollIndicator(context, child, details);
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
  WheelScrollAnimation _animation = defaultWheelScrollAnimation;
  ChromiumScrollCurve _chromiumCurve = ChromiumScrollCurve.easeInOut;
  double _distanceMultiplier = 1;
  double _durationMultiplier = defaultWheelScrollDurationMultiplier;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final dampingRatio = SmoothScrollScope.dampingRatioOf(context);
    final animation = SmoothScrollScope.animationOf(context);
    final scope = SmoothScrollScope.maybeOf(context);
    final chromiumCurve = scope?.chromiumCurve ?? ChromiumScrollCurve.easeInOut;
    final distanceMultiplier = scope?.distanceMultiplier ?? 1;
    final durationMultiplier =
        scope?.durationMultiplier ?? defaultWheelScrollDurationMultiplier;
    if (animation != _animation ||
        distanceMultiplier != _distanceMultiplier ||
        (animation != WheelScrollAnimation.spring &&
            durationMultiplier != _durationMultiplier) ||
        (animation == WheelScrollAnimation.chromium &&
            chromiumCurve != _chromiumCurve) ||
        (animation == WheelScrollAnimation.spring &&
            dampingRatio != _dampingRatio)) {
      _stopMotion();
    }
    _animation = animation;
    _chromiumCurve = chromiumCurve;
    _distanceMultiplier = distanceMultiplier;
    _durationMultiplier = durationMultiplier;
    _dampingRatio = dampingRatio;
    _active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    final enabled = _active && !shouldReduceMotion(context);
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
    final baseSpeed = _animation == WheelScrollAnimation.multiplatform
        ? SmoothScrollDefaults.scrollSpeed
        : 1.0;
    delta = (delta * _distanceMultiplier * baseSpeed)
        .clamp(
          -_WheelScrollActivity._maxPendingDistance,
          _WheelScrollActivity._maxPendingDistance,
        )
        .toDouble();
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
        _scrollBy(position, delta, event.timeStamp);
      } else {
        position.pointerScroll(delta);
      }
      event.respond(allowPlatformDefault: false);
    });
  }

  void _scrollBy(ScrollPosition position, double delta, Duration timeStamp) {
    final motion = _motion;
    if (motion != null &&
        !motion.disposed &&
        identical(position, motion.position)) {
      motion.addDelta(delta, timeStamp);
      return;
    }
    if (position case final ScrollActivityDelegate delegate) {
      final activity = _WheelScrollActivity(
        position,
        delegate,
        widget.scrollable.vsync,
        delta,
        timeStamp: timeStamp,
        dampingRatio: _dampingRatio,
        animation: _animation,
        chromiumCurve: _chromiumCurve,
        durationMultiplier: _durationMultiplier,
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

/// Coordinates the selected wheel animation with retained/nested positions.
/// Its controller cannot own NestedScrollView's coordinator-created positions.
/// Keep event/frame timing here: AnimatedScrollActivity retargets by wall clock.
final class _WheelScrollActivity extends ScrollActivity {
  _WheelScrollActivity(
    ScrollPosition position,
    super.delegate,
    TickerProvider vsync,
    double delta, {
    required double dampingRatio,
    required WheelScrollAnimation animation,
    required this.chromiumCurve,
    required double durationMultiplier,
    required Duration timeStamp,
  }) : _position = position,
       _firstInputTimeStamp = timeStamp,
       _header = HeaderScrollController.offsetFor(position),
       _mode = animation,
       _durationMultiplier = animation == WheelScrollAnimation.spring
           ? 1
           : durationMultiplier,
       _spring = animation == WheelScrollAnimation.spring
           ? SpringDescription.withDampingRatio(
               mass: 1,
               stiffness: 1600,
               ratio: dampingRatio,
             )
           : null {
    _newMotion(0, 0);
    addDelta(delta, timeStamp);
    _ticker = vsync.createTicker(_tick)..start();
  }

  final SpringDescription? _spring;
  final WheelScrollAnimation _mode;
  final ChromiumScrollCurve chromiumCurve;
  final double _durationMultiplier;
  Simulation? _simulation;
  double _simulationTarget = 0;
  int _revision = 0;
  final Duration _firstInputTimeStamp;
  static const _maxPendingDistance = 1500.0; // Logical pixels.
  static const _maxQueuedInputs = 64;
  final _pendingInputs = ListQueue<({Duration elapsed, double delta})>();
  ScrollPosition _position;
  ScrollPosition get position => _position;
  final HeaderScrollOffset? _header;
  bool get coordinated => _header != null;
  double get _pixels => _header?.pixels ?? position.pixels;
  double get _min => _header?.minScrollExtent ?? position.minScrollExtent;
  double get _max => _header?.maxScrollExtent ?? position.maxScrollExtent;
  late final Ticker _ticker;
  late ScrollAnimation _animation;
  Duration _lastElapsed = Duration.zero;
  Duration? _frameTimeOffset;
  Duration? _lastSystemFrameTimeStamp;
  bool _hasFrame = false;
  Duration _animationStartedAt = Duration.zero;
  double _lastAnimationPosition = 0;
  double _unappliedDistance = 0;
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

  Duration _scaledTime(Duration time) =>
      Duration(microseconds: (time.inMicroseconds / timeDilation).round());

  Duration _elapsedAtInput(Duration timeStamp) {
    // Synthetic/platform events without a timestamp keep the frame-clock path.
    var elapsed = _lastElapsed;
    if (_firstInputTimeStamp > Duration.zero && timeStamp > Duration.zero) {
      final frame = _lastSystemFrameTimeStamp;
      elapsed = frame == null
          ? _scaledTime(timeStamp - _firstInputTimeStamp)
          : _lastElapsed + _scaledTime(timeStamp - frame);
    }
    // Queued input may predate the last painted frame. Never rewind that frame
    // or another input already incorporated into the animation.
    if (elapsed < _lastElapsed) elapsed = _lastElapsed;
    if (elapsed < _animationStartedAt) elapsed = _animationStartedAt;
    if (_pendingInputs.isNotEmpty && elapsed < _pendingInputs.last.elapsed) {
      elapsed = _pendingInputs.last.elapsed;
    }
    return elapsed;
  }

  void addDelta(double delta, Duration timeStamp) {
    final elapsed = _elapsedAtInput(timeStamp);
    if (_pendingInputs.isEmpty && elapsed <= _lastElapsed) {
      _retarget(delta, elapsed);
      return;
    }
    // An event can arrive after vsync but before that frame's ticker callback.
    // Keep it for its own frame, rather than evaluating an animation at negative
    // time or applying its unpainted movement ahead of the frame timestamp.
    if (_pendingInputs.length == _maxQueuedInputs) {
      final last = _pendingInputs.removeLast();
      delta = last.delta.sign == delta.sign
          ? (last.delta + delta)
                .clamp(-_maxPendingDistance, _maxPendingDistance)
                .toDouble()
          : delta;
    }
    _pendingInputs.add((elapsed: elapsed, delta: delta));
    if (_velocity != 0 && delta.sign != _velocity.sign) _velocity = 0;
  }

  void _retarget(double delta, Duration elapsed) {
    final time = _animationTime(elapsed);
    final value = _valueAt(time);
    final remaining = _targetValue - value;
    final velocity = _velocityAt(time);
    final reversing =
        (_lastDelta != 0 && delta.sign != _lastDelta.sign) ||
        (velocity != 0 && delta.sign != velocity.sign) ||
        (remaining != 0 && delta.sign != remaining.sign);
    _velocity = reversing ? 0 : velocity;
    // Carry the displacement up to this input into the frame's one pixel
    // update, including multiple wheel events delivered between two frames.
    _unappliedDistance = reversing
        ? 0
        : _unappliedDistance + value - _lastAnimationPosition;
    final pendingDistance =
        ((reversing ? 0 : remaining) +
                _unappliedDistance +
                delta.clamp(-_maxPendingDistance, _maxPendingDistance))
            .clamp(-_maxPendingDistance, _maxPendingDistance)
            .toDouble();
    final target = pendingDistance - _unappliedDistance;
    if (_mode != WheelScrollAnimation.chromium ||
        reversing ||
        _lastDelta == 0) {
      _newMotion(target, _velocity);
      _lastAnimationPosition = 0;
      _animationStartedAt = elapsed;
    } else {
      // The package owns the continuous curve and velocity at the new target.
      _animation.updateTargetValue(time, Offset(0, value + target));
      _revision++;
      _lastAnimationPosition = value;
    }
    _lastDelta = delta;
  }

  void _newMotion(double distance, double velocity) {
    _revision++;
    if (_spring case final spring?) {
      _simulationTarget = distance;
      _simulation = ScrollSpringSimulation(
        spring,
        0,
        distance,
        velocity,
        tolerance: Tolerance(
          distance: .5 / position.devicePixelRatio,
          velocity: position.physics.toleranceFor(position).velocity,
        ),
      );
    } else if (_mode == WheelScrollAnimation.multiplatform) {
      _simulationTarget = distance;
      _simulation = SmoothScrollSimulation(start: 0, end: distance);
    } else {
      final ScrollAnimationFactory factory = switch (chromiumCurve) {
        ChromiumScrollCurve.easeInOut => const ChromiumEaseInOut(),
        ChromiumScrollCurve.impulse => const ChromiumImpulse(),
      };
      _animation = factory.createScrollAnimation(
        Offset.zero,
        Offset(0, distance),
        .pointer,
      );
    }
  }

  double get _targetValue =>
      _simulation == null ? _animation.targetValue.dy : _simulationTarget;

  Duration _animationTime(Duration elapsed) => Duration(
    microseconds:
        ((elapsed - _animationStartedAt).inMicroseconds / _durationMultiplier)
            .round(),
  );

  bool _isDone(Duration time) =>
      _simulation?.isDone(time.inMicroseconds / 1000000) ??
      (time >= _animation.duration);

  double _valueAt(Duration time) =>
      _simulation?.x(time.inMicroseconds / 1000000) ??
      (_isDone(time)
          ? _animation.targetValue.dy
          : _animation.getValue(time).dy);

  double _velocityAt(Duration time) =>
      (_simulation?.dx(time.inMicroseconds / 1000000) ??
          (_isDone(time) ? 0 : _animation.getVelocity(time).dy)) /
      _durationMultiplier;

  void _tick(Duration elapsed) {
    if (disposed) return;
    final frame = SchedulerBinding.instance.currentSystemFrameTimeStamp;
    // A warm-up frame has no engine timestamp to align with pointer events.
    if (_firstInputTimeStamp > Duration.zero && frame == Duration.zero) return;
    _frameTimeOffset ??= _firstInputTimeStamp > Duration.zero
        ? _scaledTime(frame - _firstInputTimeStamp) - elapsed
        : Duration.zero;
    elapsed += _frameTimeOffset!;
    _lastSystemFrameTimeStamp = frame;
    if (_hasFrame && elapsed <= _lastElapsed) return;
    _hasFrame = true;
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
    while (_pendingInputs.isNotEmpty &&
        _pendingInputs.first.elapsed <= elapsed) {
      final input = _pendingInputs.removeFirst();
      _retarget(input.delta, input.elapsed);
    }
    if (elapsed < _animationStartedAt) return;
    final revision = _revision;
    final time = _animationTime(elapsed);
    final value = _valueAt(time);
    final distance = _unappliedDistance + value - _lastAnimationPosition;
    _unappliedDistance = 0;
    _lastAnimationPosition = value;
    _velocity = _velocityAt(time);
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
    if (disposed) return;
    if (_atBoundary && _pendingInputs.isNotEmpty) {
      // Keep later input, but discard the motion that already hit this edge.
      // Appending content before that input's frame must not revive old travel.
      _discardMomentum(elapsed);
      return;
    }
    final settled = revision == _revision && _isDone(time);
    if (overscroll != 0 ||
        (_pendingInputs.isEmpty && (settled || _atBoundary))) {
      stop();
    }
  }

  bool get _atBoundary => _lastDelta > 0 ? _pixels >= _max : _pixels <= _min;

  void _discardMomentum(Duration elapsed) {
    _lastAnimationPosition = 0;
    _unappliedDistance = 0;
    _velocity = 0;
    _animationStartedAt = elapsed;
    _newMotion(0, 0);
  }

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
    if ((_atBoundary && _pendingInputs.isEmpty) ||
        !position.physics.shouldAcceptUserOffset(position)) {
      stop();
    } else if (_atBoundary) {
      _discardMomentum(_lastElapsed);
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
    _pendingInputs.clear();
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
