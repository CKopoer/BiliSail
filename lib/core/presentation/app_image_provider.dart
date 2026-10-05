import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../storage/image_byte_cache.dart';

/// Flutter's decoded LRU cache is shared across tabs while the byte cache can
/// survive process restarts. The app composition root owns both lifetimes.
final class AppImageCache extends ChangeNotifier {
  AppImageCache(this.bytes)
    : decoded = ImageCache()
        ..maximumSize = 256
        ..maximumSizeBytes = 64 * 1024 * 1024;

  final ImageByteCache bytes;
  final ImageCache decoded;
  bool get enabled => bytes.enabled;

  set enabled(bool value) {
    if (value == bytes.enabled) return;
    bytes.enabled = value;
    if (!value) {
      decoded.clear();
      decoded.clearLiveImages();
    }
    // Existing widgets keep their stream and do not refetch just because the
    // policy changed. New resolutions consult the latest policy immediately.
  }

  Future<void> changeScope(String scope) async {
    if (scope == bytes.scope) return;
    final cleanup = bytes.changeScope(scope);
    decoded.clear();
    decoded.clearLiveImages();
    notifyListeners();
    await cleanup;
  }

  Future<void> clearSession(String oldScope) async {
    bytes.invalidateSession();
    decoded.clear();
    decoded.clearLiveImages();
    if (oldScope != 'guest') await bytes.clearScope(oldScope);
  }

  Future<void> close() async {
    decoded.clear();
    decoded.clearLiveImages();
    await bytes.close();
    dispose();
  }
}

@immutable
final class AppImageProvider extends ImageProvider<AppImageProvider> {
  AppImageProvider({
    required this.cache,
    required this.url,
    this.cacheWidth,
    this.cacheHeight,
  }) : generation = cache.bytes.generation;
  final AppImageCache cache;
  final String url;
  final int generation;
  final int? cacheWidth, cacheHeight;

  @override
  Future<AppImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  void resolveStreamForKey(
    ImageConfiguration configuration,
    ImageStream stream,
    AppImageProvider key,
    ImageErrorListener handleError,
  ) {
    if (stream.completer != null) return;
    final completer = cache.enabled
        ? cache.decoded.putIfAbsent(
            key,
            () => loadImage(
              key,
              PaintingBinding.instance.instantiateImageCodecWithSize,
            ),
            onError: handleError,
          )
        : loadImage(
            key,
            PaintingBinding.instance.instantiateImageCodecWithSize,
          );
    if (completer != null) stream.setCompleter(completer);
  }

  @override
  ImageStreamCompleter loadImage(
    AppImageProvider key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(codec: _codec(decode), scale: 1);

  Future<ui.Codec> _codec(ImageDecoderCallback decode) async {
    try {
      if (generation != cache.bytes.generation) {
        throw const ImageLoadCancelled();
      }
      final uri = Uri.parse(url);
      final result = await cache.bytes.load(uri);
      try {
        return await _decode(result, decode);
      } on Exception {
        if (generation != cache.bytes.generation) rethrow;
        if (cache.enabled) await cache.bytes.invalidate(uri);
        if (!result.fromDisk) rethrow;
        return await _decode(
          await cache.bytes.load(uri, skipDisk: true),
          decode,
        );
      }
    } catch (_) {
      // Failed pending completers must not poison future mounts of this URL.
      cache.decoded.evict(this);
      rethrow;
    }
  }

  Future<ui.Codec> _decode(
    CachedImageBytes result,
    ImageDecoderCallback decode,
  ) async {
    final codec = await decode(
      await ui.ImmutableBuffer.fromUint8List(result.bytes),
      getTargetSize: (width, height) {
        // Prevent large public images from retaining full-resolution decoded
        // surfaces. A stable size also gives identical URLs identical keys.
        final targetWidth = (cacheWidth ?? 1280).clamp(1, 1280);
        final targetHeight = (cacheHeight ?? 1280).clamp(1, 1280);
        final ratio = (targetWidth / width).clamp(0.0, 1.0);
        final heightRatio = (targetHeight / height).clamp(0.0, 1.0);
        final scale = ratio < heightRatio ? ratio : heightRatio;
        if (scale == 1) return const ui.TargetImageSize();
        return ui.TargetImageSize(
          width: (width * scale).round().clamp(1, 1280),
          height: (height * scale).round().clamp(1, 1280),
        );
      },
    );
    if (generation != cache.bytes.generation) {
      codec.dispose();
      throw const ImageLoadCancelled();
    }
    return codec;
  }

  @override
  bool operator ==(Object other) =>
      other is AppImageProvider &&
      identical(cache, other.cache) &&
      url == other.url &&
      generation == other.generation &&
      cacheWidth == other.cacheWidth &&
      cacheHeight == other.cacheHeight;
  @override
  int get hashCode =>
      Object.hash(cache, url, generation, cacheWidth, cacheHeight);
  @override
  String toString() =>
      'AppImageProvider(public image, generation: $generation)';
}
