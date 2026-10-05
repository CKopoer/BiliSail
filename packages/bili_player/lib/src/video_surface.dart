import 'package:flutter/widgets.dart';

import 'player_contract.dart';

/// Keeps presentation independent of the native player and its controller.
final class VideoSurface extends StatelessWidget {
  const VideoSurface({super.key, required this.engine});
  final PlayerEngine engine;

  @override
  Widget build(BuildContext context) => engine is VideoSurfaceSource
      ? (engine as VideoSurfaceSource).buildVideoSurface()
      : const ColoredBox(color: Color(0xFF000000));
}
