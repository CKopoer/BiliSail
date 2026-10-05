import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'danmaku_controller.dart';

/// A single ticker repaints only this layer; no per-comment animation widgets.
final class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.controller,
    this.bottomInset = 0,
  });
  final DanmakuController controller;
  final double bottomInset;

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

final class _DanmakuOverlayState extends State<DanmakuOverlay>
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
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  void _onControllerChanged() {
    if (widget.controller.isAnimating) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
    _repaint.value++;
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
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
            painter: _DanmakuPainter(
              widget.controller,
              Listenable.merge([widget.controller, _repaint]),
            ),
            size: Size.infinite,
          ),
        ),
      );
    },
  );
}

final class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(this.controller, Listenable repaint)
    : super(repaint: repaint);
  final DanmakuController controller;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    for (final placement in controller.frame()) {
      controller.paintText(
        placement.event,
        canvas,
        Offset(placement.x, placement.y),
      );
    }
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller);
}
