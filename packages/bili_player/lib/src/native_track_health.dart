import 'player_contract.dart';
import 'player_diagnostics.dart';

/// A common deadline for a missing track while its companion still advances.
/// Native buffering is only a valid reason to wait when both tracks stop.
final class NativeTrackHealth {
  static const maximumUnpairedPlayback = Duration(seconds: 2);
  static const sampleInterval = Duration(milliseconds: 250);
  // Reserve one interval for native observation and one for timer dispatch.
  // Starting a full 2s timeout after a sampled update would exceed the bound.
  static final detectionWindow = maximumUnpairedPlayback - sampleInterval * 2;
  final _audio = _Progress();
  final _video = _Progress();
  int? _generation;
  bool _heldTogether = false;

  ({PlayerFailureKind kind, PlaybackStallReason reason, Duration stalledFor})?
  update(
    PlaybackSnapshot snapshot,
    Duration now, {
    required bool requiresAudio,
    required bool requiresVideo,
    Duration? audioPosition,
    int? audioFrames,
    Duration? videoPosition,
    int? videoFrames,
    bool? videoStarved,
  }) {
    if (!snapshot.desiredPlaying ||
        snapshot.isSeeking ||
        !const {
          PlaybackPhase.playing,
          PlaybackPhase.buffering,
          PlaybackPhase.paused,
        }.contains(snapshot.phase)) {
      reset();
      return null;
    }
    if (_generation != snapshot.generation) {
      reset();
      _generation = snapshot.generation;
    }
    if (_heldTogether && !snapshot.isBuffering) {
      // Resume clocks and native replies arrive independently. Give the pair
      // a fresh window after an actual, synchronized refill wait.
      _audio.restart(now);
      _video.restart(now);
      _heldTogether = false;
    }
    _audio.observe(
      audioFrames ?? audioPosition?.inMicroseconds,
      now,
      tolerance: audioFrames == null ? 50000 : 0,
    );
    _video.observe(
      videoFrames ?? videoPosition?.inMicroseconds,
      now,
      tolerance: videoFrames == null ? 50000 : 0,
    );
    if (videoStarved != null) _video.availability(videoStarved, now);
    final audioAdvancing = _audio.recent(now);
    final videoAdvancing = _video.recent(now);
    if (_heldTogether && (audioAdvancing || videoAdvancing)) {
      _audio.restart(now);
      _video.restart(now);
      _heldTogether = false;
    }
    if (snapshot.isBuffering && !audioAdvancing && !videoAdvancing) {
      _heldTogether = true;
      return null;
    }
    if (snapshot.duration > Duration.zero &&
        snapshot.duration - snapshot.position <=
            const Duration(milliseconds: 500)) {
      return null;
    }
    if (requiresAudio &&
        _audio.stalled(now) &&
        (!requiresVideo || videoAdvancing)) {
      return (
        kind: PlayerFailureKind.nativePlayback,
        reason: audioFrames == null
            ? PlaybackStallReason.audioClock
            : PlaybackStallReason.audioFrames,
        stalledFor: now - _audio.progressAt!,
      );
    }
    if (requiresVideo &&
        _video.stalled(now) &&
        (!requiresAudio || audioAdvancing)) {
      return (
        kind: PlayerFailureKind.videoInterrupted,
        reason: videoStarved == true
            ? PlaybackStallReason.videoBuffer
            : PlaybackStallReason.videoClock,
        stalledFor: now - _video.stalledSince!,
      );
    }
    return null;
  }

  void reset() {
    _generation = null;
    _heldTogether = false;
    _audio.reset();
    _video.reset();
  }
}

final class _Progress {
  int? _highWater;
  Duration? progressAt;
  Duration? _starvedAt;
  bool? _starved;
  Duration? get stalledSince => _starved == true ? _starvedAt : progressAt;

  void observe(int? value, Duration now, {required int tolerance}) {
    if (value == null || value < 0) return;
    if (_highWater == null ||
        value - _highWater! > tolerance ||
        _highWater! - value > 1000000) {
      _highWater = value;
      progressAt = now;
    }
  }

  void availability(bool starved, Duration now) {
    _starved = starved;
    if (starved) {
      _starvedAt ??= now;
    } else {
      _starvedAt = null;
    }
  }

  bool recent(Duration now) =>
      _starved != true &&
      progressAt != null &&
      now - progressAt! <= NativeTrackHealth.sampleInterval * 2;
  bool stalled(Duration now) =>
      _starved != false &&
      stalledSince != null &&
      now - stalledSince! >= NativeTrackHealth.detectionWindow;
  void restart(Duration now) {
    if (progressAt != null) progressAt = now;
    if (_starvedAt != null) _starvedAt = now;
  }

  void reset() {
    _highWater = null;
    progressAt = null;
    _starvedAt = null;
    _starved = null;
  }
}
