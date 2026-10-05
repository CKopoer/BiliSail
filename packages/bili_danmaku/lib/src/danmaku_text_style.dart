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
  DanmakuTextLayouts(this.capacity);
  final int capacity;
  DanmakuTextStyle style = const DanmakuTextStyle();
  final _cache = <String, _TextLayout>{};
  int get length => _cache.length;

  TextPainter layout(String text, Color color, double fontSize) =>
      _entry(text, color, fontSize).fill;

  _TextLayout _entry(String text, Color color, double fontSize) {
    final size = fontSize.clamp(12.0, 54.0);
    final key = '$size|${color.toARGB32()}|$text';
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
      make(),
      style.effect == DanmakuTextEffect.stroke ? make(outline: true) : null,
    );
    _cache[key] = entry;
    if (_cache.length > capacity) _cache.remove(_cache.keys.first)?.dispose();
    return entry;
  }

  void paint(
    String text,
    Color color,
    double fontSize,
    Canvas canvas,
    Offset offset,
  ) {
    final entry = _entry(text, color, fontSize);
    entry.outline?.paint(canvas, offset);
    entry.fill.paint(canvas, offset);
  }

  void clear() {
    for (final entry in _cache.values) {
      entry.dispose();
    }
    _cache.clear();
  }
}

final class _TextLayout {
  const _TextLayout(this.fill, this.outline);
  final TextPainter fill;
  final TextPainter? outline;
  void dispose() {
    fill.dispose();
    outline?.dispose();
  }
}
