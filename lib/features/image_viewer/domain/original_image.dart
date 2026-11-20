import 'dart:typed_data';
import 'dart:math' as math;

import '../../../domain/request_cancellation.dart';

final class OriginalImage {
  OriginalImage({
    required Uint8List bytes,
    required this.width,
    required this.height,
  }) : bytes = bytes.asUnmodifiableView();
  final Uint8List bytes;
  final int width, height;

  static bool acceptsDimensions(int width, int height) =>
      width > 0 &&
      height > 0 &&
      width <= 262144 &&
      height <= 262144 &&
      width * height <= 64 * 1024 * 1024;

  // Bound decoded textures separately from the encoded original, which is
  // retained unchanged for saving and copying. Keep the original layout size.
  double get _previewScale => math.min(
    1,
    math.min(
      8192 / math.max(width, height),
      math.sqrt(16 * 1024 * 1024 / (width * height)),
    ),
  );
  int get previewWidth => math.max(1, (width * _previewScale).floor());
  int get previewHeight => math.max(1, (height * _previewScale).floor());
  bool get scaledPreview => previewWidth != width || previewHeight != height;
}

abstract interface class OriginalImageRepository {
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation);
}

abstract interface class AutomaticOriginalImageRepository
    implements OriginalImageRepository {
  // An unverified or oversized original is left for an explicit user action.
  Future<OriginalImage?> loadAutomatically(
    Uri source,
    RequestCancellation cancellation,
  );
}

final class OriginalImageLimit implements Exception {
  const OriginalImageLimit();
}
