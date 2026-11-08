import 'dart:async';

/// A newly bound direct Surface must receive a real image before paused seek.
/// The caller advances only the video pipe and keeps companion audio paused.
Future<bool> confirmFvpDirectSurface({
  required void Function() startVideo,
  required Future<bool> Function() firstFrame,
  required Future<void> Function() pauseAndWait,
  required void Function() checkActive,
  Future<int> Function()? seek,
}) async {
  checkActive();
  try {
    startVideo();
    if (!await firstFrame()) return false;
    checkActive();
  } finally {
    await pauseAndWait();
  }
  checkActive();
  if (seek != null) {
    final position = await seek();
    checkActive();
    if (position < 0) return false;
  }
  return true;
}

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
