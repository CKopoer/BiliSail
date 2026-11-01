import 'dart:async';

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
  Timer? _arrivalWake;
  int _paintedRevision = -1;
  bool _tickerEnabled = true;
  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      if (widget.controller.needsFrame) {
        _repaint.value++;
      } else {
        _ticker.stop();
        _scheduleArrival();
      }
    });
    widget.controller.addListener(_changed);
    _changed();
  }

  void _changed() {
    _arrivalWake?.cancel();
    if (!_tickerEnabled) {
      _ticker.stop();
      return;
    }
    final needsFrame = widget.controller.needsFrame;
    if (needsFrame) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
    }
    if (needsFrame || widget.controller.visualRevision != _paintedRevision) {
      _repaint.value++;
    }
    _scheduleArrival();
  }

  void _scheduleArrival() {
    _arrivalWake?.cancel();
    if (!_tickerEnabled || _ticker.isActive) return;
    final delay = widget.controller.nextFrameDelay;
    if (delay != null) {
      _arrivalWake = Timer(delay, () {
        if (mounted) _changed();
      });
    } else if (widget.controller.needsFrame) {
      // Catch deadlines crossed between the idle check and wake calculation.
      _ticker.start();
      _repaint.value++;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _changed();
  }

  @override
  void didUpdateWidget(covariant LiveDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      _paintedRevision = -1;
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    _arrivalWake?.cancel();
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
            // Cache text bitmaps, rather than the continuously moving picture.
            willChange: true,
            painter: _LivePainter(
              widget.controller,
              _repaint,
              MediaQuery.maybeDevicePixelRatioOf(context) ??
                  View.of(context).devicePixelRatio,
              () => _paintedRevision = widget.controller.visualRevision,
            ),
            size: Size.infinite,
          ),
        ),
      );
    },
  );
}

final class _LivePainter extends CustomPainter {
  _LivePainter(
    this.controller,
    Listenable repaint,
    this.pixelRatio,
    this.onPainted,
  ) : super(repaint: repaint);
  final LiveDanmakuController controller;
  final double pixelRatio;
  final VoidCallback onPainted;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    controller.paintFrame(canvas, pixelRatio: pixelRatio);
    onPainted();
  }

  @override
  bool shouldRepaint(_LivePainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      pixelRatio != oldDelegate.pixelRatio;
}
