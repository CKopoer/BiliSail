import 'package:canvas_danmaku/base_danmaku_painter.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart' as upstream;
import 'package:flutter/painting.dart';

/// Adapts the upstream batching/compositing pipeline to externally timed items.
///
/// The scheduler owns positions and the bounded text cache owns images. Using
/// DanmakuScreen here would introduce a second animation clock and lose paused
/// seek reconstruction. No upstream controller, ticker or image owner is added.
final class CanvasDanmakuRenderer {
  final _items = <upstream.DanmakuItem<void>>[];
  final _pool = <upstream.DanmakuItem<void>>[];
  static final _content = upstream.DanmakuContentItem<void>('');
  late final _painter = _PositionedDanmakuPainter(_items);
  Canvas? _canvas;
  double _pixelRatio = 1;
  int _used = 0;

  void beginFrame(Canvas canvas, double pixelRatio) {
    assert(_canvas == null);
    _canvas = canvas;
    _pixelRatio = pixelRatio;
    _used = 0;
  }

  void paintImage({
    required Canvas canvas,
    required upstream.DanmakuItem<void> image,
    required Offset offset,
    required double pixelRatio,
  }) {
    // A standalone text paint (e.g. diagnostics) uses the same compositor.
    if (_canvas == null) {
      BaseDanmakuPainter.paintImg(
        canvas,
        image,
        offset.dx,
        offset.dy,
        pixelRatio,
      );
      return;
    }
    assert(identical(_canvas, canvas) && _pixelRatio == pixelRatio);
    if (_used == _pool.length) {
      _pool.add(
        upstream.DanmakuItem<void>(content: _content, width: 0, height: 0),
      );
    }
    final item = _pool[_used++]
      ..image = image.image
      ..width = image.width
      ..height = image.height
      ..xPosition = offset.dx
      ..yPosition = offset.dy;
    _items.add(item);
  }

  /// Flush before direct-text fallbacks to preserve mixed-mode arrival order.
  void flush() {
    final canvas = _canvas;
    if (canvas == null || _items.isEmpty) return;
    _painter.pixelRatio = _pixelRatio;
    _painter.paint(canvas, Size.zero);
    for (final item in _items) {
      // Images are borrowed; only DanmakuTextLayouts disposes them.
      item.image = null;
    }
    _items.clear();
  }

  void endFrame() {
    try {
      flush();
    } finally {
      _canvas = null;
      for (final item in _items) {
        item.image = null;
      }
      _items.clear();
    }
  }
}

/// Upstream owns batching, picture disposal and image sampling. External
/// positions preserve the existing collision, fullscreen and two-clock rules.
final class _PositionedDanmakuPainter extends BaseDanmakuPainter {
  _PositionedDanmakuPainter(List<upstream.DanmakuItem<void>> items)
    : super(
        length: 0,
        danmakuItems: items,
        fontSize: 24,
        fontWeight: 3,
        strokeWidth: 0,
        devicePixelRatio: 1,
        running: false,
        tick: 0,
      );

  double pixelRatio = 1;

  @override
  void paintDanmaku(
    Canvas canvas,
    Size size,
    upstream.DanmakuItem<Object?> item,
  ) {
    BaseDanmakuPainter.paintImg(
      canvas,
      item,
      item.xPosition,
      item.yPosition,
      pixelRatio,
    );
  }
}
