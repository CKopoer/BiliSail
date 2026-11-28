import 'package:flutter/widgets.dart';

typedef PlayerPictureTransform = ({double scale, Offset offset});

/// Page-owned view state shared by the inline and fullscreen presentations.
class PlayerPictureController extends ValueNotifier<PlayerPictureTransform> {
  PlayerPictureController() : super(identity);

  static const PlayerPictureTransform identity = (
    scale: 1,
    offset: Offset.zero,
  );

  void reset() => value = identity;
}

/// Transforms only the video output, retaining the child across touch updates.
class PlayerPicture extends StatelessWidget {
  const PlayerPicture({
    super.key,
    required this.controller,
    required this.child,
  });

  final PlayerPictureController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: LayoutBuilder(
      builder: (context, constraints) => ValueListenableBuilder(
        valueListenable: controller,
        child: child,
        builder: (context, value, child) => Transform(
          key: const ValueKey('player-picture-transform'),
          transform: Matrix4.identity()
            ..translateByDouble(
              value.offset.dx * constraints.maxWidth,
              value.offset.dy * constraints.maxHeight,
              0,
              1,
            )
            ..scaleByDouble(value.scale, value.scale, 1, 1),
          child: child,
        ),
      ),
    ),
  );
}
