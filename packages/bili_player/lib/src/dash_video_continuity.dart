import 'player_contract.dart';

/// For a DASH pair, mpv's main demuxer buffer belongs to video. External audio
/// can continue after premature video EOF without a terminal END_FILE event.
/// Detect only confirmed playback beyond that buffer, away from normal EOF.
final class DashVideoContinuity {
  Duration? _since;
  PlaybackSnapshot? _last;

  Duration? update(PlaybackSnapshot snapshot, Duration now) {
    final previous = _last;
    _last = snapshot;
    final eligible =
        snapshot.phase == PlaybackPhase.playing &&
        snapshot.desiredPlaying &&
        !snapshot.isSeeking &&
        !snapshot.isBuffering &&
        snapshot.buffered > Duration.zero &&
        snapshot.duration - snapshot.buffered > const Duration(seconds: 2) &&
        snapshot.position - snapshot.buffered >
            const Duration(milliseconds: 500);
    if (!eligible ||
        previous == null ||
        previous.generation != snapshot.generation ||
        snapshot.position < previous.position ||
        snapshot.buffered != previous.buffered) {
      _since = null;
      return null;
    }
    final since = _since ??= now;
    if (now - since < const Duration(seconds: 1)) return null;
    return snapshot.buffered;
  }

  void reset() {
    _since = null;
    _last = null;
  }
}
