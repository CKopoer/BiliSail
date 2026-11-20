import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../storage/image_byte_cache.dart';

typedef CachedImagePreview = ({
  Uint8List bytes,
  int width,
  int height,
  bool isOriginal,
});

/// Flutter's decoded LRU cache is shared across tabs while the byte cache can
/// survive process restarts. The app composition root owns both lifetimes.
final class AppImageCache extends ChangeNotifier {
  AppImageCache(this.bytes)
    : decoded = ImageCache()
        ..maximumSize = 256
        ..maximumSizeBytes = 64 * 1024 * 1024;

  final ImageByteCache bytes;
  final ImageCache decoded;
  final Map<AppImageProvider, _ImageDemand> _demands = {};
  final _viewerPreviews = <Uri, CachedImagePreview>{};
  static const _viewerPreviewBudget = 8 * 1024 * 1024;
  int _viewerPreviewBytes = 0;
  bool get enabled => bytes.enabled;

  static Uri _https(Uri uri) =>
      uri.scheme == 'http' ? uri.replace(scheme: 'https') : uri;

  CachedImagePreview? previewFor(Uri original) {
    if (!enabled) return null;
    final key = _https(original);
    final preview = _viewerPreviews.remove(key);
    if (preview != null) _viewerPreviews[key] = preview;
    return preview;
  }

  void _rememberPreview(
    Uri original,
    Uri source,
    Uint8List bytes,
    int width,
    int height,
  ) {
    if (!enabled || bytes.length > _viewerPreviewBudget) return;
    final key = _https(original);
    _viewerPreviewBytes -= _viewerPreviews.remove(key)?.bytes.length ?? 0;
    while (_viewerPreviews.length >= 64 ||
        _viewerPreviewBytes + bytes.length > _viewerPreviewBudget) {
      _viewerPreviewBytes -= _viewerPreviews
          .remove(_viewerPreviews.keys.first)!
          .bytes
          .length;
    }
    _viewerPreviews[key] = (
      bytes: bytes.asUnmodifiableView(),
      width: width,
      height: height,
      isOriginal: key == source,
    );
    _viewerPreviewBytes += bytes.length;
  }

  void _clearPreviews() {
    _viewerPreviews.clear();
    _viewerPreviewBytes = 0;
  }

  AppImageConsumer _acquireConsumer(
    AppImageProvider provider,
    ImageLoadPriority priority,
  ) {
    final demand = _demands.putIfAbsent(provider, _ImageDemand.new);
    final consumer = AppImageConsumer._(demand, priority, () {
      if (demand.consumers.isNotEmpty) return;
      if (identical(_demands[provider], demand)) {
        _demands.remove(provider);
        // Flutter's pending cache listener is not visible widget demand.
        // Remove it before a returning viewport can resolve the cancelled task.
        if (decoded.statusForKey(provider).pending) decoded.evict(provider);
      }
      for (final lease in demand.loads) {
        lease.release();
      }
    });
    demand.consumers.add(consumer);
    demand.updatePriority();
    return consumer;
  }

  /// Reads the original sheet size without allocating its full decoded pixels.
  /// The later thumbnail resolution shares the same bounded byte cache.
  Future<({int width, int height})> dimensions(Uri uri) async {
    final generation = bytes.generation;
    Future<({int width, int height})> inspect(CachedImageBytes result) async {
      final buffer = await ui.ImmutableBuffer.fromUint8List(result.bytes);
      try {
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (generation != bytes.generation) {
            throw const ImageLoadCancelled();
          }
          return (width: descriptor.width, height: descriptor.height);
        } finally {
          descriptor.dispose();
        }
      } finally {
        buffer.dispose();
      }
    }

    final result = await bytes.load(uri);
    try {
      return await inspect(result);
    } on Exception {
      if (generation != bytes.generation) rethrow;
      if (enabled) await bytes.invalidate(uri);
      if (!result.fromDisk) rethrow;
      return inspect(await bytes.load(uri, skipDisk: true));
    }
  }

  set enabled(bool value) {
    if (value == bytes.enabled) return;
    bytes.enabled = value;
    if (!value) {
      _clearPreviews();
      decoded.clear();
      decoded.clearLiveImages();
    }
    // Existing widgets keep their stream and do not refetch just because the
    // policy changed. New resolutions consult the latest policy immediately.
  }

  Future<void> changeScope(String scope) async {
    if (scope == bytes.scope) return;
    final cleanup = bytes.changeScope(scope);
    _clearPreviews();
    decoded.clear();
    decoded.clearLiveImages();
    notifyListeners();
    await cleanup;
  }

  Future<void> clearSession(String oldScope) async {
    bytes.invalidateSession();
    _clearPreviews();
    decoded.clear();
    decoded.clearLiveImages();
    if (oldScope != 'guest') await bytes.clearScope(oldScope);
  }

  Future<void> close() async {
    _clearPreviews();
    decoded.clear();
    decoded.clearLiveImages();
    await bytes.close();
    dispose();
  }
}

/// Widget demand is separate from a decoded stream's keepAlive handle. A ready
/// frame can survive a page swipe without retaining unfinished transport.
final class AppImageConsumer {
  AppImageConsumer._(this._demand, this._priority, this._onRelease);
  final _ImageDemand _demand;
  final VoidCallback _onRelease;
  ImageLoadPriority _priority;
  bool _released = false;

