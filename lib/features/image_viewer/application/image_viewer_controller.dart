import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/public_image_variant.dart';
import '../../../core/storage/image_byte_cache.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/image_export_service.dart';
import '../domain/original_image.dart';

final originalImageRepositoryProvider = Provider<OriginalImageRepository>(
  (ref) => throw UnimplementedError('OriginalImageRepository'),
);
final imageViewerSessionProvider = Provider<Object>((ref) => 0);
final imageExportServiceProvider = Provider<ImageExportService>(
  (ref) => const UnsupportedImageExportService(),
);
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

  Uri previewSource(int index) =>
      publicImageThumbnail(images[index], width: 1280, resizeAnimated: true);
}

final class ImageViewerState {
  const ImageViewerState({
    required this.index,
    this.loading = true,
    this.image,
    this.message,
    this.exporting = false,
    this.exportMessage,
    this.originalRequested = false,
    this.isOriginal = false,
  });
  final int index;
  final bool loading;
  final OriginalImage? image;
  final String? message;
  final bool exporting;
  final String? exportMessage;
  final bool originalRequested;
  final bool isOriginal;

  ImageViewerState withExport(bool busy, [String? feedback]) =>
      ImageViewerState(
        index: index,
        loading: loading,
        image: image,
        message: message,
        exporting: busy,
        exportMessage: feedback,
        originalRequested: originalRequested,
        isOriginal: isOriginal,
      );
}

class ImageViewerController extends Notifier<ImageViewerState> {
  ImageViewerController(this.request);
  final ImageViewerRequest request;
  RequestCancellation? _read;
  int _generation = 0;
  bool _exporting = false;
  bool _disposed = false;

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
        exporting: _exporting,
      );
    });
    ref.onDispose(() {
      _disposed = true;
      ++_generation;
      _read?.cancel();
    });
    return ImageViewerState(
      index: request.initialIndex.clamp(0, request.images.length - 1),
    );
  }

  Future<void> load([int? index]) => _load(index ?? state.index);

  Future<void> retry() => _load(state.index, original: state.originalRequested);

  Future<void> loadOriginal() async {
    if (state.isOriginal) return;
    await _load(state.index, original: true);
  }

  Future<void> _load(int next, {bool original = false}) async {
    if (next < 0 || next >= request.images.length) return;
    final preview = request.previewSource(next);
    final originalRequested = original || preview == request.images[next];
    if (state.loading &&
        _read != null &&
        next == state.index &&
        state.originalRequested == originalRequested) {
      return;
    }
    // Keep the small preview visible while an explicitly requested original
    // downloads. Switching pictures never carries pixels from the old index.
    final retained = original && next == state.index ? state.image : null;
    final retainedOriginal = retained != null && state.isOriginal;
    _read?.cancel();
    final generation = ++_generation;
    final cancellation = RequestCancellation();
    _read = cancellation;
    state = ImageViewerState(
      index: next,
      image: retained,
      exporting: _exporting,
      originalRequested: originalRequested,
      isOriginal: retainedOriginal,
    );
    try {
      final image = await ref
          .read(originalImageRepositoryProvider)
          .load(
            originalRequested ? request.images[next] : preview,
            cancellation,
          );
      if (generation != _generation || cancellation.isCancelled) return;
      state = ImageViewerState(
        index: next,
        loading: false,
        image: image,
        exporting: _exporting,
        originalRequested: originalRequested,
        isOriginal: originalRequested,
      );
    } catch (error) {
      if (generation != _generation || cancellation.isCancelled) return;
      if (error is ImageLoadCancelled) {
        state = ImageViewerState(
          index: next,
          loading: false,
          message: '图片加载已取消',
          exporting: _exporting,
          image: retained,
          originalRequested: originalRequested,
          isOriginal: retainedOriginal,
        );
        return;
      }
      state = ImageViewerState(
        index: next,
        loading: false,
        exporting: _exporting,
        image: retained,
        originalRequested: originalRequested,
        isOriginal: retainedOriginal,
        message: switch (error) {
          OriginalImageLimit() || ImageResponseTooLarge() =>
            '${originalRequested ? '原图' : '预览图'}超过安全加载上限（32 MiB／约 6711 万像素），请在官方页面查看',
          TimeoutException() => '${originalRequested ? '原图' : '预览图'}加载超时，请重试',
          HttpException() ||
          SocketException() => '${originalRequested ? '原图' : '预览图'}下载失败，请重试',
          _ => '${originalRequested ? '原图' : '预览图'}无法读取，请重试',
        },
      );
    } finally {
      if (generation == _generation) _read = null;
    }
  }

  Future<void> export({required bool save}) async {
    final image = state.image;
    if (image == null || _exporting) return;
    final generation = _generation;
    _exporting = true;
    state = state.withExport(true);
    String feedback;
    try {
      final service = ref.read(imageExportServiceProvider);
      if (save) {
        final path = await service.save(image.bytes);
        feedback = '已保存到 $path';
      } else {
        await service.copy(image.bytes);
        feedback = '图片已复制到剪贴板';
      }
    } on TimeoutException {
      feedback = save ? '保存操作超时，请先检查系统图片目录' : '复制操作超时，请先尝试粘贴确认结果';
    } catch (_) {
      // Native errors can contain local paths; show a stable user-facing error.
      feedback = save ? '图片保存失败，请检查目录权限和剩余空间后重试' : '图片复制失败，请重试';
    } finally {
      _exporting = false;
    }
    if (_disposed) return;
    state = state.withExport(
      false,
      generation == _generation ? feedback : null,
    );
  }
}
