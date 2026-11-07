import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'video_composition.dart';
import 'video_output.dart';

/// Keeps the surface identity stable while a source selects a new backend.
final class SwitchingVideoOutput
    implements FlutterVideoOutput, VideoFrameReadiness {
  final _output = ValueNotifier<VideoOutput?>(null);
  final _ready = ValueNotifier(false);
  Object? _owner;
  ({double width, double height, double dpr})? _viewport;

  @override
  ValueListenable<bool> get frameReady => _ready;

  void _updateReady() {
    final current = _output.value;
    _ready.value = switch (current) {
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
    _ready.value = false;
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
  Widget buildVideoSurface() => ValueListenableBuilder<VideoOutput?>(
    valueListenable: _output,
    builder: (context, output, _) => output is FlutterVideoOutput
        ? output.buildVideoSurface()
        : const ColoredBox(color: Color(0xFF000000)),
  );

  void dispose() {
    bind(null);
    _output.dispose();
    _ready.dispose();
  }
}
