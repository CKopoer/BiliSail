import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'video_output.dart';

/// A video output whose pixels can be presented as a Flutter widget.
abstract interface class FlutterVideoOutput implements VideoOutput {
  Widget buildVideoSurface();
}

/// An optional signal that a video surface can present its current source.
abstract interface class VideoFrameReadiness {
  /// Whether a usable first frame and display dimensions are available.
  ///
  /// Resets when the output is cleared or rebound. Readiness is published after
  /// a Flutter frame so foreground layers can follow the video surface.
  ValueListenable<bool> get frameReady;
}

/// The presentation strategy for video and its ordered Flutter foreground.
///
/// Output and composition implementations must be selected together. The
/// adapter does not own playback commands, clocks, or media resources.
abstract interface class VideoCompositionAdapter {
  Widget buildVideoSurface(BuildContext context, VideoOutput output);

  /// Composes layers in paint order while preserving their input behavior.
  Widget compose(BuildContext context, {required List<Widget> layers});
}

/// The existing Flutter widget and Stack composition path.
final class FlutterVideoCompositionAdapter implements VideoCompositionAdapter {
  const FlutterVideoCompositionAdapter();

  @override
  Widget buildVideoSurface(BuildContext context, VideoOutput output) {
    if (output is! FlutterVideoOutput) {
      throw StateError('The Flutter compositor requires a FlutterVideoOutput.');
    }
    return output.buildVideoSurface();
  }

  @override
  Widget compose(BuildContext context, {required List<Widget> layers}) =>
      // Layout-builder callbacks above the player may repaint their ancestors
      // even when only an isolated foreground layer changed.
      RepaintBoundary(
        child: Stack(fit: StackFit.expand, children: layers),
      );
}

/// Supplies one composition strategy to pages, fullscreen routes, and previews.
final class VideoCompositionScope extends InheritedWidget {
  const VideoCompositionScope({
    super.key,
    required this.adapter,
    required super.child,
  });

  final VideoCompositionAdapter adapter;

  static VideoCompositionAdapter of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<VideoCompositionScope>()
          ?.adapter ??
      const FlutterVideoCompositionAdapter();

  @override
  bool updateShouldNotify(VideoCompositionScope oldWidget) =>
      !identical(adapter, oldWidget.adapter);
}
