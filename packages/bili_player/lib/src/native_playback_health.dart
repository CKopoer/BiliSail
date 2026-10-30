import 'player_contract.dart';

/// Playback position alone can be driven by just one surviving DASH track.
/// Sample both the main video buffer and the external audio clock. The native
/// cache handles ordinary underruns; this also catches premature per-track EOF
/// and buffering that never reports an error or another position event.
final class NativePlaybackHealth {
  PlaybackSnapshot? _last;
  Duration? _progressAt;
  Duration? _audioPosition;

  ({PlayerFailureKind kind, Duration position})? update(
    PlaybackSnapshot snapshot,
    Duration now, {
    required bool paired,
    Duration? audioPosition,
  }) {
    final previous = _last;
    _last = snapshot;
    if (!snapshot.desiredPlaying ||
        snapshot.isSeeking ||
        !const {
          PlaybackPhase.playing,
          PlaybackPhase.buffering,
          PlaybackPhase.paused,
        }.contains(snapshot.phase) ||
        previous == null ||
        previous.generation != snapshot.generation ||
        snapshot.position < previous.position) {
      _progressAt = now;
      _audioPosition = audioPosition != null && audioPosition >= Duration.zero
          ? audioPosition
          : null;
      return null;
    }
    if (paired &&
        snapshot.buffered > Duration.zero &&
        (snapshot.duration <= Duration.zero ||
            snapshot.duration - snapshot.buffered >
                const Duration(milliseconds: 500)) &&
        snapshot.position - snapshot.buffered >
            const Duration(milliseconds: 250)) {
      return (
        kind: PlayerFailureKind.videoInterrupted,
        position: snapshot.buffered,
      );
    }
    if (paired) {
      // mpv may make audio-pts unavailable once that track reaches EOF. Retain
      // its last clock so video progress cannot disguise the missing audio.
      if (audioPosition != null && audioPosition >= Duration.zero) {
        _audioPosition = audioPosition;
      }
      final audio = _audioPosition;
      if (audio != null &&
          snapshot.position - audio > const Duration(milliseconds: 750) &&
          (snapshot.duration <= Duration.zero ||
              snapshot.duration - snapshot.position >
                  const Duration(milliseconds: 500))) {
        return (kind: PlayerFailureKind.nativePlayback, position: audio);
      }
    }
    if (snapshot.position > previous.position && !snapshot.isBuffering) {
      _progressAt = now;
    }
    final progressAt = _progressAt ??= now;
    if (now - progressAt >= const Duration(seconds: 8)) {
      return (
        kind: PlayerFailureKind.nativePlayback,
        position: snapshot.position,
      );
    }
    return null;
  }

  void reset() {
    _last = null;
    _progressAt = null;
    _audioPosition = null;
  }
}
