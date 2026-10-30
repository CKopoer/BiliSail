import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/presentation/workspace_activity.dart';

/// Retains pointer presence while suppressing hover effects during scrolling.
/// Every ancestor must be idle before a stationary pointer becomes hovered.
final class ScrollAwareHoverRegion extends StatefulWidget {
  const ScrollAwareHoverRegion({
    super.key,
    required this.onHover,
    required this.child,
  });

  final ValueChanged<bool> onHover;
  final Widget child;

  @override
  State<ScrollAwareHoverRegion> createState() => _ScrollAwareHoverRegionState();
}

final class _ScrollAwareHoverRegionState extends State<ScrollAwareHoverRegion> {
  final _positions = <ScrollPosition>{};
  bool _pointerInside = false;
  bool _hovered = false;
  bool _active = true;
  bool _checkScheduled = false;
  Widget? _region;

  @override
  void didUpdateWidget(ScrollAwareHoverRegion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) _region = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Scrollable.maybeOf(context);
    _active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    _syncScrollPositions();
    _updateHover();
  }

  void _syncScrollPositions() {
    final positions = <ScrollPosition>{};
    // Touch-only cards have no hover to suppress. Subscribe on actual pointer
    // entry, preserving external mice/stylus hover on mobile without scanning
    // every retained card's ancestors on primary navigation.
    if (_active && _pointerInside) {
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          positions.add((element.state as ScrollableState).position);
        }
        return true;
      });
    }
    for (final position in _positions.difference(positions)) {
      position.isScrollingNotifier.removeListener(_updateHover);
    }
    for (final position in positions.difference(_positions)) {
      position.isScrollingNotifier.addListener(_updateHover);
    }
    _positions
      ..clear()
      ..addAll(positions);
  }

  void _updateHover() {
    // The owner already suspends hidden content. Retain its last hover value
    // so restoring a page does not need an extra frame before preview delay.
    if (!_active) return;
    final hovered =
        _pointerInside &&
        !_positions.any((position) => position.isScrollingNotifier.value);
    if (hovered == _hovered) return;
    // A viewport can end its scroll activity during layout. Notify the owner
    // after that frame rather than marking an already built ancestor dirty.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_checkScheduled) return;
      _checkScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkScheduled = false;
        if (mounted) _updateHover();
      });
      return;
    }
    _hovered = hovered;
    widget.onHover(hovered);
  }

  void _setPointerInside(bool inside) {
    _pointerInside = inside;
    _syncScrollPositions();
    _updateHover();
  }

  @override
  void deactivate() {
    _clearScrollPositions();
    super.deactivate();
  }

  void _clearScrollPositions() {
    for (final position in _positions) {
      position.isScrollingNotifier.removeListener(_updateHover);
    }
    _positions.clear();
  }

  @override
  Widget build(BuildContext context) => _region ??= MouseRegion(
    onEnter: (_) => _setPointerInside(true),
    onExit: (_) => _setPointerInside(false),
    child: widget.child,
  );

  @override
  void dispose() {
    _clearScrollPositions();
    super.dispose();
  }
}
