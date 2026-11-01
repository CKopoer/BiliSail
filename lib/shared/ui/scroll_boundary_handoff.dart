import 'package:flutter/material.dart';

import 'scroll_collapsing_header.dart';

/// Lets a bounded vertical list finish a touch gesture in its enclosing scroll
/// view. The list remains lazy and keeps its own controller and scroll position.
final class ScrollBoundaryHandoff extends StatefulWidget {
  const ScrollBoundaryHandoff({super.key, required this.child});

  final Widget child;

  @override
  State<ScrollBoundaryHandoff> createState() => _ScrollBoundaryHandoffState();
}

final class _ScrollBoundaryHandoffState extends State<ScrollBoundaryHandoff> {
  bool _forwardedDrag = false;

  ScrollPosition? get _outer =>
      Scrollable.maybeOf(context, axis: Axis.vertical)?.position;

  bool _canMove(ScrollPosition position, double delta) {
    final header = HeaderScrollController.offsetFor(position);
    final pixels = header?.pixels ?? position.pixels;
    return delta < 0
        ? pixels > (header?.minScrollExtent ?? position.minScrollExtent)
        : delta > 0 &&
              pixels < (header?.maxScrollExtent ?? position.maxScrollExtent);
  }

  bool _onScroll(ScrollNotification notification) {
    // Horizontal section strips and any deeper scrollables retain their own
    // gesture/wheel handling. Programmatic jumps do not trigger a handoff.
    if (notification.depth != 0 || notification.metrics.axis != Axis.vertical) {
      return false;
    }
    if (notification is ScrollStartNotification) _forwardedDrag = false;
    final outer = _outer;
    if (outer == null || !outer.hasContentDimensions) return false;
    if (notification is OverscrollNotification &&
        (notification.dragDetails != null || notification.velocity != 0) &&
        _canMove(outer, notification.overscroll)) {
      outer.pointerScroll(notification.overscroll);
      if (notification.dragDetails != null) {
        _forwardedDrag = true;
      } else {
        // The inner ballistic activity stops at its clamped edge. Continue
        // with its remaining velocity rather than losing the fling there.
        if (outer case final ScrollActivityDelegate delegate) {
          delegate.goBallistic(notification.velocity);
        }
      }
    } else if (notification is ScrollEndNotification) {
      final details = notification.dragDetails;
      if (_forwardedDrag && details != null) {
        final velocity = -details.velocity.pixelsPerSecond.dy;
        final metrics = notification.metrics;
        final atEdge = velocity < 0
            ? metrics.pixels <= metrics.minScrollExtent
            : metrics.pixels >= metrics.maxScrollExtent;
        if (atEdge &&
            _canMove(outer, velocity) &&
            outer is ScrollActivityDelegate) {
          (outer as ScrollActivityDelegate).goBallistic(velocity);
        }
      }
      _forwardedDrag = false;
    }
    return false;
  }

  @override
  Widget build(
    BuildContext context,
  ) => NotificationListener<ScrollNotification>(
    onNotification: _onScroll,
    child: Listener(
      onPointerDown: (_) {
        if (_outer case final ScrollActivityDelegate delegate) {
          delegate.goIdle();
        }
      },
      child: ScrollConfiguration(
        // Bouncing physics consumes the delta beyond an edge itself. Clamp only
        // the nested viewport so its remainder can reach the outer page, even
        // for a short list that fits entirely inside the episode panel.
        behavior: ScrollConfiguration.of(context).copyWith(
          physics: _outer == null
              ? null
              : const ClampingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics(),
                ),
        ),
        child: widget.child,
      ),
    ),
  );
}
