import 'dart:async';

/// A renderer callback from before Surface binding cannot confirm direct output.
final class FvpFirstVideoFrame {
  final _rendered = Completer<bool>();
  final _consumed = Completer<bool>();

  Future<bool> ready({required bool directSurface}) =>
      directSurface ? _consumed.future : _rendered.future;

  void rendered(bool success) {
    if (!_rendered.isCompleted) _rendered.complete(success);
  }

  void surfaceConsumed() {
    if (!_consumed.isCompleted) _consumed.complete(true);
  }
}

/// Surface binding reopens MediaCodec asynchronously. Do not seek while that
/// decoder is still starting, or while its playing pipeline is draining.
Future<bool> confirmFvpSurfacePreroll({
  required Future<bool> firstFrame,
  required Future<void> Function() pauseAndWait,
  Future<int> Function()? seek,
}) async {
  if (!await firstFrame) return false;
  if (seek == null) return true;
  await pauseAndWait();
  return await seek() >= 0;
}
