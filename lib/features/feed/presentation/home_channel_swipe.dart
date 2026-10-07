import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../domain/home_channel.dart';

/// Touch channel navigation leaves nested scrollables in the gesture arena.
final class HomeChannelSwipe extends StatefulWidget {
  const HomeChannelSwipe({
    super.key,
    required this.channel,
    required this.onChanged,
    required this.child,
  });

  final HomeChannel channel;
  final ValueChanged<HomeChannel> onChanged;
  final Widget child;

  @override
  State<HomeChannelSwipe> createState() => _HomeChannelSwipeState();
}

final class _HomeChannelSwipeState extends State<HomeChannelSwipe> {
  HomeChannel? _dragChannel;
  double _distance = 0;

  void _reset() {
    _dragChannel = null;
    _distance = 0;
  }

  @override
  void didUpdateWidget(HomeChannelSwipe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!WorkspaceActivity.isActive(context)) _reset();
  }

  void _finish(DragEndDetails details, double width) {
    final channel = _dragChannel;
    final distance = _distance;
    _reset();
    if (channel != widget.channel || !WorkspaceActivity.isActive(context)) {
      return;
    }
    final velocity = details.primaryVelocity ?? 0;
    final fling = velocity.abs() >= 500 && distance.abs() >= 24;
    if (!fling && distance.abs() < (width * 0.2).clamp(48, 120)) return;
    final direction = fling ? velocity : distance;
    final forward = Directionality.of(context) == TextDirection.ltr
        ? direction < 0
        : direction > 0;
    final index = widget.channel.index + (forward ? 1 : -1);
    if (index >= 0 && index < HomeChannel.values.length) {
      widget.onChanged(HomeChannel.values[index]);
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    // Flutter also reports an accepted drag's pointer cancellation as drag
    // end. Clear it before that callback so interruptions cannot navigate.
    builder: (context, constraints) => Listener(
      onPointerCancel: (_) => _reset(),
      child: GestureDetector(
        key: const ValueKey('home-channel-swipe'),
        behavior: HitTestBehavior.opaque,
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: (_) {
          _dragChannel = widget.channel;
          _distance = 0;
        },
        onHorizontalDragUpdate: (details) =>
            _distance += details.primaryDelta ?? 0,
        onHorizontalDragEnd: (details) =>
            _finish(details, constraints.maxWidth),
        onHorizontalDragCancel: _reset,
        child: widget.child,
      ),
    ),
  );
}
