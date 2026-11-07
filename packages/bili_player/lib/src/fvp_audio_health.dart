import 'native_playback_health.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';

/// MDK's video position and main demuxer do not prove external audio is alive.
/// Observe decoded audio activity, including silent PCM, without inspecting its
/// amplitude or sending high-frequency native callbacks to the UI isolate.
final class FvpAudioHealth {
  int? _generation;
  int? _frames;
  Duration? _progressAt;

  NativePlaybackInterruption? update(
    PlaybackSnapshot snapshot,
    Duration now,
    int frames,
  ) {
    if (_generation != snapshot.generation ||
        !snapshot.desiredPlaying ||
        snapshot.isSeeking ||
        snapshot.isBuffering ||
        snapshot.phase != PlaybackPhase.playing ||
        _frames == null ||
        frames != _frames) {
      _generation = snapshot.generation;
      _frames = frames;
      _progressAt = now;
      return null;
    }
    final stalledFor = now - (_progressAt ??= now);
    if (stalledFor < NativePlaybackHealth.stallTimeout ||
        snapshot.duration > Duration.zero &&
            snapshot.duration - snapshot.position <=
                const Duration(milliseconds: 500)) {
      return null;
    }
    return NativePlaybackInterruption(
      kind: PlayerFailureKind.nativePlayback,
      position: snapshot.position,
      reason: PlaybackStallReason.audioFrames,
      stalledFor: stalledFor,
    );
  }

  void reset() {
    _generation = null;
    _frames = null;
    _progressAt = null;
  }
}
