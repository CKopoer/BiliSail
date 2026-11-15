import 'player_contract.dart';
import 'player_diagnostics.dart';

/// A failed hardware decoder/output cannot be cleared by the audio clock.
/// Recoverable bitstream errors retain the existing progress/deadline policy.
final class NativeVideoErrorMonitor {
  NativeVideoErrorMonitor({required this.snapshot, required this.onFailure});

  final PlaybackSnapshot Function() snapshot;
  final void Function() onFailure;
  int? _generation;
  bool _failed = false, _disposed = false;

  void report(NativeErrorSummary error, NativeLogSeverity severity) {
    if (_disposed || _failed) return;
    final hardwareFailure =
        error.isVideoDecodeError &&
        error.cause == NativeErrorCause.hardwareDecoder;
    final outputFailure =
        error.cause == NativeErrorCause.videoOutput &&
        severity != NativeLogSeverity.warning;
    // mpv's vd_lavc.handle_err reports actual hardware frame failures as WARN.
    // Advice, corrupt packets and a decoder's normal fallback are not failures.
    if (!hardwareFailure && !outputFailure) return;
    _generation ??= snapshot().generation;
    update();
  }

  void update() {
    if (_disposed || _generation == null) return;
    final value = snapshot();
    if (value.generation != _generation ||
        value.isSeeking ||
        !const {
          PlaybackPhase.playing,
          PlaybackPhase.buffering,
          PlaybackPhase.paused,
        }.contains(value.phase)) {
      reset();
      return;
    }
    if (!value.desiredPlaying || value.phase == PlaybackPhase.paused) return;
    _generation = null;
    _failed = true;
    onFailure();
  }

  void reset() {
    _generation = null;
    _failed = false;
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
