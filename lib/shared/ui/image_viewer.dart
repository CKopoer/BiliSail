import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/input_stroke.dart';
import '../../core/input/shortcut_dispatcher.dart';
import '../../core/presentation/input_scope.dart';
import '../../domain/shortcut_command.dart';

import '../../features/image_viewer/application/image_viewer_controller.dart';
import '../../features/image_viewer/domain/original_image.dart';

Future<void> showImageViewer(
  BuildContext context,
  List<Uri> images,
  int index,
) {
  if (images.isEmpty) return Future.value();
  final navigator = Navigator.of(context);
  // The request identifies the controller for this preview. Route rebuilds
  // must keep it stable because the viewer starts loading only in initState.
  final request = ImageViewerRequest(images, index);
  // showDialog creates a native window when desktop windowing is enabled in
  // the pinned SDK. Keep the shared viewer on its owning window's Navigator.
  return navigator.push<void>(
    DialogRoute<void>(
      context: context,
      builder: (_) => ImageViewer(request: request),
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      barrierColor:
          DialogTheme.of(context).barrierColor ??
          Theme.of(context).dialogTheme.barrierColor ??
          Colors.black54,
      traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop,
    ),
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
  int? _shownIndex;
  Size _viewport = Size.zero;
  final _pointers = <int>{};
  ({int pointer, int index, Offset position})? _swipeStart;

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
    _imageProvider(image).evict();
    _imageProvider(image, background: true).evict();
  }

  ImageProvider<Object> _imageProvider(
    OriginalImage image, {
    bool background = false,
  }) => ResizeImage(
    MemoryImage(image.bytes),
    width: background ? 256 : image.previewWidth,
    height: background ? 256 : image.previewHeight,
    policy: ResizeImagePolicy.fit,
  );

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
    final clamped = scale.clamp(.0001, 8.0);
    _transform.value = Matrix4.identity()
      ..translateByDouble(
        (_viewport.width - image.width * clamped) / 2,
        (_viewport.height - image.height * clamped) / 2,
        0,
        1,
      )
      // InteractiveViewer reads the maximum scale across all three axes.
      ..scaleByDouble(clamped, clamped, clamped, 1);
  }

  double get _fitScale {
    final image = _shown;
    if (image == null || _viewport.isEmpty) return 1;
    final width = _viewport.width / image.width;
    final height = _viewport.height / image.height;
    return (width < height ? width : height).clamp(.0001, 1);
  }

  void _fit() => _scale(_fitScale);

  bool get _canSwipe =>
      widget.request.images.length > 1 &&
      (_shown == null ||
          _transform.value.getMaxScaleOnAxis() <= _fitScale * 1.001);

  void _startSwipe(PointerDownEvent event) {
    _pointers.add(event.pointer);
    // Observe the same pointers as InteractiveViewer without competing with
    // its scale recognizer. A second finger cancels paging until all lift.
    _swipeStart = _pointers.length == 1 && _canSwipe
        ? (
            pointer: event.pointer,
            index: ref
                .read(imageViewerControllerProvider(widget.request))
                .index,
            position: event.localPosition,
          )
        : null;
  }

  void _endSwipe(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    final start = _swipeStart;
    _swipeStart = null;
    if (start == null ||
        start.pointer != event.pointer ||
        !_canSwipe ||
        start.index !=
            ref.read(imageViewerControllerProvider(widget.request)).index) {
      return;
    }
    final delta = event.localPosition - start.position;
    final threshold = (_viewport.width * .15).clamp(48.0, 100.0);
    if (delta.dx.abs() >= threshold && delta.dx.abs() > delta.dy.abs() * 1.5) {
      _move(delta.dx < 0 ? 1 : -1);
    }
  }

  void _cancelSwipe(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _swipeStart = null;
  }

  void _zoom(double factor) =>
      _scale(_transform.value.getMaxScaleOnAxis() * factor);

  void _move(int delta) {
    final provider = imageViewerControllerProvider(widget.request);
    ref.read(provider.notifier).load(ref.read(provider).index + delta);
  }

  CommandOutcome _command(ReservedShortcut command, InputStroke stroke) {
    if (stroke.phase == InputPhase.up) return CommandOutcome.noOp;
    switch (command) {
      case ReservedShortcut.imageClose:
        Navigator.pop(context);
      case ReservedShortcut.imagePrevious:
        _move(-1);
      case ReservedShortcut.imageNext:
        _move(1);
      case ReservedShortcut.imageZoomIn:
        _zoom(1.25);
      case ReservedShortcut.imageZoomOut:
        _zoom(.8);
    }
    return CommandOutcome.completed;
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
    final canExport = ref.watch(imageExportServiceProvider).supported;
    final image = state.image;
    if (!identical(image, _shown) || state.index != _shownIndex) {
      _evict(_shown);
      _shown = image;
      _shownIndex = state.index;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fit();
      });
    }
    return CommandTargetScope<Object>(
      scope: CommandScope.local,
      commands: {
        for (final command in [
          ReservedShortcut.imageClose,
          ReservedShortcut.imagePrevious,
          ReservedShortcut.imageNext,
          ReservedShortcut.imageZoomIn,
          ReservedShortcut.imageZoomOut,
        ])
          command: (stroke) => _command(command, stroke),
      },
      child: Dialog.fullscreen(
        child: Focus(
          autofocus: true,
          focusNode: _focus,

          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: () => Navigator.pop(context),
            child: Stack(
              children: [
                Positioned.fill(
                  child: ColoredBox(
                    color: Theme.of(context).colorScheme.surface,
                  ),
                ),
                if (image != null)
                  Positioned.fill(
                    child: Opacity(
                      opacity: .14,
                      child: ImageFiltered(
                        imageFilter: ui.ImageFilter.blur(
                          sigmaX: 28,
                          sigmaY: 28,
                        ),
                        child: Image(
                          image: _imageProvider(image, background: true),
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ),
                  ),
                Positioned.fill(
                  child: SafeArea(
                    child: Column(
                      children: [
                        const SizedBox(height: 48),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Listener(
                              behavior: HitTestBehavior.opaque,
                              onPointerDown: _startSwipe,
                              onPointerUp: _endSwipe,
                              onPointerCancel: _cancelSwipe,
                              child: LayoutBuilder(
                                builder: (context, constraints) {
                                  final size = constraints.biggest;
                                  if (_viewport != size) {
                                    _swipeStart = null;
                                    _viewport = size;
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
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
                                          InputModifierScope.anyPressedOf(
                                            context,
                                            const [
                                              LogicalKeyboardKey.controlLeft,
                                              LogicalKeyboardKey.controlRight,
                                            ],
                                          )) {
                                        GestureBinding
                                            .instance
                                            .pointerSignalResolver
                                            .register(
                                              event,
                                              (_) => _zoom(
                                                event.scrollDelta.dy < 0
                                                    ? 1.25
                                                    : .8,
                                              ),
                                            );
                                      }
                                    },
                                    child: ValueListenableBuilder<Matrix4>(
                                      valueListenable: _transform,
                                      builder: (_, _, child) =>
                                          InteractiveViewer(
                                            transformationController:
                                                _transform,
                                            panEnabled: !_canSwipe,
                                            constrained: false,
                                            minScale: .0001,
                                            maxScale: 8,
                                            boundaryMargin:
                                                const EdgeInsets.all(
                                                  double.infinity,
                                                ),
                                            // The hit area follows the transformed image, leaving
                                            // the surrounding viewport available for dismissal.
                                            child: child!,
                                          ),
                                      child: GestureDetector(
                                        excludeFromSemantics: true,
                                        onTap: () {},
                                        child: Image(
                                          image: _imageProvider(image),
                                          width: image.width.toDouble(),
                                          height: image.height.toDouble(),
                                          fit: BoxFit.fill,
                                          semanticLabel:
                                              '原图 ${state.index + 1}',
                                          errorBuilder: (_, _, _) =>
                                              const Center(
                                                child: Text('原图解码失败'),
                                              ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 10,
                                runSpacing: 8,
                                children: [
                                  if (canExport)
                                    _group([
                                      _button(
                                        '保存图片',
                                        Icons.save_alt,
                                        image == null || state.exporting
                                            ? null
                                            : () => ref
                                                  .read(
                                                    imageViewerControllerProvider(
                                                      widget.request,
                                                    ).notifier,
                                                  )
                                                  .export(save: true),
                                      ),
                                      _button(
                                        '复制图片',
                                        Icons.copy_outlined,
                                        image == null || state.exporting
                                            ? null
                                            : () => ref
                                                  .read(
                                                    imageViewerControllerProvider(
                                                      widget.request,
                                                    ).notifier,
                                                  )
                                                  .export(save: false),
                                      ),
                                    ]),
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
                                          style: const TextStyle(
                                            color: Colors.white,
                                          ),
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
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                    _button(
                                      '下一张',
                                      Icons.skip_next_outlined,
                                      state.index + 1 >=
                                              widget.request.images.length
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
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    tooltip: '关闭图片',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                if (state.exportMessage != null || image?.scaledPreview == true)
                  Positioned(
                    top: 12,
                    left: 16,
                    right: 64,
                    child: Text(
                      state.exportMessage ?? '大图采用缩小预览，保存和复制使用原图',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
