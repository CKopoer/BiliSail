import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../core/presentation/input_scope.dart';
import '../../core/presentation/workspace_activity.dart';
import 'featured_bottom_navigation_scope.dart';

class BottomNavigationScrollRegion extends StatefulWidget {
  const BottomNavigationScrollRegion({
    super.key,
    required this.destination,
    required this.enabled,
    required this.navigationBuilder,
    required this.child,
    this.featuredNavigationHeight,
  });

  final Object destination;
  final bool enabled;
  final Widget Function(BuildContext, bool visible)? navigationBuilder;
  final Widget child;
  final double? featuredNavigationHeight;

  @override
  State<BottomNavigationScrollRegion> createState() =>
      _BottomNavigationScrollRegionState();
}

class _BottomNavigationScrollRegionState
    extends State<BottomNavigationScrollRegion> {
  static const _minimumTravel = 24.0;
  static const _wheelPause = Duration(milliseconds: 180);

  bool _active = true;
  bool _visible = true;
  bool? _pendingVisibility;
  bool _updateScheduled = false;
  double _dragTravel = 0;
  double _wheelTravel = 0;
  Duration? _lastWheelInput;

  bool get _usesFeaturedNavigation => widget.featuredNavigationHeight != null;
  bool get _reactsToScrolling =>
      _active && widget.enabled && !_usesFeaturedNavigation;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = WorkspaceActivity.isActive(context);
    if (!_active) _reset();
  }

  @override
  void didUpdateWidget(BottomNavigationScrollRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.destination != oldWidget.destination ||
        widget.featuredNavigationHeight != oldWidget.featuredNavigationHeight ||
        (!widget.enabled && !_usesFeaturedNavigation)) {
      _reset();
    }
  }

  void _reset() {
    _visible = true;
    _pendingVisibility = null;
    _dragTravel = 0;
    _wheelTravel = 0;
    _lastWheelInput = null;
  }

  bool _onScroll(ScrollNotification notification) {
    if (!_reactsToScrolling || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) {
      if (notification.dragDetails != null) _dragTravel = 0;
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
    if (!_reactsToScrolling ||
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
      _scheduleVisibility();
    }
    return 0;
  }

  void _scheduleVisibility() {
    if (_updateScheduled) return;
    _updateScheduled = true;
    // Apply scroll notifications after layout and let pointer signals resolve.
    final binding = WidgetsBinding.instance;
    binding.addPostFrameCallback((_) {
      _updateScheduled = false;
      if (!mounted) return;
      final pending = _pendingVisibility;
      _pendingVisibility = null;
      if (pending != null && pending != _visible) {
        setState(() => _visible = pending);
      }
    });
    binding.ensureVisualUpdate();
  }

  void _toggleFeaturedNavigation() {
    if (_active && _usesFeaturedNavigation) {
      setState(() => _visible = !_visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = widget.navigationBuilder?.call(context, _visible);
    final featuredHeight = widget.featuredNavigationHeight;
    return Stack(
      fit: StackFit.expand,
      children: [
        Column(
          children: [
            Expanded(
              child: FeaturedBottomNavigationScope(
                visible: _visible,
                onToggle: _toggleFeaturedNavigation,
                enabled: _usesFeaturedNavigation,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    child: widget.child,
                  ),
                ),
              ),
            ),
            if (featuredHeight == null)
              ?navigation
            else if (_visible && widget.enabled)
              // The bar animates separately without resizing the pager.
              SizedBox(height: featuredHeight),
          ],
        ),
        if (featuredHeight != null && navigation != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: featuredHeight,
            child: ClipRect(child: navigation),
          ),
      ],
    );
  }
}
