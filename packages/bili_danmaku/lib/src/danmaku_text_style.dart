import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

enum DanmakuTextEffect { shadow, stroke, plain }

@immutable
final class DanmakuTextStyle {
  const DanmakuTextStyle({
    this.fontFamily,
    this.bold = false,
    this.effect = DanmakuTextEffect.shadow,
  });
  final String? fontFamily;
  final bool bold;
  final DanmakuTextEffect effect;

  @override
  bool operator ==(Object other) =>
      other is DanmakuTextStyle &&
      fontFamily == other.fontFamily &&
      bold == other.bold &&
      effect == other.effect;
  @override
  int get hashCode => Object.hash(fontFamily, bold, effect);
}

/// Both clocks share bounded text layout and painting, never scheduling state.
final class DanmakuTextLayouts {
  DanmakuTextLayouts(this.capacity, {this.maxRasterBytes = 32 * 1024 * 1024})
    : assert(capacity > 0),
      assert(maxRasterBytes >= 0);
  // Scaled text can be smaller than the protocol's unscaled font sizes.
  static const minFontSize = 1.0;
  final int capacity;

  /// RGBA pixel budget, separate from the bounded native paragraph cache.
  final int maxRasterBytes;
  DanmakuTextStyle _style = const DanmakuTextStyle();
  DanmakuTextStyle get style => _style;
  set style(DanmakuTextStyle value) {
    if (_style == value) return;
    clear();
    _style = value;
  }

  final _cache = <(double, int, String), _TextLayout>{};
  final _rasters = <_TextLayout, int>{};
  final _protectedKeys = <(double, int, String)>{};
  int _rasterBytes = 0;
  int get rasterBytes => _rasterBytes;
  int buildCount = 0;
  int rasterBuildCount = 0;
  int get length => _cache.length;

  /// Avoid cyclic bitmap eviction when the visible working set exceeds the
  /// pixel budget: keep resident visible images and draw overflow as text.
  void protectRasters(Iterable<(String, Color, double)> visible) {
    _protectedKeys.clear();
    for (final (text, color, size) in visible) {
      _protectedKeys.add((
        size.clamp(minFontSize, 54.0),
        color.toARGB32(),
        text,
      ));
    }
  }

  TextPainter layout(String text, Color color, double fontSize) =>
      _entry(text, color, fontSize).fill;

  _TextLayout _entry(String text, Color color, double fontSize) {
    final size = fontSize.clamp(minFontSize, 54.0);
    final key = (size, color.toARGB32(), text);
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    TextPainter make({bool outline = false}) => TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: style.fontFamily,
          fontWeight: style.bold ? FontWeight.bold : FontWeight.normal,
          fontSize: size,
          color: outline ? null : color,
          foreground: outline
              ? (Paint()
                  ..color = const Color(0xff000000)
                  ..style = PaintingStyle.stroke
                  ..strokeWidth = 2)
              : null,
          shadows: !outline && style.effect == DanmakuTextEffect.shadow
              ? const [Shadow(color: Color(0xff000000), blurRadius: 2)]
              : null,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final entry = _TextLayout(
      key,
      make(),
      style.effect == DanmakuTextEffect.stroke
          ? () => make(outline: true)
          : null,
    );
    buildCount++;
    _cache[key] = entry;
    if (_cache.length > capacity) {
      final evicted = _cache.remove(_cache.keys.first);
      if (evicted != null) {
        _releaseRaster(evicted);
        evicted.dispose();
      }
    }
    return entry;
  }

  void paint(
    String text,
    Color color,
    double fontSize,
    Canvas canvas,
    Offset offset, {
    double pixelRatio = 1,
    bool cacheRaster = true,
  }) {
    final entry = _entry(text, color, fontSize);
    // Rasterize only painted text at the actual display DPR. Moving images
    // avoids per-frame glyph/effect rendering, especially blurred shadows.
    // The native paragraphs remain available for pixel-budget overflow.
    if (cacheRaster) {
      final ratio = pixelRatio.isFinite && pixelRatio > 0 ? pixelRatio : 1.0;
      if (entry.image != null && entry.pixelRatio != ratio) {
        _releaseRaster(entry);
      }
      const padding = 6.0; // Covers the 2px blur plus glyph overhang.
      final width = ((entry.fill.width + padding * 2) * ratio).ceil();
      final height = ((entry.fill.height + padding * 2) * ratio).ceil();
      final bytes = width * height * 4;
      // Extremely long/high-DPI lines keep their original paragraph drawing.
      if (entry.image == null &&
          width <= 4096 &&
          height <= 4096 &&
          bytes <= maxRasterBytes) {
        while (_rasterBytes + bytes > maxRasterBytes && _rasters.isNotEmpty) {
          _TextLayout? victim;
          for (final candidate in _rasters.keys) {
            if (!_protectedKeys.contains(candidate.key)) {
              victim = candidate;
              break;
            }
          }
          if (victim == null) break;
          _releaseRaster(victim);
        }
        if (_rasterBytes + bytes <= maxRasterBytes) {
          final recorder = ui.PictureRecorder();
          final rasterCanvas = Canvas(recorder)..scale(ratio);
          entry.paint(rasterCanvas, const Offset(padding, padding));
          final picture = recorder.endRecording();
          entry.image = picture.toImageSync(width, height);
          picture.dispose();
          entry.pixelRatio = ratio;
          _rasters[entry] = bytes;
          _rasterBytes += bytes;
          rasterBuildCount++;
        }
      }
      final image = entry.image;
      if (image != null) {
        final cost = _rasters.remove(entry);
        if (cost != null) _rasters[entry] = cost;
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          Rect.fromLTWH(
            offset.dx - padding,
            offset.dy - padding,
            image.width / ratio,
            image.height / ratio,
          ),
          Paint()..filterQuality = FilterQuality.low,
        );
        return;
      }
    }
    entry.paint(canvas, offset);
  }

  void _releaseRaster(_TextLayout entry) {
    _rasterBytes -= _rasters.remove(entry) ?? 0;
    entry.image?.dispose();
    entry.image = null;
  }

  void clear() {
    for (final entry in _cache.values) {
      _releaseRaster(entry);
      entry.dispose();
    }
    _cache.clear();
    _protectedKeys.clear();
  }
}

final class _TextLayout {
  _TextLayout(this.key, this.fill, this._makeOutline);
  final (double, int, String) key;
  final TextPainter fill;
  final TextPainter Function()? _makeOutline;
  TextPainter? _outline;
  ui.Image? image;
  double pixelRatio = 1;
  void paint(Canvas canvas, Offset offset) {
    final makeOutline = _makeOutline;
    if (makeOutline != null) {
      (_outline ??= makeOutline()).paint(canvas, offset);
    }
    fill.paint(canvas, offset);
  }

  void dispose() {
    fill.dispose();
    _outline?.dispose();
  }
}
