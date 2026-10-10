import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'live_danmaku_controller.dart';

final class LiveDanmakuOverlay extends StatefulWidget {
  const LiveDanmakuOverlay({
    super.key,
    required this.controller,
    this.bottomInset = 64,
  });
  final LiveDanmakuController controller;
  final double bottomInset;
  @override
  State<LiveDanmakuOverlay> createState() => _LiveDanmakuOverlayState();
}

final class _LiveDanmakuOverlayState extends State<LiveDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final ValueNotifier<int> _repaint = ValueNotifier(0);
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (widget.controller.isAnimating) {
        _repaint.value++;
      } else {
        _ticker.stop();
      }
    });
    widget.controller.addListener(_changed);
    _changed();
  }

  void _changed() {
    if (widget.controller.isAnimating) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
    _repaint.value++;
  }

  @override
  void didUpdateWidget(covariant LiveDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth.isFinite && constraints.maxHeight.isFinite) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            widget.controller.setViewport(
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              bottomInset: widget.bottomInset,
            );
          }
        });
      }
      return IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _LivePainter(
              widget.controller,
              Listenable.merge([widget.controller, _repaint]),
              View.of(context).devicePixelRatio,
            ),
            size: Size.infinite,
          ),
        ),
      );
    },
  );
}

final class _LivePainter extends CustomPainter {
  _LivePainter(this.controller, Listenable repaint, this.pixelRatio)
    : super(repaint: repaint);
  final LiveDanmakuController controller;
  final double pixelRatio;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final item in controller.frame()) {
      controller.paintText(
        item.event,
        canvas,
        Offset(item.x, item.y),
        pixelRatio: pixelRatio,
      );
    }
  }

  @override
  bool shouldRepaint(_LivePainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      pixelRatio != oldDelegate.pixelRatio;
}
