import 'dart:ui' as ui;

import 'package:canvas_danmaku/canvas_danmaku.dart' as upstream;
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import 'canvas_danmaku_renderer.dart';

enum DanmakuTextEffect { shadow, stroke, plain }

/// Cumulative local paint counters. A paint is one item on one rendered frame,
/// not one Flutter frame. Reading a snapshot never retains text or images.
@immutable
final class DanmakuRasterStatistics {
  const DanmakuRasterStatistics({
    required this.imagePaints,
    required this.cacheHits,
    required this.rasterBuilds,
    required this.dimensionFallbacks,
    required this.imageBudgetFallbacks,
    required this.workingSetFallbacks,
    required this.uncachedPaints,
    required this.peakRasterBytes,
  });

  final int imagePaints, cacheHits, rasterBuilds;
  final int dimensionFallbacks, imageBudgetFallbacks, workingSetFallbacks;
  final int uncachedPaints, peakRasterBytes;
  int get directPaints =>
      dimensionFallbacks +
      imageBudgetFallbacks +
      workingSetFallbacks +
      uncachedPaints;
  int get totalPaints => imagePaints + directPaints;
}

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
  final _renderer = CanvasDanmakuRenderer();

  void beginFrame(Canvas canvas, double pixelRatio) =>
      _renderer.beginFrame(canvas, pixelRatio);

  void endFrame() => _renderer.endFrame();
  // Blur and glyph overhang in logical pixels.
  static const _rasterPadding = 6.0;
  int _rasterBytes = 0;
  int get rasterBytes => _rasterBytes;
  int buildCount = 0;
  int rasterBuildCount = 0;
  int get length => _cache.length;
  int _imagePaints = 0;
  int _cacheHits = 0;
  int _dimensionFallbacks = 0;
  int _imageBudgetFallbacks = 0;
  int _workingSetFallbacks = 0;
  int _uncachedPaints = 0;
  int _peakRasterBytes = 0;

  DanmakuRasterStatistics get rasterStatistics => DanmakuRasterStatistics(
    imagePaints: _imagePaints,
    cacheHits: _cacheHits,
    rasterBuilds: rasterBuildCount,
    dimensionFallbacks: _dimensionFallbacks,
    imageBudgetFallbacks: _imageBudgetFallbacks,
    workingSetFallbacks: _workingSetFallbacks,
    uncachedPaints: _uncachedPaints,
    peakRasterBytes: _peakRasterBytes,
  );

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
      final cached = entry.raster;
      if (cached != null && cached.pixelRatio == ratio) {
        _cacheHits++;
        _paintRaster(entry, cached, canvas, offset);
        return;
      }
      if (cached != null) {
        _releaseRaster(entry);
      }
      // Dimensions and budget checks are needed only when preparing an image.
      final width = ((entry.fill.width + _rasterPadding * 2) * ratio).ceil();
      final height = ((entry.fill.height + _rasterPadding * 2) * ratio).ceil();
      final bytes = width * height * 4;
      // Extremely long/high-DPI lines keep their original paragraph drawing.
      if (width <= 4096 && height <= 4096 && bytes <= maxRasterBytes) {
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
          entry.paint(
            rasterCanvas,
            const Offset(_rasterPadding, _rasterPadding),
          );
          final picture = recorder.endRecording();
          entry.raster = _TextRaster(picture.toImageSync(width, height), ratio);
          picture.dispose();
          _rasters[entry] = bytes;
          _rasterBytes += bytes;
          if (_rasterBytes > _peakRasterBytes) _peakRasterBytes = _rasterBytes;
          rasterBuildCount++;
        }
      }
      final raster = entry.raster;
      if (raster != null) {
        _paintRaster(entry, raster, canvas, offset);
        return;
      }
      if (width > 4096 || height > 4096) {
        _dimensionFallbacks++;
      } else if (bytes > maxRasterBytes) {
        _imageBudgetFallbacks++;
      } else {
        _workingSetFallbacks++;
      }
    } else {
      _uncachedPaints++;
    }
    _renderer.flush();
    entry.paint(canvas, offset);
  }

  void _paintRaster(
    _TextLayout entry,
    _TextRaster raster,
    Canvas canvas,
    Offset offset,
  ) {
    _imagePaints++;
    final cost = _rasters.remove(entry);
    if (cost != null) _rasters[entry] = cost;
    _renderer.paintImage(
      canvas: canvas,
      image: raster.item,
      offset: offset - const Offset(_rasterPadding, _rasterPadding),
      pixelRatio: raster.pixelRatio,
    );
  }

  void _releaseRaster(_TextLayout entry) {
    // A small layout cache can evict an image queued earlier in this frame.
    // Submit its borrowed draw before releasing the sole owning reference.
    _renderer.flush();
    _rasterBytes -= _rasters.remove(entry) ?? 0;
    entry.raster?.image.dispose();
    entry.raster = null;
  }

  void releaseRasters() {
    for (final entry in _rasters.keys.toList(growable: false)) {
      _releaseRaster(entry);
    }
    _protectedKeys.clear();
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
  _TextRaster? raster;
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

/// Geometry shares the image lifetime so cached draws never remeasure text or
/// query native image dimensions. Replacing the DPR replaces both together.
final class _TextRaster {
  _TextRaster(this.image, this.pixelRatio)
    : item = upstream.DanmakuItem<void>(
        content: upstream.DanmakuContentItem<void>(''),
        width: image.width / pixelRatio,
        height: image.height / pixelRatio,
        image: image,
      );

  final ui.Image image;
  final double pixelRatio;
  final upstream.DanmakuItem<void> item;
}
