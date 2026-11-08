import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'video_composition.dart';
import 'video_output.dart';

/// Keeps the surface identity stable while a source selects a new backend.
final class SwitchingVideoOutput
    implements FlutterVideoOutput, VideoFrameReadiness {
  final _output = ValueNotifier<VideoOutput?>(null);
  final _ready = ValueNotifier(false);
  final _retainedFrame = ValueNotifier<ui.Image?>(null);
  final _surfaces = <_SwitchingSurfaceState>{};
  int _captureRevision = 0;

  /// One bounded, in-memory frame bridges native release and track preparation.
  /// Normal buffering keeps the native texture and never copies video frames.
  Future<void> retainFrame() async {
    if (_retainedFrame.value != null || !_ready.value) return;
    final revision = ++_captureRevision;
    final current = _output.value;
    if (current is SwitchingVideoOutput) {
      final image = current._retainedFrame.value;
      if (image != null) {
        // A configurable engine can replace its child runtime. Share that
        // child's retained pixels instead of doing a second GPU readback.
        _retainedFrame.value = image.clone();
        _updateReady();
        return;
      }
    }
    final capture = () async {
      for (final surface in _surfaces.toList().reversed) {
        final image = await surface.capture();
        if (image == null) continue;
        if (revision != _captureRevision) {
          image.dispose();
          return;
        }
        _retainedFrame.value = image;
        _updateReady();
        return;
      }
    }();
    try {
      await capture.timeout(const Duration(milliseconds: 250));
    } on Object {
      // Hidden/unpainted outputs have no frame to retain. A late raster result
      // still belongs to this request and must dispose itself after timeout.
      if (revision == _captureRevision) ++_captureRevision;
    }
  }

  void clearRetainedFrame() {
    ++_captureRevision;
    final image = _retainedFrame.value;
    _retainedFrame.value = null;
    // RawImage may still be referenced by this frame's render tree.
    if (image != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => image.dispose());
      WidgetsBinding.instance.scheduleFrame();
    }
    _updateReady();
  }

  Object? _owner;
  ({double width, double height, double dpr})? _viewport;

  @override
  ValueListenable<bool> get frameReady => _ready;

  void _updateReady() {
    final current = _output.value;
    _ready.value =
        _retainedFrame.value != null ||
        switch (current) {
          VideoFrameReadiness readiness => readiness.frameReady.value,
          _ => false,
        };
  }

  void bind(VideoOutput? output) {
    final old = _output.value;
    if (identical(old, output)) return;
    if (old case VideoFrameReadiness readiness) {
      readiness.frameReady.removeListener(_updateReady);
    }
    if (_owner case final owner?) old?.detach(owner);
    _output.value = output;
    if (output case VideoFrameReadiness readiness) {
      readiness.frameReady.addListener(_updateReady);
    }
    if (_owner case final owner?) {
      output?.attach(owner);
      if (_viewport case final viewport?) {
        output?.updateViewport(
          owner,
          logicalWidth: viewport.width,
          logicalHeight: viewport.height,
          devicePixelRatio: viewport.dpr,
        );
      }
    }
    _updateReady();
  }

  @override
  void attach(Object owner) {
    if (_owner case final previous?) _output.value?.detach(previous);
    _owner = owner;
    _viewport = null;
    _output.value?.attach(owner);
  }

  @override
  void detach(Object owner) {
    if (!identical(owner, _owner)) return;
    _output.value?.detach(owner);
    _owner = null;
    _viewport = null;
  }

  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {
    if (!identical(owner, _owner)) return;
    _viewport = (
      width: logicalWidth,
      height: logicalHeight,
      dpr: devicePixelRatio,
    );
    _output.value?.updateViewport(
      owner,
      logicalWidth: logicalWidth,
      logicalHeight: logicalHeight,
      devicePixelRatio: devicePixelRatio,
    );
  }

  @override
  Widget buildVideoSurface() => _SwitchingSurface(this);

  void dispose() {
    clearRetainedFrame();
    bind(null);
    _output.dispose();
    _ready.dispose();
    _retainedFrame.dispose();
  }
}

final class _SwitchingSurface extends StatefulWidget {
  const _SwitchingSurface(this.output);
  final SwitchingVideoOutput output;

  @override
  State<_SwitchingSurface> createState() => _SwitchingSurfaceState();
}

final class _SwitchingSurfaceState extends State<_SwitchingSurface> {
  final _boundary = GlobalKey();

  @override
  void initState() {
    super.initState();
    widget.output._surfaces.add(this);
  }

  @override
  void didUpdateWidget(_SwitchingSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.output, widget.output)) {
      oldWidget.output._surfaces.remove(this);
      widget.output._surfaces.add(this);
    }
  }

  @override
  void dispose() {
    widget.output._surfaces.remove(this);
    super.dispose();
  }

  Future<ui.Image?> capture() async {
    final boundary = _boundary.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary ||
        !boundary.attached ||
        !boundary.hasSize ||
        boundary.size.isEmpty ||
        boundary.debugNeedsPaint) {
      return null;
    }
    // At most 1920 x 1080 pixels (~8 MiB), including letterboxing. No disk I/O.
    final ratio = math.min(
      View.of(context).devicePixelRatio,
      math.min(1920 / boundary.size.width, 1080 / boundary.size.height),
    );
    return boundary.toImage(pixelRatio: ratio);
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    alignment: Alignment.center,
    children: [
      RepaintBoundary(
        key: _boundary,
        child: ValueListenableBuilder<VideoOutput?>(
          valueListenable: widget.output._output,
          builder: (context, output, _) => output is FlutterVideoOutput
              ? output.buildVideoSurface()
              : const ColoredBox(color: Color(0xFF000000)),
        ),
      ),
      ValueListenableBuilder<ui.Image?>(
        valueListenable: widget.output._retainedFrame,
        builder: (context, image, _) => image == null
            ? const SizedBox.shrink()
            : ColoredBox(
                color: const Color(0xFF000000),
                child: RawImage(image: image, fit: BoxFit.contain),
              ),
      ),
    ],
  );
}
