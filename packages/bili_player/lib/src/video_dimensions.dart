import 'package:media_kit/media_kit.dart' show VideoParams;

import 'player_contract.dart';

VideoDimensions? videoDisplayDimensions(VideoParams params) {
  final displayWidth = params.dw;
  final displayHeight = params.dh;
  final hasDisplaySize =
      displayWidth != null &&
      displayHeight != null &&
      displayWidth > 0 &&
      displayHeight > 0;
  final width = hasDisplaySize ? displayWidth : params.w;
  final height = hasDisplaySize ? displayHeight : params.h;
  if (width == null || height == null || width <= 0 || height <= 0) {
    return null;
  }
  // Match the surface's orientation rather than the encoded pixel layout.
  final rotation = (params.rotate ?? 0) % 360;
  return rotation == 90 || rotation == 270
      ? VideoDimensions(height, width)
      : VideoDimensions(width, height);
}
