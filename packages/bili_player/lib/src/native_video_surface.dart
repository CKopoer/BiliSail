import 'player_contract.dart';

/// Initial Surface size before decoding. Decoded video parameters remain the
/// authority afterwards; container dimensions are only a bounded startup hint.
VideoDimensions? nativeVideoSurfaceDimensions(String Function(String) read) {
  final count = int.tryParse(read('track-list/count')) ?? 0;
  if (count < 0 || count > 128) return null;
  for (var index = 0; index < count; index++) {
    final track = 'track-list/$index';
    if (read('$track/type') != 'video' || read('$track/albumart') == 'yes') {
      continue;
    }
    final width = int.tryParse(read('$track/demux-w')) ?? 0;
    final height = int.tryParse(read('$track/demux-h')) ?? 0;
    if (width <= 1 || height <= 1 || width > 16384 || height > 16384) {
      return null;
    }
    final par = double.tryParse(read('$track/demux-par')) ?? 1;
    if (!par.isFinite || par <= 0 || par > 16) return null;
    final displayWidth = (width * par).round();
    if (displayWidth <= 1 || displayWidth > 16384) return null;
    final rotation = int.tryParse(read('$track/demux-rotation')) ?? 0;
    return rotation % 180 == 90
        ? VideoDimensions(height, displayWidth)
        : VideoDimensions(displayWidth, height);
  }
  return null;
}
