import 'package:flutter/widgets.dart';

import 'bili_icons.dart';

class BiliCoinIcon extends StatelessWidget {
  const BiliCoinIcon({super.key, required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) {
    if (!filled) return const Icon(BiliIcons.coin);
    final theme = IconTheme.of(context);
    final color = theme.color ?? const Color(0xff000000);
    return SizedBox.square(
      dimension: theme.size ?? 24,
      child: CustomPaint(
        painter: _FilledCoinPainter(
          color.withValues(alpha: color.a * (theme.opacity ?? 1)),
        ),
      ),
    );
  }
}

class _FilledCoinPainter extends CustomPainter {
  const _FilledCoinPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    // Cut the 币 strokes into the coin instead of painting a background color.
    final symbol = Path()
      ..addRect(const Rect.fromLTWH(7.5, 6.5, 9, 1.7))
      ..addRect(const Rect.fromLTWH(11.15, 7, 1.7, 11))
      ..addRect(const Rect.fromLTWH(7.5, 10, 9, 1.7))
      ..addRect(const Rect.fromLTWH(7.5, 10, 1.7, 6.5))
      ..addRect(const Rect.fromLTWH(14.8, 10, 1.7, 6.5));
    final path = Path.combine(
      PathOperation.difference,
      Path()..addOval(const Rect.fromLTWH(2, 2, 20, 20)),
      symbol,
    );
    canvas.drawPath(path, Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_FilledCoinPainter oldDelegate) =>
      color != oldDelegate.color;
}