  void setPriority(ImageLoadPriority priority) {
    if (_released || _priority == priority) return;
    _priority = priority;
    _demand.updatePriority();
  }

  void release() {
    if (_released) return;
    _released = true;
    _demand.consumers.remove(this);
    _demand.updatePriority();
    _onRelease();
  }
}

final class _ImageDemand {
  final consumers = <AppImageConsumer>{};
  final loads = <ImageByteLease>{};
  bool get cancelled => consumers.isEmpty;
  ImageLoadPriority get priority =>
      consumers.any(
        (consumer) => consumer._priority == ImageLoadPriority.visible,
      )
      ? ImageLoadPriority.visible
      : ImageLoadPriority.prefetch;

  void check() {
    if (cancelled) throw const ImageLoadCancelled();
  }

  void updatePriority() {
    for (final load in loads) {
      load.setPriority(priority);
    }
  }
}

@immutable
final class AppImageProvider extends ImageProvider<AppImageProvider> {
  AppImageProvider({
    required this.cache,
    required this.url,
    this.cacheWidth,
    this.cacheHeight,
    this.viewerOriginal,
  }) : generation = cache.bytes.generation;
  final AppImageCache cache;
  final String url;
  final int generation;
  final int? cacheWidth, cacheHeight;
  final Uri? viewerOriginal;

  AppImageConsumer acquireConsumer(ImageLoadPriority priority) =>
      cache._acquireConsumer(this, priority);

  /// Only a completed frame may bypass viewport admission or scroll deferral.
  /// Pending streams still need the usual visibility and loading policy.
  bool get hasDecodedFrame {
    if (!cache.enabled || generation != cache.bytes.generation) return false;
    final status = cache.decoded.statusForKey(this);
    return !status.pending && (status.keepAlive || status.live);
  }

  @override
  ImageStream createStream(ImageConfiguration configuration) {
    final stream = super.createStream(configuration);
    if (hasDecodedFrame) {
      // Expose our completed stream without populating the framework's global
      // cache. A widget can consume it directly without starting new work.
      final completer = cache.decoded.putIfAbsent(
        this,
        () => loadImage(
          this,
          PaintingBinding.instance.instantiateImageCodecWithSize,
        ),
      );
      if (completer != null) stream.setCompleter(completer);
    }
    return stream;
  }

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
  ) => MultiFrameImageStreamCompleter(
    codec: _codec(decode, cache._demands[this]),
    scale: 1,
  );

  Future<ui.Codec> _codec(
    ImageDecoderCallback decode,
    _ImageDemand? demand,
  ) async {
    Future<CachedImageBytes> load(Uri uri, {bool skipDisk = false}) async {
      demand?.check();
      final lease = cache.bytes.acquire(
        uri,
        skipDisk: skipDisk,
        priority: demand?.priority ?? ImageLoadPriority.visible,
      );
      demand?.loads.add(lease);
      try {
        final result = await lease.result;
        demand?.check();
        return result;
      } finally {
        demand?.loads.remove(lease);
        lease.release();
      }
    }

    try {
      if (generation != cache.bytes.generation) {
        throw const ImageLoadCancelled();
      }
      final uri = Uri.parse(url);
      final result = await load(uri);
      try {
        return await _decode(uri, result, decode, demand);
      } on Exception {
        demand?.check();
        if (generation != cache.bytes.generation) rethrow;
        if (cache.enabled) await cache.bytes.invalidate(uri);
        if (!result.fromDisk) rethrow;
        return await _decode(
          uri,
          await load(uri, skipDisk: true),
          decode,
          demand,
        );
      }
    } catch (_) {
      // Failed pending completers must not poison future mounts of this URL.
      if (demand == null || identical(cache._demands[this], demand)) {
        cache.decoded.evict(this);
      }
      rethrow;
    }
  }

  Future<ui.Codec> _decode(
    Uri source,
    CachedImageBytes result,
    ImageDecoderCallback decode,
    _ImageDemand? demand,
  ) async {
    demand?.check();
    final buffer = await ui.ImmutableBuffer.fromUint8List(result.bytes);
    if (generation != cache.bytes.generation || demand?.cancelled == true) {
      buffer.dispose();
      throw const ImageLoadCancelled();
    }
    (int, int)? dimensions;
    final codec = await decode(
      buffer,
      getTargetSize: (width, height) {
        dimensions = (width, height);
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
    if (generation != cache.bytes.generation || demand?.cancelled == true) {
      codec.dispose();
      throw const ImageLoadCancelled();
    }
    if ((viewerOriginal, dimensions) case (
      final original?,
      (final w, final h),
    )) {
      cache._rememberPreview(original, source, result.bytes, w, h);
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
      cacheHeight == other.cacheHeight &&
      viewerOriginal == other.viewerOriginal;
  @override
  int get hashCode => Object.hash(
    cache,
    url,
    generation,
    cacheWidth,
    cacheHeight,
    viewerOriginal,
  );
  @override
  String toString() =>
      'AppImageProvider(public image, generation: $generation)';
}
