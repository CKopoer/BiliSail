import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  static const _duration = Duration(milliseconds: 160);
  ScrollPosition? _position;
  double? _target;
  double _lastDelta = 0;
  int _generation = 0;
  bool _startingAnimation = false;
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

  void _forgetTarget() {
    _generation++;
    _position = null;
    _target = null;
    _lastDelta = 0;
  }

  void _stopMotion() {
    final position = _position;
    _forgetTarget();
    if (position != null &&
        widget.scrollable.mounted &&
        identical(position, widget.scrollable.position) &&
        position.hasPixels) {
      position.jumpTo(position.pixels);
    }
  }

  void _onEvent(PointerEvent event) {
    if (event is PointerDownEvent ||
        event is PointerPanZoomStartEvent ||
        event is PointerScrollInertiaCancelEvent) {
      // The normal scrollable handles the drag/hold or inertia cancellation.
      _forgetTarget();
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
    if (!position.hasContentDimensions ||
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
      if (!mounted || !_enabled || !widget.scrollable.mounted) return;
      _scrollBy(position, delta);
      event.respond(allowPlatformDefault: false);
    });
  }

  void _scrollBy(ScrollPosition position, double delta) {
    final continuing =
        identical(position, _position) &&
        _target != null &&
        delta * _lastDelta > 0;
    final start = continuing ? _target ?? position.pixels : position.pixels;
    final target = (start + delta)
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    _position = position;
    _target = target;
    _lastDelta = delta;
    final generation = ++_generation;
    _startingAnimation = true;
    final Future<void> motion;
    try {
      motion = position.animateTo(
        target,
        duration: _duration,
        curve: Curves.easeOutCubic,
      );
    } finally {
      _startingAnimation = false;
    }
    unawaited(
      motion.then((_) {
        if (mounted && generation == _generation) _forgetTarget();
      }),
    );
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth == 0 &&
        !_startingAnimation &&
        (notification is ScrollStartNotification ||
            notification is ScrollEndNotification)) {
      // Refresh, return-to-top, scrollbar drag and touch take ownership.
      _forgetTarget();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: _WheelSignalListener(onEvent: _onEvent, child: widget.child),
      );

  @override
  void dispose() {
    _forgetTarget();
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
