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
