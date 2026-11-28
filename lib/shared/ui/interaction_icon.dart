import 'package:flutter/widgets.dart';

import '../../core/presentation/workspace_activity.dart';

enum InteractionGlyph {
  like,
  coin,
  favorite,
  comment,
  share,
  external,
  download,
}

class InteractionIcon extends StatefulWidget {
  const InteractionIcon(
    this.glyph, {
    super.key,
    this.selected = false,
    this.size,
    this.color,
  });

  final InteractionGlyph glyph;
  final bool selected;
  final double? size;
  final Color? color;

  @override
  State<InteractionIcon> createState() => _InteractionIconState();
}

class _InteractionIconState extends State<InteractionIcon>
    with SingleTickerProviderStateMixin {
  static final _pulse = TweenSequence<double>([
    TweenSequenceItem(tween: Tween(begin: 1, end: .92), weight: 18),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: .92,
        end: 1.13,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 42,
    ),
    TweenSequenceItem(
      tween: Tween<double>(
        begin: 1.13,
        end: 1,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
      weight: 40,
    ),
  ]);

  AnimationController? _controller;
  bool _animate = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate =
        !MediaQuery.disableAnimationsOf(context) &&
        WorkspaceActivity.isActive(context) &&
        TickerMode.valuesOf(context).enabled;
    if (!_animate) _controller?.reset();
  }

  @override
  void didUpdateWidget(InteractionIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.selected || oldWidget.glyph != widget.glyph) {
      _controller?.reset();
    } else if (!oldWidget.selected && _animate) {
      final controller = _controller ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 240),
      );
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = IconTheme.of(context);
    final color = widget.color ?? theme.color ?? const Color(0xff000000);
    final icon = SizedBox.square(
      dimension: widget.size ?? theme.size ?? 24,
      child: CustomPaint(
        painter: _InteractionGlyphPainter(
          widget.glyph,
          color.withValues(alpha: color.a * (theme.opacity ?? 1)),
          widget.selected,
        ),
      ),
    );
    final controller = _controller;
    return controller == null
        ? icon
        : ScaleTransition(scale: controller.drive(_pulse), child: icon);
  }
}

class _InteractionGlyphPainter extends CustomPainter {
  const _InteractionGlyphPainter(this.glyph, this.color, this.selected);

  final InteractionGlyph glyph;
  final Color color;
  final bool selected;

  static final _thumb = Path()
    ..moveTo(8.6, 10.3)
    ..cubicTo(10.9, 8.8, 12.2, 6.3, 12.4, 3.9)
    ..quadraticBezierTo(12.5, 2.9, 13.4, 3)
    ..cubicTo(15, 3.2, 15.9, 4.6, 15.8, 6.2)
    ..quadraticBezierTo(15.7, 8, 15.1, 9.5)
    ..lineTo(19.4, 9.5)
    ..cubicTo(21, 9.5, 22, 10.8, 21.7, 12.3)
    ..lineTo(20.5, 18.2)
    ..quadraticBezierTo(20, 20.5, 17.8, 20.5)
    ..lineTo(12, 20.5)
    ..quadraticBezierTo(10.3, 20.5, 8.6, 19.4)
    ..close();
  static final _cuff = RRect.fromLTRBR(
    2.3,
    10.4,
    5.8,
    20.5,
    const Radius.circular(1),
  );

  static const _coinFace = Rect.fromLTRB(3, 3, 21, 21);
  // The filled face cuts out the same mark used in the outlined face.
  static final _coinMark = Path()
    ..moveTo(8.5, 6.9)
    ..lineTo(15.5, 6.9)
    ..quadraticBezierTo(16.9, 7.6, 15.5, 8.3)
    ..lineTo(12.7, 8.3)
    ..lineTo(12.7, 10.6)
    ..lineTo(13.7, 10.6)
    ..quadraticBezierTo(16, 10.6, 16, 12.9)
    ..lineTo(16, 15.3)
    ..quadraticBezierTo(15.3, 16.7, 14.6, 15.3)
    ..lineTo(14.6, 12.9)
    ..quadraticBezierTo(14.6, 12, 13.7, 12)
    ..lineTo(12.7, 12)
    ..lineTo(12.7, 17)
    ..quadraticBezierTo(12, 18.4, 11.3, 17)
    ..lineTo(11.3, 12)
    ..lineTo(10.3, 12)
    ..quadraticBezierTo(9.4, 12, 9.4, 12.9)
    ..lineTo(9.4, 15.3)
    ..quadraticBezierTo(8.7, 16.7, 8, 15.3)
    ..lineTo(8, 12.9)
    ..quadraticBezierTo(8, 10.6, 10.3, 10.6)
    ..lineTo(11.3, 10.6)
    ..lineTo(11.3, 8.3)
    ..lineTo(8.5, 8.3)
    ..quadraticBezierTo(7.1, 7.6, 8.5, 6.9)
    ..close();
  static final _filledCoin = Path()
    ..fillType = PathFillType.evenOdd
    ..addOval(_coinFace)
    ..addPath(_coinMark, Offset.zero);

