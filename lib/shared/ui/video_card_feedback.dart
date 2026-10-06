import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

final class VideoCardFeedback {
  const VideoCardFeedback({this.onUndo, this.busy = false});
  final VoidCallback? onUndo;
  final bool busy;
}

/// A static cover replaces the preview while the recommendation is rejected.
final class VideoCardFeedbackCover extends StatelessWidget {
  const VideoCardFeedbackCover({
    super.key,
    required this.background,
    required this.feedback,
  });

  final Widget background;
  final VideoCardFeedback feedback;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(6),
    child: Stack(
      fit: StackFit.expand,
      children: [
        ExcludeSemantics(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: background,
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xDC202123), Color(0xEF0D1016)],
            ),
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            final scaler = MediaQuery.textScalerOf(context);
            final wide = constraints.maxWidth >= scaler.scale(250);
            final showFace = constraints.maxHeight >= scaler.scale(130);
            final message = Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (showFace) ...[
                  const SizedBox(
                    width: 36,
                    height: 36,
                    child: CustomPaint(painter: _FeedbackFace()),
                  ),
                  const SizedBox(height: 8),
                ],
                Text(
                  '内容不感兴趣',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: wide ? 14 : 12,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '将减少此类内容推荐',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: const Color(0xFFC5C5C5),
                    fontSize: wide ? 12 : 11,
                    height: 1.3,
                  ),
                ),
              ],
            );
            final undo = TextButton.icon(
              key: const ValueKey('video-card-feedback-undo'),
              onPressed: feedback.busy ? null : feedback.onUndo,
              icon: feedback.busy
                  ? const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.undo_rounded, size: 15),
              label: Text(feedback.busy ? '撤销中' : '撤销'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                disabledForegroundColor: Colors.white54,
                backgroundColor: const Color(0xFF3D3E40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                minimumSize: const Size(64, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(fontSize: 12, height: 1.2),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            );
            return Padding(
              padding: const EdgeInsets.all(8),
              child: wide
                  ? Center(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(child: message),
                          const SizedBox(width: 24),
                          undo,
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(child: SingleChildScrollView(child: message)),
                        const SizedBox(height: 4),
                        undo,
                      ],
                    ),
            );
          },
        ),
      ],
    ),
  );
}

final class _FeedbackFace extends CustomPainter {
  const _FeedbackFace();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawCircle(
      size.center(Offset.zero),
      size.width / 2,
      Paint()..color = Colors.white,
    );
    final stroke = Paint()
      ..color = const Color(0xFF444548)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(
      Path()
        ..moveTo(11, 12)
        ..lineTo(15, 15)
        ..lineTo(11, 18)
        ..moveTo(25, 12)
        ..lineTo(21, 15)
        ..lineTo(25, 18)
        ..moveTo(14, 26)
        ..quadraticBezierTo(18, 22, 22, 26),
      stroke,
    );
  }

  @override
  bool shouldRepaint(_FeedbackFace oldDelegate) => false;
}
