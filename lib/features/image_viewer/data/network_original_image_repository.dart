import 'dart:async';
import 'dart:ui' as ui;

import '../../../core/storage/image_byte_cache.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/original_image.dart';

/// Originals are fetched only on explicit preview, without CDN resizing,
/// credentials or disk persistence. The viewer owns cancellation and memory.
final class NetworkOriginalImageRepository implements OriginalImageRepository {
  NetworkOriginalImageRepository({this.loader = loadPublicImage});
  final ImageByteLoader loader;
  static const maxBytes = 32 * 1024 * 1024;
  static const maxPixels = 32 * 1024 * 1024;
  static const timeout = Duration(seconds: 30);

  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    final uri = source.scheme == 'http'
        ? source.replace(scheme: 'https')
        : source;
    if (!ImageByteCache.isPublicImageUri(uri)) {
      throw const FormatException('Unsupported original image');
    }
    final request = ImageLoadRequest(maxBytes: maxBytes, timeout: timeout);
    cancellation.onCancel(request.cancel);
    request.check();
    final bytes = await loader(uri, request).timeout(
      timeout,
      onTimeout: () {
        request.cancel();
        throw TimeoutException('Original image deadline exceeded');
      },
    );
    request.check();
    if (bytes.isEmpty || bytes.length > maxBytes) {
      throw const OriginalImageLimit();
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    ui.ImageDescriptor? descriptor;
    try {
      descriptor = await ui.ImageDescriptor.encoded(buffer);
      request.check();
      if (descriptor.width > 16384 ||
          descriptor.height > 16384 ||
          descriptor.width * descriptor.height > maxPixels) {
        throw const OriginalImageLimit();
      }
      return OriginalImage(
        bytes: bytes,
        width: descriptor.width,
        height: descriptor.height,
      );
    } finally {
      descriptor?.dispose();
      buffer.dispose();
    }
  }
}
