import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/presentation/input_scope.dart';
import '../../core/presentation/workspace_activity.dart';

class BottomNavigationScrollRegion extends StatefulWidget {
  const BottomNavigationScrollRegion({
    super.key,
    required this.destination,
    required this.enabled,
    required this.navigationBuilder,
    required this.child,
  });

  final Object destination;
  final bool enabled;
  final Widget Function(BuildContext, bool visible)? navigationBuilder;
  final Widget child;

  @override
  State<BottomNavigationScrollRegion> createState() =>
      _BottomNavigationScrollRegionState();
}

class _BottomNavigationScrollRegionState
    extends State<BottomNavigationScrollRegion> {
  static const _minimumTravel = 24.0;
  static const _wheelPause = Duration(milliseconds: 180);

  final _scrollingPagers = <BuildContext>{};
  bool _active = true;
  bool _visible = true;
  bool? _pendingVisibility;
  bool _updateScheduled = false;
  double _dragTravel = 0;
  double _wheelTravel = 0;
  Duration? _lastWheelInput;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = WorkspaceActivity.isActive(context);
    if (!_active) _reset();
  }

  @override
  void didUpdateWidget(BottomNavigationScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.destination != oldWidget.destination || !widget.enabled) {
      _reset();
    }
  }

  void _reset() {
    _visible = true;
    _pendingVisibility = null;
    _scrollingPagers.clear();
    _dragTravel = 0;
    _wheelTravel = 0;
    _lastWheelInput = null;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_active ||
        !widget.enabled ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _dragTravel = 0;
      if (notification.context case final pager?
          when notification.metrics is PageMetrics) {
        _scrollingPagers.add(pager);
      }
    } else if (notification is ScrollEndNotification) {
      if (_scrollingPagers.remove(notification.context)) _applyWhenSettled();
    } else {
      final dy = switch (notification) {
        ScrollUpdateNotification(:final dragDetails) => dragDetails?.delta.dy,
        OverscrollNotification(:final dragDetails) => dragDetails?.delta.dy,
        _ => null,
      };
      if (dy != null && dy.isFinite && dy != 0) {
        _dragTravel = _accumulate(_dragTravel, -dy);
      }
    }
    return false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!_active ||
        !widget.enabled ||
        event is! PointerScrollEvent ||
        (event.kind != PointerDeviceKind.mouse &&
            event.kind != PointerDeviceKind.trackpad) ||
        InputModifierScope.anyPressedOf(context, const [
          LogicalKeyboardKey.altLeft,
          LogicalKeyboardKey.altRight,
          LogicalKeyboardKey.controlLeft,
          LogicalKeyboardKey.controlRight,
          LogicalKeyboardKey.metaLeft,
          LogicalKeyboardKey.metaRight,
          LogicalKeyboardKey.shiftLeft,
          LogicalKeyboardKey.shiftRight,
        ])) {
      return;
    }
    final delta = event.scrollDelta;
    if (!delta.isFinite || delta.dy.abs() <= delta.dx.abs()) return;
    if (_lastWheelInput case final last?
        when event.timeStamp - last > _wheelPause) {
      _wheelTravel = 0;
    }
    _lastWheelInput = event.timeStamp;
    _wheelTravel = _accumulate(_wheelTravel, delta.dy);
  }

  double _accumulate(double previous, double delta) {
    final travel = previous.sign == delta.sign ? previous + delta : delta;
    if (travel.abs() < _minimumTravel) return travel;
    final visible = travel < 0;
    if ((_pendingVisibility ?? _visible) != visible) {
      _pendingVisibility = visible;
      _applyWhenSettled();
    }
    return 0;
  }

  void _applyWhenSettled() {
    if (_pendingVisibility == null || _updateScheduled) return;
    _updateScheduled = true;
    // Let the pointer signal resolve and the pager finish using its old extent
    // before resizing. Ballistic and programmatic updates supply no intent.
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _updateScheduled = false;
      _scrollingPagers.removeWhere((pager) => !pager.mounted);
      if (!mounted || _scrollingPagers.isNotEmpty) return;
      final pending = _pendingVisibility;
      _pendingVisibility = null;
      if (pending != null && pending != _visible) {
        setState(() => _visible = pending);
      }
    });
    binding.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Expanded(
        child: NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: Listener(
            onPointerSignal: _onPointerSignal,
            child: widget.child,
          ),
        ),
      ),
      if (widget.navigationBuilder case final buildNavigation?)
        buildNavigation(context, _visible),
    ],
  );
}
