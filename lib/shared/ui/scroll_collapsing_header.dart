import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;

import '../../core/presentation/workspace_activity.dart';

class ScrollHeaderRegion extends StatefulWidget {
  const ScrollHeaderRegion({
    super.key,
    required this.enabled,
    required this.child,
    this.identity,
  });

  final bool enabled;
  final Object? identity;
  final Widget child;

  static bool isEnabled(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_HeaderScope>()?.enabled ??
      false;

  @override
  State<ScrollHeaderRegion> createState() => _ScrollHeaderRegionState();
}

class _ScrollHeaderRegionState extends State<ScrollHeaderRegion> {
  final _expanded = ValueNotifier(true);

  @override
  void didUpdateWidget(ScrollHeaderRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled ||
        widget.identity != oldWidget.identity) {
      _expanded.value = true;
    }
  }

  bool _onScroll(UserScrollNotification notification) {
    final origin = notification.context;
    if (!widget.enabled ||
        notification.metrics.axis != Axis.vertical ||
        origin == null ||
        !WorkspaceActivity.isActive(origin)) {
      return false;
    }
    switch (notification.direction) {
      case ScrollDirection.forward:
        _expanded.value = true;
      case ScrollDirection.reverse:
        // A short list or a bouncing top edge must not hide its controls.
        if (!notification.metrics.outOfRange &&
            notification.metrics.extentAfter > 0) {
          _expanded.value = false;
        }
      case ScrollDirection.idle:
        break;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) => _HeaderScope(
    enabled: widget.enabled,
    expanded: _expanded,
    child: NotificationListener<UserScrollNotification>(
      onNotification: _onScroll,
      child: widget.child,
    ),
  );

  @override
  void dispose() {
    _expanded.dispose();
    super.dispose();
  }
}

class _HeaderScope extends InheritedWidget {
  const _HeaderScope({
    required this.enabled,
    required this.expanded,
    required super.child,
  });

  final bool enabled;
  final ValueListenable<bool> expanded;

  @override
  bool updateShouldNotify(_HeaderScope oldWidget) =>
      enabled != oldWidget.enabled || expanded != oldWidget.expanded;
}

class ScrollCollapsingHeader extends StatelessWidget {
  const ScrollCollapsingHeader({
    super.key,
    required this.child,
    this.enabled = true,
  });

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<_HeaderScope>();
    if (scope == null) return child;
    final animate = !MediaQuery.disableAnimationsOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: scope.expanded,
      child: child,
      builder: (context, expanded, child) {
        final visible = !enabled || !scope.enabled || expanded;
        return ExcludeFocus(
          excluding: !visible,
          child: ExcludeSemantics(
            excluding: !visible,
            child: IgnorePointer(
              ignoring: !visible,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 1, end: visible ? 1 : 0),
                duration: animate
                    ? const Duration(milliseconds: 240)
                    : Duration.zero,
                curve: Curves.easeInOutCubic,
                child: child,
                builder: (context, value, child) => ClipRect(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    heightFactor: value,
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
