import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/image_viewer/application/image_viewer_controller.dart';
import '../../features/image_viewer/domain/original_image.dart';

Future<void> showImageViewer(
  BuildContext context,
  List<Uri> images,
  int index,
) {
  if (images.isEmpty) return Future.value();
  return showDialog<void>(
    context: context,
    builder: (_) => ImageViewer(request: ImageViewerRequest(images, index)),
  );
}

class ImageViewer extends ConsumerStatefulWidget {
  const ImageViewer({super.key, required this.request});
  final ImageViewerRequest request;
  @override
  ConsumerState<ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends ConsumerState<ImageViewer> {
  final _transform = TransformationController();
  final _focus = FocusNode();
  OriginalImage? _shown;
  Size _viewport = Size.zero;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(imageViewerControllerProvider(widget.request).notifier).load();
      }
    });
  }

  void _evict(OriginalImage? image) {
    if (image == null) return;
    MemoryImage(image.bytes).evict();
    ResizeImage(MemoryImage(image.bytes), width: 256).evict();
  }

  @override
  void dispose() {
    _evict(_shown);
    _transform.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _scale(double scale) {
    final image = _shown;
    if (image == null || _viewport.isEmpty) return;
    final clamped = scale.clamp(.01, 8.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (_viewport.width - image.width * clamped) / 2,
        (_viewport.height - image.height * clamped) / 2,
        0,
        1,
      )
      ..scaleByDouble(clamped, clamped, 1, 1);
  }

  void _fit() {
    final image = _shown;
    if (image == null) return;
    final width = _viewport.width / image.width;
    final height = _viewport.height / image.height;
    _scale((width < height ? width : height).clamp(.01, 1));
  }

  void _zoom(double factor) =>
      _scale(_transform.value.getMaxScaleOnAxis() * factor);

  void _move(int delta) {
    final provider = imageViewerControllerProvider(widget.request);
    ref.read(provider.notifier).load(ref.read(provider).index + delta);
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.pop(context);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.pageUp) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.pageDown) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.equal ||
        key == LogicalKeyboardKey.numpadAdd) {
      _zoom(1.25);
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.minus ||
        key == LogicalKeyboardKey.numpadSubtract) {
      _zoom(.8);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  Widget _button(String tooltip, IconData icon, VoidCallback? action) =>
      IconButton(
        tooltip: tooltip,
        onPressed: action,
        icon: Icon(icon, size: 20),
        color: Colors.white,
        disabledColor: Colors.white38,
      );

  Widget _group(List<Widget> children) => GestureDetector(
    excludeFromSemantics: true,
    onTap: () {},
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xdd202020),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(imageViewerControllerProvider(widget.request));
    final image = state.image;
    if (!identical(image, _shown)) {
      _evict(_shown);
      _shown = image;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
    return Dialog.fullscreen(
      child: Focus(
        autofocus: true,
        focusNode: _focus,
        onKeyEvent: _key,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: () => Navigator.pop(context),
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(color: Theme.of(context).colorScheme.surface),
              ),
              if (image != null)
                Positioned.fill(
                  child: Opacity(
                    opacity: .14,
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                      child: Image.memory(
                        image.bytes,
                        fit: BoxFit.cover,
                        cacheWidth: 256,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              Positioned.fill(
                bottom: 112,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      if (_viewport != size) {
                        _viewport = size;
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _fit();
                        });
                      }
                      if (state.loading) {
                        return const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 16),
                              Text('正在加载原图…'),
                            ],
                          ),
                        );
                      }
                      if (image == null) {
                        return Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(state.message ?? '图片加载失败'),
                              const SizedBox(height: 12),
                              TextButton(
                                onPressed: () => ref
                                    .read(
                                      imageViewerControllerProvider(
                                        widget.request,
                                      ).notifier,
                                    )
                                    .load(),
                                child: const Text('重试'),
                              ),
                            ],
                          ),
                        );
                      }
                      return Listener(
                        onPointerSignal: (event) {
                          if (event is PointerScrollEvent &&
                              HardwareKeyboard.instance.isControlPressed) {
                            GestureBinding.instance.pointerSignalResolver
                                .register(
                                  event,
                                  (_) => _zoom(
                                    event.scrollDelta.dy < 0 ? 1.25 : .8,
                                  ),
                                );
                          }
                        },
                        child: InteractiveViewer(
                          transformationController: _transform,
                          constrained: false,
                          minScale: .01,
                          maxScale: 8,
                          boundaryMargin: const EdgeInsets.all(double.infinity),
                          // The hit area follows the transformed image, leaving
                          // the surrounding viewport available for dismissal.
                          child: GestureDetector(
                            excludeFromSemantics: true,
                            onTap: () {},
                            child: Image.memory(
                              image.bytes,
                              width: image.width.toDouble(),
                              height: image.height.toDouble(),
                              fit: BoxFit.fill,
                              semanticLabel: '原图 ${state.index + 1}',
                              errorBuilder: (_, _, _) =>
                                  const Center(child: Text('原图解码失败')),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  tooltip: '关闭图片',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 16,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Wrap(
                      alignment: WrapAlignment.center,
                      spacing: 10,
                      runSpacing: 8,
                      children: [
                        _group([
                          _button(
                            '适应窗口',
                            Icons.fit_screen,
                            image == null ? null : _fit,
                          ),
                          _button(
                            '原始大小',
                            Icons.photo_size_select_actual_outlined,
                            image == null ? null : () => _scale(1),
                          ),
                          _button(
                            '缩小',
                            Icons.remove_circle_outline,
                            image == null ? null : () => _zoom(.8),
                          ),
                          ValueListenableBuilder<Matrix4>(
                            valueListenable: _transform,
                            builder: (_, matrix, _) => SizedBox(
                              width: 54,
                              child: Text(
                                '${(matrix.getMaxScaleOnAxis() * 100).round()}%',
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.white),
                              ),
                            ),
                          ),
                          _button(
                            '放大',
                            Icons.add_circle_outline,
                            image == null ? null : () => _zoom(1.25),
                          ),
                        ]),
                        _group([
                          _button(
                            '上一张',
                            Icons.skip_previous_outlined,
                            state.index <= 0 ? null : () => _move(-1),
                          ),
                          Text(
                            '${state.index + 1} / ${widget.request.images.length}',
                            style: const TextStyle(color: Colors.white),
                          ),
                          _button(
                            '下一张',
                            Icons.skip_next_outlined,
                            state.index + 1 >= widget.request.images.length
                                ? null
                                : () => _move(1),
                          ),
                        ]),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
