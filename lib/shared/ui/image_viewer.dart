import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/input/input_stroke.dart';
import '../../core/input/shortcut_dispatcher.dart';
import '../../core/presentation/input_scope.dart';
import '../../domain/shortcut_command.dart';

import '../../features/image_viewer/application/image_viewer_controller.dart';
import '../../features/image_viewer/domain/original_image.dart';
import 'app_network_image.dart';

Future<void> showImageViewer(
  BuildContext context,
  List<Uri> images,
  int index,
) {
  if (images.isEmpty) return Future.value();
  final navigator = Navigator.of(context);
  final cache = AppImageCacheScope.maybeOf(context);
  final generation = cache?.bytes.generation;
  // The request identifies the controller for this preview. Route rebuilds
  // must keep it stable because the viewer starts loading only in initState.
  final request = ImageViewerRequest(
    images,
    index,
    findPreview: cache == null
        ? null
        : (source) {
            if (cache.bytes.generation != generation) return null;
            final preview = cache.previewFor(source);
            if (preview == null ||
                !OriginalImage.acceptsDimensions(
                  preview.width,
                  preview.height,
                )) {
              return null;
            }
            return (
              image: OriginalImage(
                bytes: preview.bytes,
                width: preview.width,
                height: preview.height,
              ),
              isOriginal: preview.isOriginal,
            );
          },
  );
  // showDialog creates a native window when desktop windowing is enabled in
  // the pinned SDK. Keep the shared viewer on its owning window's Navigator.
  return navigator.push<void>(
    DialogRoute<void>(
      context: context,
      builder: (_) => ImageViewer(request: request),
      // The viewer paints its background edge to edge and protects controls
      // with its own safe area. A route-level inset would expose the barrier.
      useSafeArea: false,
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

class _ImageViewerState extends ConsumerState<ImageViewer>
    with SingleTickerProviderStateMixin {
  final _transform = TransformationController();
  final _focus = FocusNode();
  late final AnimationController _slideOffset;
  OriginalImage? _shown;
  int? _shownIndex;
  Size _viewport = Size.zero;
  final _pointers = <int>{};
  ({int pointer, int index, Offset position})? _swipeStart;
  ({int index, ImageViewerPreview? preview})? _neighbor;

  @override
  void initState() {
    super.initState();
    _slideOffset = AnimationController.unbounded(vsync: this);
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
    _evict(_neighbor?.preview?.image);
    _slideOffset.dispose();
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
    if (_pointers.length > 1) {
      _swipeStart = null;
      if (_neighbor != null) unawaited(_settleSwipe(commit: false));
    } else if (event.buttons == kPrimaryButton &&
        _canSwipe &&
        !_slideOffset.isAnimating) {
      _swipeStart = (
        pointer: event.pointer,
        index: ref.read(imageViewerControllerProvider(widget.request)).index,
        position: event.localPosition,
      );
    }
  }

  void _updateSwipe(PointerMoveEvent event) {
    final start = _swipeStart;
    if (start == null || start.pointer != event.pointer || !_canSwipe) return;
    final delta = event.localPosition - start.position;
    if (_neighbor == null &&
        (delta.dx.abs() < kTouchSlop ||
            delta.dx.abs() <= delta.dy.abs() * 1.5)) {
      return;
    }
    final next = start.index + (delta.dx < 0 ? 1 : -1);
    if (next < 0 || next >= widget.request.images.length || delta.dx == 0) {
      _slideOffset.value = 0;
      return;
    }
    if (_neighbor?.index != next) {
      _evict(_neighbor?.preview?.image);
      setState(() {
        _neighbor = (index: next, preview: widget.request.cachedPreview(next));
      });
    }
    _slideOffset.value = delta.dx.clamp(-_viewport.width, _viewport.width);
  }

  void _endSwipe(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    final start = _swipeStart;
    if (start == null || start.pointer != event.pointer) return;
    _swipeStart = null;
    final delta = event.localPosition - start.position;
    final threshold = (_viewport.width * .15).clamp(48.0, 100.0);
    final commit =
        _canSwipe &&
        _neighbor?.index == start.index + (delta.dx < 0 ? 1 : -1) &&
        delta.dx.abs() >= threshold &&
        delta.dx.abs() > delta.dy.abs() * 1.5;
    unawaited(_settleSwipe(commit: commit));
  }

  void _cancelSwipe(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_swipeStart?.pointer != event.pointer) return;
    _swipeStart = null;
    unawaited(_settleSwipe(commit: false));
  }

  Future<void> _settleSwipe({required bool commit}) async {
    final neighbor = _neighbor;
    if (neighbor == null) return;
    final target = commit ? _slideOffset.value.sign * _viewport.width : 0.0;
    try {
      await _slideOffset
          .animateTo(
            target,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }
    if (!mounted) return;
    final selected = commit && _canSwipe;
    _resetSwipe(evictNeighbor: !selected);
    if (selected) {
      unawaited(
        ref
            .read(imageViewerControllerProvider(widget.request).notifier)
            .load(neighbor.index),
      );
      if (!identical(_shown?.bytes, neighbor.preview?.image.bytes)) {
        _evict(neighbor.preview?.image);
      }
    }
  }

  void _resetSwipe({bool evictNeighbor = true}) {
    _swipeStart = null;
    _slideOffset.value = 0;
    if (evictNeighbor) _evict(_neighbor?.preview?.image);
    if (_neighbor != null) setState(() => _neighbor = null);
  }

  void _zoom(double factor) {
    _resetSwipe();
    _scale(_transform.value.getMaxScaleOnAxis() * factor);
  }

  void _move(int delta) {
    _resetSwipe();
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

  Widget _buildViewport(ImageViewerState state) => Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: _startSwipe,
    onPointerMove: _updateSwipe,
    onPointerUp: _endSwipe,
    onPointerCancel: _cancelSwipe,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_viewport != size) {
          final widthChanged = _viewport.width != size.width;
          _viewport = size;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            if (widthChanged) _resetSwipe();
            _fit();
          });
        }
        final current = _buildCurrentPage(state);
        final neighbor = _neighbor;
        final adjacent = neighbor == null
            ? null
            : _buildAdjacentPage(neighbor.index, neighbor.preview);
        final displacement =
            ((neighbor?.index ?? state.index) - state.index) * size.width;
        return ClipRect(
          child: ValueListenableBuilder<double>(
            valueListenable: _slideOffset,
            // Keep the main image mounted throughout the drag and settle.
            child: current,
            builder: (_, offset, child) => Stack(
              fit: StackFit.expand,
              children: [
                Transform.translate(offset: Offset(offset, 0), child: child),
                if (adjacent != null)
                  IgnorePointer(
                    child: ExcludeSemantics(
                      child: Transform.translate(
                        offset: Offset(displacement + offset, 0),
                        child: adjacent,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _loadingPage(bool original) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 16),
        Text(original ? '正在加载原图…' : '正在加载预览图…'),
      ],
    ),
  );

  Widget _buildAdjacentPage(int index, ImageViewerPreview? preview) {
    if (preview == null) {
      return _loadingPage(
        widget.request.previewSource(index) == widget.request.images[index],
      );
    }
    return Center(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: _buildPicture(
          preview.image,
          index: index,
          isOriginal: preview.isOriginal,
        ),
      ),
    );
  }

  Widget _buildCurrentPage(ImageViewerState state) {
    final image = state.image;
    if (image == null) {
      if (state.loading) return _loadingPage(state.originalRequested);
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(state.message ?? '图片加载失败'),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => ref
                  .read(imageViewerControllerProvider(widget.request).notifier)
                  .retry(),
              child: Text(state.originalRequested ? '查看原图' : '重试'),
            ),
          ],
        ),
      );
    }
    return Listener(
      onPointerSignal: (event) {
        if (event is PointerScrollEvent &&
            InputModifierScope.anyPressedOf(context, const [
              LogicalKeyboardKey.controlLeft,
              LogicalKeyboardKey.controlRight,
            ])) {
          GestureBinding.instance.pointerSignalResolver.register(
            event,
            (_) => _zoom(event.scrollDelta.dy < 0 ? 1.25 : .8),
          );
        }
      },
      child: ValueListenableBuilder<Matrix4>(
        valueListenable: _transform,
        // Toolbar hover and tooltip animations must not repaint the image.
        builder: (_, _, child) => RepaintBoundary(
          child: InteractiveViewer(
            transformationController: _transform,
            panEnabled: !_canSwipe,
            constrained: false,
            minScale: .0001,
            maxScale: 8,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            child: child!,
          ),
        ),
        // The hit area follows the image, leaving the surrounding viewport
        // available for dismissal.
        child: GestureDetector(
          excludeFromSemantics: true,
          onTap: () {},
          child: _buildPicture(
            image,
            index: state.index,
            isOriginal: state.isOriginal,
          ),
        ),
      ),
    );
  }

  Widget _buildPicture(
    OriginalImage image, {
    required int index,
    required bool isOriginal,
  }) => Image(
    key: ValueKey(index),
    image: _imageProvider(image),
    width: image.width.toDouble(),
    height: image.height.toDouble(),
    fit: BoxFit.fill,
    gaplessPlayback: true,
    semanticLabel: '${isOriginal ? '原图' : '预览图'} ${index + 1}',
    errorBuilder: (_, _, _) => const Center(child: Text('图片解码失败')),
  );

  @override
  Widget build(BuildContext context) {
    final provider = imageViewerControllerProvider(widget.request);
    final state = ref.watch(provider);
    ref.listen(provider, (_, next) {
      if (identical(next.image, _shown) && next.index == _shownIndex) return;
      _evict(_shown);
      _shown = next.image;
      _shownIndex = next.index;
      _fit();
    });
    ref.listen(imageViewerSessionProvider, (previous, next) {
      if (previous != next) _resetSwipe();
    });
    final canExport = ref.watch(imageExportServiceProvider).supported;
    final safePadding = MediaQuery.paddingOf(context);
    final image = state.image;
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
                          gaplessPlayback: true,
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
                            child: _buildViewport(state),
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
                                  if (!state.isOriginal &&
                                      (image != null ||
                                          !state.originalRequested) &&
                                      widget.request.previewSource(
                                            state.index,
                                          ) !=
                                          widget.request.images[state.index])
                                    _group([
                                      TextButton.icon(
                                        onPressed:
                                            state.loading &&
                                                state.originalRequested
                                            ? null
                                            : () => ref
                                                  .read(
                                                    imageViewerControllerProvider(
                                                      widget.request,
                                                    ).notifier,
                                                  )
                                                  .loadOriginal(),
                                        icon:
                                            state.loading &&
                                                state.originalRequested
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(Icons.hd_outlined),
                                        label: Text(
                                          state.loading &&
                                                  state.originalRequested
                                              ? '正在加载原图…'
                                              : '查看原图',
                                        ),
                                        style: TextButton.styleFrom(
                                          foregroundColor: Colors.white,
                                        ),
                                      ),
                                    ]),
                                  if (canExport)
                                    _group([
                                      _button(
                                        state.isOriginal ? '保存图片' : '保存预览图',
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
                                        state.isOriginal ? '复制图片' : '复制预览图',
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
                                      '实际大小',
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
                  top: safePadding.top + 8,
                  right: safePadding.right + 8,
                  child: IconButton(
                    tooltip: '关闭图片',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ),
                if (state.exportMessage != null ||
                    (image != null && state.message != null) ||
                    image?.scaledPreview == true)
                  Positioned(
                    top: safePadding.top + 12,
                    left: safePadding.left + 16,
                    right: safePadding.right + 64,
                    child: Text(
                      state.exportMessage ??
                          state.message ??
                          '大图采用缩小预览，保存和复制使用原图',
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
