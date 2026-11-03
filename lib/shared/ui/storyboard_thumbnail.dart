import 'package:flutter/widgets.dart';

import '../../features/playback/domain/playback_timeline.dart';
import 'app_network_image.dart';

class StoryboardThumbnail extends StatelessWidget {
  const StoryboardThumbnail({
    super.key,
    required this.storyboard,
    required this.frame,
    required this.width,
    required this.height,
    this.fallback = const ColoredBox(color: Color(0xff303030)),
    this.hideUntilLoaded = false,
  });
  final VideoStoryboard storyboard;
  final StoryboardFrame frame;
  final double width, height;
  final Widget fallback;
  final bool hideUntilLoaded;

  Widget get _placeholder => hideUntilLoaded
      ? const SizedBox.shrink()
      : SizedBox(width: width, height: height, child: fallback);

  @override
  Widget build(BuildContext context) => AppNetworkImage(
    url: frame.image.toString(),
    width: width * storyboard.columns,
    height: height * storyboard.rows,
    fit: BoxFit.fill,
    cacheWidth: 1280,
    cacheHeight: 1280,
    excludeFromSemantics: true,
    errorBuilder: (_, _, _) => _placeholder,
    // Wrap the whole tile so an unfinished sprite need not reserve any height.
    frameBuilder: (_, child, imageFrame, _) =>
        hideUntilLoaded && imageFrame == null
        ? _placeholder
        : SizedBox(
            width: width,
            height: height,
            child: Stack(
              fit: StackFit.expand,
              children: [
                fallback,
                ClipRect(
                  child: OverflowBox(
                    minWidth: width * storyboard.columns,
                    maxWidth: width * storyboard.columns,
                    minHeight: height * storyboard.rows,
                    maxHeight: height * storyboard.rows,
                    alignment: Alignment(
                      storyboard.columns == 1
                          ? 0
                          : -1 + 2 * frame.column / (storyboard.columns - 1),
                      storyboard.rows == 1
                          ? 0
                          : -1 + 2 * frame.row / (storyboard.rows - 1),
                    ),
                    child: Opacity(
                      opacity: imageFrame == null ? 0 : 1,
                      child: child,
                    ),
                  ),
                ),
              ],
            ),
          ),
  );
}
