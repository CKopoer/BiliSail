import 'package:flutter/widgets.dart';

import '../../features/video/application/video_card_preview_playback.dart';

/// The app composition root supplies card operations to all video grids.
class VideoCardInteractionScope extends InheritedWidget {
  const VideoCardInteractionScope({
    super.key,
    required this.interactions,
    required this.onNotice,
    required super.child,
  });
  final VideoCardOperations interactions;
  final void Function(BuildContext, String) onNotice;

  static VideoCardInteractionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<VideoCardInteractionScope>();

  @override
  bool updateShouldNotify(VideoCardInteractionScope oldWidget) =>
      interactions != oldWidget.interactions || onNotice != oldWidget.onNotice;
}
