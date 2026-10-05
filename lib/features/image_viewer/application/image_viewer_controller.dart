import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/image_byte_cache.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/original_image.dart';

final originalImageRepositoryProvider = Provider<OriginalImageRepository>(
  (ref) => throw UnimplementedError('OriginalImageRepository'),
);
final imageViewerSessionProvider = Provider<Object>((ref) => 0);
final imageViewerControllerProvider = NotifierProvider.autoDispose
    .family<ImageViewerController, ImageViewerState, ImageViewerRequest>(
      ImageViewerController.new,
    );

final class ImageViewerRequest {
  ImageViewerRequest(List<Uri> images, int index)
    : images = List.unmodifiable(images.take(9)),
      initialIndex = index {
    if (this.images.isEmpty) throw ArgumentError.value(images, 'images');
  }
  final List<Uri> images;
  final int initialIndex;
}

final class ImageViewerState {
  const ImageViewerState({
    required this.index,
    this.loading = true,
    this.image,
    this.message,
  });
  final int index;
  final bool loading;
  final OriginalImage? image;
  final String? message;
}

class ImageViewerController extends Notifier<ImageViewerState> {
  ImageViewerController(this.request);
  final ImageViewerRequest request;
  RequestCancellation? _read;
  int _generation = 0;

  @override
  ImageViewerState build() {
    ref.listen(imageViewerSessionProvider, (previous, next) {
      if (previous == next) return;
      ++_generation;
      _read?.cancel();
      _read = null;
      state = ImageViewerState(
        index: state.index,
        loading: false,
        message: '账号会话已变化，请重新加载图片',
      );
    });
    ref.onDispose(() {
      ++_generation;
      _read?.cancel();
    });
    return ImageViewerState(
      index: request.initialIndex.clamp(0, request.images.length - 1),
    );
  }

  Future<void> load([int? index]) async {
    final next = index ?? state.index;
    if (next < 0 || next >= request.images.length) return;
    if (state.loading && _read != null && next == state.index) return;
    _read?.cancel();
    final generation = ++_generation;
    final cancellation = RequestCancellation();
    _read = cancellation;
    state = ImageViewerState(index: next);
    try {
      final image = await ref
          .read(originalImageRepositoryProvider)
          .load(request.images[next], cancellation);
      if (generation != _generation || cancellation.isCancelled) return;
      state = ImageViewerState(index: next, loading: false, image: image);
    } catch (error) {
      if (generation != _generation || cancellation.isCancelled) return;
      if (error is ImageLoadCancelled) {
        state = ImageViewerState(
          index: next,
          loading: false,
          message: '图片加载已取消',
        );
        return;
      }
      state = ImageViewerState(
        index: next,
        loading: false,
        message: switch (error) {
          OriginalImageLimit() => '原图超过支持的大小，请在官方页面查看',
          TimeoutException() => '原图加载超时，请重试',
          HttpException() || SocketException() => '原图下载失败，请重试',
          _ => '原图无法读取，请重试',
        },
      );
    } finally {
      if (generation == _generation) _read = null;
    }
  }
}
