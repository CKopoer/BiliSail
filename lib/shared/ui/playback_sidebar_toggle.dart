import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The playback page owns the panel state, including manual overrides.
class PlaybackInfoScope extends InheritedWidget {
  const PlaybackInfoScope({
    super.key,
    required this.wide,
    required this.showInfo,
    required this.tooltip,
    required this.onToggle,
    required super.child,
  });

  final bool wide;
  final bool showInfo;
  final String tooltip;
  final VoidCallback onToggle;

  static PlaybackInfoScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PlaybackInfoScope>();

  static PlaybackInfoScope? read(BuildContext context) =>
      context.getInheritedWidgetOfExactType<PlaybackInfoScope>();

  @override
  bool updateShouldNotify(PlaybackInfoScope oldWidget) =>
      wide != oldWidget.wide ||
      showInfo != oldWidget.showInfo ||
      tooltip != oldWidget.tooltip ||
      onToggle != oldWidget.onToggle;
}

class PlaybackSidebarToggle extends StatelessWidget {
  const PlaybackSidebarToggle({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context) {
    final info = PlaybackInfoScope.maybeOf(context);
    if (info == null) return const SizedBox.shrink();
    return Semantics(
      expanded: info.showInfo,
      child: IconButton(
        color: color,
        tooltip: info.tooltip,
        onPressed: info.onToggle,
        icon: Builder(
          builder: (context) => CustomPaint(
            key: ValueKey(
              info.showInfo ? 'playback-collapse-info' : 'playback-expand-info',
            ),
            size: const Size.square(20),
            painter: _InfoPanelIcon(
              wide: info.wide,
              expanded: info.showInfo,
              color:
                  IconTheme.of(context).color ??
                  Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoPanelIcon extends CustomPainter {
  const _InfoPanelIcon({
    required this.wide,
    required this.expanded,
    required this.color,
  });

  final bool wide;
  final bool expanded;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTRB(1, 2.5, size.width - 1, size.height - 2.5);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 1.5;
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(2.5)),
      stroke,
    );
    var center = frame.center;
    if (expanded) {
      if (wide) {
        final x = frame.right - 4.5;
        canvas.drawLine(Offset(x, frame.top), Offset(x, frame.bottom), stroke);
        center = Offset((frame.left + x) / 2, center.dy);
      } else {
        final y = frame.bottom - 4;
        canvas.drawLine(Offset(frame.left, y), Offset(frame.right, y), stroke);
        center = Offset(center.dx, (frame.top + y) / 2);
      }
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (!wide) canvas.rotate(math.pi / 2);
    if (!expanded) canvas.rotate(math.pi);
    // The chevron points towards the visible panel. An inward arrow opens it again.
    final arrow = Path()
      ..moveTo(-1, -2.8)
      ..lineTo(1.8, 0)
      ..lineTo(-1, 2.8);
    if (!expanded) {
      arrow.moveTo(-4, 0);
      arrow.lineTo(1.8, 0);
    }
    canvas.drawPath(arrow, stroke);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_InfoPanelIcon oldDelegate) =>
      wide != oldDelegate.wide ||
      expanded != oldDelegate.expanded ||
      color != oldDelegate.color;
}

/// Offline rooms and unavailable episodes have no playback toolbar.
class PlaybackInfoPlaceholder extends StatelessWidget {
  const PlaybackInfoPlaceholder({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      child,
      const Align(
        alignment: Alignment.bottomRight,
        child: Material(
          color: Colors.black54,
          child: PlaybackSidebarToggle(color: Colors.white),
        ),
      ),
    ],
  );
}
