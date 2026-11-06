import 'dart:math' as math;

import 'player_contract.dart';

/// Bound the intermediate render target, preserving decode size and aspect.
/// Invalid/missing layout keeps the source size; never upscale a small source.
VideoDimensions androidVideoViewport(
  VideoDimensions source, {
  required double physicalWidth,
  required double physicalHeight,
}) {
  if (source.width < 2 ||
      source.height < 2 ||
      !physicalWidth.isFinite ||
      !physicalHeight.isFinite ||
      physicalWidth < 2 ||
      physicalHeight < 2) {
    return source;
  }
  final scale = math.min(
    1.0,
    math.min(physicalWidth / source.width, physicalHeight / source.height),
  );
  return VideoDimensions(
    (source.width * scale).ceil().clamp(2, source.width),
    (source.height * scale).ceil().clamp(2, source.height),
  );
}

/// Serializes surface resizing and skips superseded layouts before native work.
/// The apply port must also guard its generation after asynchronous native calls.
final class AndroidVideoSurfaceSizer {
  AndroidVideoSurfaceSizer({required this.apply, required this.isCurrent});

  final Future<void> Function(VideoDimensions dimensions) apply;
  final bool Function() isCurrent;
  Future<void> _pending = Future.value();
  VideoDimensions? _requested;
  VideoDimensions? _applied;
  int _revision = 0;

  VideoDimensions? get applied => _applied;
  Future<void> get pending => _pending;

  Future<void> request(VideoDimensions dimensions, {bool force = false}) {
    if (!force && dimensions == _requested) return _pending;
    _requested = dimensions;
    final revision = ++_revision;
    final task = _pending.then((_) async {
      if (revision != _revision || !isCurrent()) return;
      try {
        await apply(dimensions);
        if (revision == _revision && isCurrent()) _applied = dimensions;
      } on Object {
        if (revision == _revision) _requested = null;
        rethrow;
      }
    });
    // One failed resize must not poison subsequent layouts. Return the error
    // to this caller; keep a recovered tail solely for serializing later work.
    _pending = task.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return task;
  }

  void invalidate() {
    _revision++;
    _requested = null;
    _applied = null;
  }
}
