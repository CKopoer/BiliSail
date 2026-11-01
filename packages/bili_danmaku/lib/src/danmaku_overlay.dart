import 'dart:async';

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
    widget.controller.addListener(_onControllerChanged);
    _onControllerChanged();
  }

  void _onControllerChanged() {
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
    // Clock confirmations retime the wake without repainting stationary text.
    // Content revisions also preserve the clearing frame after removal.
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
        if (mounted) _onControllerChanged();
      });
    } else if (widget.controller.needsFrame) {
      // The clock can cross a deadline after the caller's idle check. Drain
      // bounded admission even if no later clock/message notification arrives.
      _ticker.start();
      _repaint.value++;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _onControllerChanged();
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _paintedRevision = -1;
      widget.controller.addListener(_onControllerChanged);
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    _arrivalWake?.cancel();
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
            // Text bitmaps are cached separately; moving positions change
            // this picture. This hint does not schedule animation frames.
            willChange: true,
            painter: _DanmakuPainter(
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

final class _DanmakuPainter extends CustomPainter {
  _DanmakuPainter(
    this.controller,
    Listenable repaint,
    this.pixelRatio,
    this.onPainted,
  ) : super(repaint: repaint);
  final DanmakuController controller;
  final double pixelRatio;
  final VoidCallback onPainted;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    controller.paintFrame(canvas, pixelRatio: pixelRatio);
    onPainted();
  }

  @override
  bool shouldRepaint(_DanmakuPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      pixelRatio != oldDelegate.pixelRatio;
}