  static final _star = Path()
    ..moveTo(11.3, 3.3)
    ..quadraticBezierTo(12, 1.9, 12.7, 3.3)
    ..lineTo(15.1, 8.2)
    ..lineTo(20.6, 9)
    ..quadraticBezierTo(22.1, 9.2, 21, 10.3)
    ..lineTo(17.1, 14.2)
    ..lineTo(18, 19.6)
    ..quadraticBezierTo(18.3, 21.1, 16.9, 20.4)
    ..lineTo(12, 17.8)
    ..lineTo(7.1, 20.4)
    ..quadraticBezierTo(5.7, 21.1, 6, 19.6)
    ..lineTo(6.9, 14.2)
    ..lineTo(3, 10.3)
    ..quadraticBezierTo(1.9, 9.2, 3.4, 9)
    ..lineTo(8.9, 8.2)
    ..close();

  static final _bubble = Path()
    ..moveTo(6.5, 4.4)
    ..lineTo(17.5, 4.4)
    ..quadraticBezierTo(21, 4.4, 21, 7.9)
    ..lineTo(21, 13.7)
    ..quadraticBezierTo(21, 17.2, 17.5, 17.2)
    ..lineTo(11.2, 17.2)
    ..lineTo(6.5, 20.4)
    ..lineTo(6.5, 17.2)
    ..quadraticBezierTo(3, 17.2, 3, 13.7)
    ..lineTo(3, 7.9)
    ..quadraticBezierTo(3, 4.4, 6.5, 4.4)
    ..close();

  static final _share = Path()
    ..moveTo(14.3, 4)
    ..lineTo(21.2, 10.6)
    ..lineTo(14.3, 17.1)
    ..lineTo(14.3, 13.4)
    ..cubicTo(9.1, 13.5, 5.5, 15.3, 3, 19.1)
    ..cubicTo(3.7, 11.8, 7.5, 8.4, 14.3, 8)
    ..close();

  static final _external = Path()
    ..moveTo(10, 5)
    ..lineTo(6, 5)
    ..quadraticBezierTo(4, 5, 4, 7)
    ..lineTo(4, 18)
    ..quadraticBezierTo(4, 20, 6, 20)
    ..lineTo(17, 20)
    ..quadraticBezierTo(19, 20, 19, 18)
    ..lineTo(19, 14)
    ..moveTo(11, 13)
    ..lineTo(20, 4)
    ..moveTo(14, 4)
    ..lineTo(20, 4)
    ..lineTo(20, 10);

  static final _download = Path()
    ..moveTo(12, 3.5)
    ..lineTo(12, 14.5)
    ..moveTo(8, 10.5)
    ..lineTo(12, 14.5)
    ..lineTo(16, 10.5)
    ..moveTo(4, 15)
    ..lineTo(4, 18)
    ..quadraticBezierTo(4, 20, 6, 20)
    ..lineTo(18, 20)
    ..quadraticBezierTo(20, 20, 20, 18)
    ..lineTo(20, 15);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    switch (glyph) {
      case InteractionGlyph.like:
        final paint = selected ? fill : stroke;
        canvas.drawPath(_thumb, paint);
        canvas.drawRRect(_cuff, paint);
      case InteractionGlyph.coin:
        if (selected) {
          canvas.drawPath(_filledCoin, fill);
        } else {
          canvas.drawOval(_coinFace, stroke);
          canvas.drawPath(_coinMark, fill);
        }
      case InteractionGlyph.favorite:
        canvas.drawPath(_star, selected ? fill : stroke);
      case InteractionGlyph.comment:
        canvas.drawPath(_bubble, stroke);
        for (final x in [8.5, 12.0, 15.5]) {
          canvas.drawCircle(Offset(x, 10.8), .8, fill);
        }
      case InteractionGlyph.share:
        canvas.drawPath(_share, stroke);
      case InteractionGlyph.external:
        canvas.drawPath(_external, stroke);
      case InteractionGlyph.download:
        canvas.drawPath(_download, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InteractionGlyphPainter oldDelegate) =>
      oldDelegate.glyph != glyph ||
      oldDelegate.color != color ||
      oldDelegate.selected != selected;
}
