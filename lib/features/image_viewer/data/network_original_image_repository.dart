import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import '../../../core/storage/image_byte_cache.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/original_image.dart';

/// Loads the preview or original URL selected by the viewer, without credentials
/// or disk persistence. The viewer owns cancellation and memory.
final class NetworkOriginalImageRepository
    implements AutomaticOriginalImageRepository {
  NetworkOriginalImageRepository({this.loader = loadPublicImage});
  final ImageByteLoader loader;
  static const maxBytes = 32 * 1024 * 1024;
  static const automaticMaxBytes = 8 * 1024 * 1024;
  static const timeout = Duration(seconds: 30);

  @override
  Future<OriginalImage> load(
    Uri source,
    RequestCancellation cancellation,
  ) async => _load(_publicSource(source), cancellation, loader, maxBytes);

  @override
  Future<OriginalImage?> loadAutomatically(
    Uri source,
    RequestCancellation cancellation,
  ) async {
    final uri = _publicSource(source);
    final transport = PublicImageTransport(maxConnections: 1);
    try {
      final probe = ImageLoadRequest(
        maxBytes: automaticMaxBytes,
        timeout: const Duration(seconds: 3),
      );
      cancellation.onCancel(probe.cancel);
      // Some CDN resources permit GET but reject HEAD.
      final length = await transport
          .contentLength(uri, probe)
          .onError<HttpException>((_, _) => null)
          .onError<TimeoutException>((_, _) => null);
      if (length == null || length > automaticMaxBytes) return null;
      return await _load(uri, cancellation, transport.load, automaticMaxBytes);
    } on ImageResponseTooLarge {
      // The GET response can exceed the size reported by HEAD.
      return null;
    } on OriginalImageLimit {
      return null;
    } finally {
      transport.close();
    }
  }

  Uri _publicSource(Uri source) {
    final uri = source.scheme == 'http'
        ? source.replace(scheme: 'https')
        : source;
    if (!ImageByteCache.isPublicImageUri(uri)) {
      throw const FormatException('Unsupported original image');
    }
    return uri;
  }

  Future<OriginalImage> _load(
    Uri uri,
    RequestCancellation cancellation,
    ImageByteLoader transfer,
    int maxBytes,
  ) async {
    final request = ImageLoadRequest(maxBytes: maxBytes, timeout: timeout);
    cancellation.onCancel(request.cancel);
    request.check();
    final bytes = await transfer(uri, request).timeout(
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
      if (!OriginalImage.acceptsDimensions(
        descriptor.width,
        descriptor.height,
      )) {
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
