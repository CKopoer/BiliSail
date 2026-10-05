import 'dart:typed_data';

import '../../../domain/request_cancellation.dart';

final class OriginalImage {
  OriginalImage({
    required Uint8List bytes,
    required this.width,
    required this.height,
  }) : bytes = bytes.asUnmodifiableView();
  final Uint8List bytes;
  final int width, height;
}

abstract interface class OriginalImageRepository {
  Future<OriginalImage> load(Uri source, RequestCancellation cancellation);
}

final class OriginalImageLimit implements Exception {
  const OriginalImageLimit();
}
