import 'player_contract.dart';
import 'player_diagnostics.dart';

/// A decoder error retires the whole pair, even while video/cache can advance.
/// Recovery is owned by the session's existing bounded retry policy.
final class NativeAudioErrorMonitor {
  NativeAudioErrorMonitor({required this.snapshot, required this.onFailure});

  final PlaybackSnapshot Function() snapshot;
  final void Function() onFailure;
  int? _generation;
  bool _disposed = false, _failed = false;

  void report(NativeErrorSummary error, NativeLogSeverity severity) {
    if (_disposed ||
        _failed ||
        severity == NativeLogSeverity.warning ||
        error.cause != NativeErrorCause.decoder ||
        !const {'ad', 'ffmpeg/audio'}.contains(error.component)) {
      return;
    }
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
