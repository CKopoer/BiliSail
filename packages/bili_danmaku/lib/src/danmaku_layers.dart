import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'danmaku_text_style.dart';

abstract interface class LayeredDanmakuController implements Listenable {
  bool get needsFrame;
  Duration? get nextFrameDelay;
  int get visualRevision;
  DanmakuPaintLayers get paintLayers;
  void preparePaintLayers();
  void setViewport({
    required double width,
    required double height,
    double bottomInset = 0,
  });
}

// Positions are prepared once per ticker frame. The two painters never advance
// admission, so splitting layers cannot double the per-frame admission budget.
final class DanmakuPaintLayers {
  DanmakuPaintLayers(this._layouts);
  final DanmakuTextLayouts _layouts;
  final _scrolling = <_PositionedText>[];
  final _fixed = <_PositionedText>[];
  int _scrollingUsed = 0, _fixedUsed = 0;
  bool _scrollingChanged = false, _fixedChanged = false;
  DanmakuTextStyle? _style;
  int _scrollingRevision = 0, _fixedRevision = 0;
  int get scrollingRevision => _scrollingRevision;
  int get fixedRevision => _fixedRevision;

  void beginFrame() {
    _scrollingUsed = _fixedUsed = 0;
    _scrollingChanged = _fixedChanged = _style != _layouts.style;
    _style = _layouts.style;
  }

  void add({
    required bool scrolling,
    required String text,
    required Color color,
    required double fontSize,
    required double x,
    required double y,
    bool isColorful = false,
  }) {
    final items = scrolling ? _scrolling : _fixed;
    final index = scrolling ? _scrollingUsed++ : _fixedUsed++;
    var changed = index == items.length;
    if (changed) {
      items.add(_PositionedText(text, color, fontSize, x, y, isColorful));
    } else {
      final item = items[index];
      changed =
          item.text != text ||
          item.color != color ||
          item.isColorful != isColorful ||
          item.fontSize != fontSize ||
          item.x != x ||
          item.y != y;
      item
        ..text = text
        ..color = color
        ..isColorful = isColorful
        ..fontSize = fontSize
        ..x = x
        ..y = y;
    }
    if (scrolling) {
      _scrollingChanged |= changed;
    } else {
      _fixedChanged |= changed;
    }
  }

  void endFrame() {
    if (_scrolling.length != _scrollingUsed) {
      _scrolling.removeRange(_scrollingUsed, _scrolling.length);
      _scrollingChanged = true;
    }
    if (_fixed.length != _fixedUsed) {
      _fixed.removeRange(_fixedUsed, _fixed.length);
      _fixedChanged = true;
    }
    if (_scrollingChanged) _scrollingRevision++;
    if (_fixedChanged) _fixedRevision++;
  }

  void paint(
    Canvas canvas, {
    required bool scrolling,
    required double pixelRatio,
  }) {
    _layouts.beginFrame(canvas, pixelRatio);
    try {
      for (final item in scrolling ? _scrolling : _fixed) {
        _layouts.paint(
          item.text,
          item.color,
          item.fontSize,
          canvas,
          Offset(item.x, item.y),
          pixelRatio: pixelRatio,
          isColorful: item.isColorful,
        );
      }
    } finally {
      _layouts.endFrame();
    }
  }

  void clear() {
    _scrolling.clear();
    _fixed.clear();
    _scrollingRevision++;
    _fixedRevision++;
  }
}

final class _PositionedText {
  _PositionedText(
    this.text,
    this.color,
    this.fontSize,
    this.x,
    this.y,
    this.isColorful,
  );
  String text;
  Color color;
  bool isColorful;
  double fontSize, x, y;
}

// Like PiliPlus, moving text is below fixed text and each has its own retained
// paint boundary. The caller still applies one opacity to the complete group.
final class LayeredDanmakuOverlay extends StatefulWidget {
  const LayeredDanmakuOverlay({
    super.key,
    required this.controller,
    required this.bottomInset,
  });
  final LayeredDanmakuController controller;
  final double bottomInset;

  @override
  State<LayeredDanmakuOverlay> createState() => _LayeredDanmakuOverlayState();
}

final class _LayeredDanmakuOverlayState extends State<LayeredDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _scrollingRepaint = ValueNotifier(0);
  final _fixedRepaint = ValueNotifier(0);
  Timer? _arrivalWake;
  int _preparedRevision = -1, _scrollingRevision = -1, _fixedRevision = -1;
  bool _tickerEnabled = true;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    widget.controller.addListener(_changed);
    _changed();
  }

  void _tick(Duration _) {
    final controller = widget.controller;
    controller.preparePaintLayers();
    _preparedRevision = controller.visualRevision;
    final layers = controller.paintLayers;
    if (_scrollingRevision != layers.scrollingRevision) {
      _scrollingRevision = layers.scrollingRevision;
      _scrollingRepaint.value++;
    }
    if (_fixedRevision != layers.fixedRevision) {
      _fixedRevision = layers.fixedRevision;
      _fixedRepaint.value++;
    }
    if (!controller.needsFrame) {
      _ticker.stop();
      _scheduleArrival();
    }
  }

  void _changed() {
    _arrivalWake?.cancel();
    if (!_tickerEnabled) {
      _ticker.stop();
      return;
    }
    if (widget.controller.needsFrame ||
        widget.controller.visualRevision != _preparedRevision) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      _ticker.stop();
      _scheduleArrival();
    }
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
      // A monotonic deadline can cross between the idle and delay checks.
      _ticker.start();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _changed();
  }

  @override
  void didUpdateWidget(covariant LayeredDanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget.controller, oldWidget.controller)) {
      oldWidget.controller.removeListener(_changed);
      _preparedRevision = _scrollingRevision = _fixedRevision = -1;
      widget.controller.addListener(_changed);
      _changed();
    }
  }

  @override
  void dispose() {
    _arrivalWake?.cancel();
    widget.controller.removeListener(_changed);
    _ticker.dispose();
    _scrollingRepaint.dispose();
    _fixedRepaint.dispose();
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
      final ratio =
          MediaQuery.maybeDevicePixelRatioOf(context) ??
          View.of(context).devicePixelRatio;
      return IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            for (final scrolling in [true, false])
              RepaintBoundary(
                key: ValueKey(
                  scrolling ? 'danmaku-scrolling-layer' : 'danmaku-fixed-layer',
                ),
                child: CustomPaint(
                  willChange: scrolling,
                  painter: _DanmakuLayerPainter(
                    widget.controller.paintLayers,
                    scrolling ? _scrollingRepaint : _fixedRepaint,
                    scrolling: scrolling,
                    pixelRatio: ratio,
                  ),
                  size: Size.infinite,
                ),
              ),
          ],
        ),
      );
    },
  );
}

final class _DanmakuLayerPainter extends CustomPainter {
  _DanmakuLayerPainter(
    this.layers,
    Listenable repaint, {
    required this.scrolling,
    required this.pixelRatio,
  }) : super(repaint: repaint);
  final DanmakuPaintLayers layers;
  final bool scrolling;
  final double pixelRatio;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    layers.paint(canvas, scrolling: scrolling, pixelRatio: pixelRatio);
  }

  @override
  bool shouldRepaint(_DanmakuLayerPainter oldDelegate) =>
      !identical(layers, oldDelegate.layers) ||
      scrolling != oldDelegate.scrolling ||
      pixelRatio != oldDelegate.pixelRatio;
}
