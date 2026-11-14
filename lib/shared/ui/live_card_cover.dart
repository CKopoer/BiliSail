import 'package:flutter/material.dart';

import '../../core/presentation/workspace_activity.dart';
import '../../features/live/domain/live_room.dart';
import 'card_hover_preview.dart';
import 'live_card_preview_scope.dart';

class LiveCardCover extends StatefulWidget {
  const LiveCardCover({
    super.key,
    required this.roomId,
    required this.hovered,
    required this.child,
    this.previewEnabled = true,
    this.borderRadius = 6,
  });

  final RoomId roomId;
  final bool hovered;
  final Widget child;
  final bool previewEnabled;
  final double borderRadius;

  @override
  State<LiveCardCover> createState() => _LiveCardCoverState();
}

class _LiveCardCoverState extends State<LiveCardCover> {
  bool _snapBack = false;

  @override
  void didUpdateWidget(LiveCardCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hovered != widget.hovered) {
      _snapBack = false;
      if (widget.hovered) return;
      context.visitAncestorElements((element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          _snapBack = (element.state as ScrollableState)
              .position
              .isScrollingNotifier
              .value;
        }
        return !_snapBack;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = LiveCardPreviewScope.maybeOf(context);
    final active =
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    return AnimatedScale(
      key: const ValueKey('live-card-cover-scale'),
      scale: active && widget.hovered ? 1.05 : 1,
      duration: _snapBack || MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(widget.borderRadius),
        child: Stack(
          fit: StackFit.expand,
          children: [
            widget.child,
            if (active &&
                widget.hovered &&
                widget.previewEnabled &&
                widget.roomId.isValid &&
                scope != null &&
                scope.enabled)
              CardHoverPreview(
                key: const ValueKey('live-card-hover-preview'),
                sourceKey: (widget.roomId, scope.controller),
                load: (token) => scope.controller.preview(widget.roomId, token),
                showProgress: false,
                previewKey: const ValueKey('live-card-preview'),
              ),
          ],
        ),
      ),
    );
  }
}
