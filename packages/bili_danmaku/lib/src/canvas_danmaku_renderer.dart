import 'dart:ui' as ui;

import 'package:canvas_danmaku/base_danmaku_painter.dart';
import 'package:canvas_danmaku/canvas_danmaku.dart' as upstream;
import 'package:flutter/painting.dart';

/// Adapts the upstream batching/compositing pipeline to externally timed items.
///
/// The scheduler owns positions and the bounded text cache owns images. Using
/// DanmakuScreen here would introduce a second animation clock and lose paused
/// seek reconstruction. No upstream controller, ticker or image owner is added.
final class CanvasDanmakuRenderer {
  final _items = <_PositionedImage>[];
  final _pool = <_PositionedImage>[];
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
      BaseDanmakuPainter.paintImg(canvas, image, offset.dx, offset.dy);
      return;
    }
    assert(identical(_canvas, canvas) && _pixelRatio == pixelRatio);
    if (_used == _pool.length) {
      _pool.add(
        _PositionedImage(
          upstream.DanmakuItem<void>(content: _content, width: 0, height: 0),
        ),
      );
    }
    final positioned = _pool[_used++]
      ..x = offset.dx
      ..y = offset.dy;
    positioned.item
      ..image = image.image
      ..width = image.width
      ..height = image.height;
    _items.add(positioned);
  }

  /// Flush before direct-text fallbacks to preserve mixed-mode arrival order.
  void flush() {
    final canvas = _canvas;
    if (canvas == null || _items.isEmpty) return;
    _painter.paint(canvas, Size.zero);
    for (final item in _items) {
      // Images are borrowed; only DanmakuTextLayouts disposes them.
      item.item.image = null;
    }
    _items.clear();
  }

  void endFrame() {
    try {
      flush();
    } finally {
      _canvas = null;
      for (final item in _items) {
        item.item.image = null;
      }
      _items.clear();
    }
  }
}

final class _PositionedImage {
  _PositionedImage(this.item);
  final upstream.DanmakuItem<void> item;
  double x = 0, y = 0;
}

/// Uses PiliPlus's upstream image sampling with externally prepared positions.
/// Its painter base exposes sampling, but batching lives in its final scrolling
/// painter, so this adapter groups the same draws without advancing that clock.
final class _PositionedDanmakuPainter extends BaseDanmakuPainter {
  _PositionedDanmakuPainter(this.items)
    : super(
        length: 0,
        fontSize: 24,
        fontWeight: 3,
        strokeWidth: 0,
        running: false,
        tick: 0,
      );

  final List<_PositionedImage> items;

  @override
  void paint(Canvas canvas, Size size) {
    final recorder = items.length > batchThreshold
        ? ui.PictureRecorder()
        : null;
    final target = recorder == null ? canvas : Canvas(recorder);
    for (final positioned in items) {
      BaseDanmakuPainter.paintImg(
        target,
        positioned.item,
        positioned.x,
        positioned.y,
      );
    }
    if (recorder != null) {
      final picture = recorder.endRecording();
      canvas.drawPicture(picture);
      picture.dispose();
    }
  }
}
