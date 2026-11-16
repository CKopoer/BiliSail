import 'package:material_ui/material_ui.dart';

import '../domain/high_energy_trend.dart';

/// A static path and base layer; playback only changes the foreground clip.
class HighEnergyCurve extends StatefulWidget {
  const HighEnergyCurve({
    super.key,
    required this.trend,
    required this.fraction,
    required this.height,
  });
  final HighEnergyTrend trend;
  final double fraction, height;

  @override
  HighEnergyCurveState createState() => HighEnergyCurveState();
}

class HighEnergyCurveState extends State<HighEnergyCurve> {
  Path? _path;
  Size? _size;
  HighEnergyTrend? _trend;
  Widget? _base;
  Widget? _foreground;
  Color? _color;
  TextDirection? _direction;
  int _pathBuildCount = 0;
  @visibleForTesting
  int get pathBuildCount => _pathBuildCount;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: ExcludeSemantics(
      child: SizedBox(
        height: widget.height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, widget.height);
            if (_size != size || !identical(_trend, widget.trend)) {
              _size = size;
              _trend = widget.trend;
              final path = Path()..moveTo(0, size.height);
              final points = widget.trend.points;
              if (points.isNotEmpty) {
                var previousX = points.first.fraction * size.width;
                var previousY = (1 - points.first.intensity) * size.height;
                path.lineTo(previousX, previousY);
                for (final point in points.skip(1)) {
                  final x = point.fraction * size.width;
                  final y = (1 - point.intensity) * size.height;
                  final middle = (previousX + x) / 2;
                  // Controls remain inside each segment's value range: no overshoot.
                  path.cubicTo(middle, previousY, middle, y, x, y);
                  previousX = x;
                  previousY = y;
                }
              }
              path
                ..lineTo(size.width, size.height)
                ..close();
              _path = path;
              _base = null;
              _foreground = null;
              _pathBuildCount++;
            }
            final color = Theme.of(context).colorScheme.primary;
            final direction = Directionality.of(context);
            if (_color != color || _direction != direction) {
              _color = color;
              _direction = direction;
              _base = null;
              _foreground = null;
            }
            final path = _path;
            if (path == null || size.width <= 0) return const SizedBox.shrink();
            final rtl = direction == TextDirection.rtl;
            _base ??= RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _CurvePainter(
                  path,
                  Colors.white.withValues(alpha: .16),
                  1,
                  rtl,
                ),
              ),
            );
            _foreground ??= RepaintBoundary(
              child: CustomPaint(
                size: size,
                painter: _CurvePainter(
                  path,
                  color.withValues(alpha: .32),
                  1,
                  rtl,
                ),
              ),
            );
            return Stack(
              children: [
                _base!,
                ClipRect(
                  clipper: _PlayedClipper(widget.fraction.clamp(0, 1), rtl),
                  child: _foreground!,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

class _PlayedClipper extends CustomClipper<Rect> {
  const _PlayedClipper(this.fraction, this.rtl);
  final double fraction;
  final bool rtl;
  @override
  Rect getClip(Size size) => Rect.fromLTWH(
    rtl ? size.width * (1 - fraction) : 0,
    0,
    size.width * fraction,
    size.height,
  );
  @override
  bool shouldReclip(covariant _PlayedClipper oldClipper) =>
      fraction != oldClipper.fraction || rtl != oldClipper.rtl;
}

class _CurvePainter extends CustomPainter {
  const _CurvePainter(this.path, this.color, this.fraction, this.rtl);
  final Path path;
  final Color color;
  final double fraction;
  final bool rtl;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    if (rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width * fraction, size.height));
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) =>
      !identical(path, oldDelegate.path) ||
      color != oldDelegate.color ||
      fraction != oldDelegate.fraction ||
      rtl != oldDelegate.rtl;
}
