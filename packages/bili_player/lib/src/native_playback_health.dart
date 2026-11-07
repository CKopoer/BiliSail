import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'native_track_health.dart';

/// Playback position alone can be driven by just one surviving DASH track.
/// Sample both the main video buffer and the external audio clock. The native
/// cache handles ordinary underruns; this also catches premature per-track EOF
/// and buffering that never reports an error or another position event.
final class NativePlaybackHealth {
  static const stallTimeout = NativeTrackHealth.maximumUnpairedPlayback;
  static const bufferingTimeout = Duration(seconds: 30);
  static const sampleInterval = NativeTrackHealth.sampleInterval;
  final _tracks = NativeTrackHealth();

  PlaybackSnapshot? _last;
  Duration? _progressAt;
  Duration? _audioPosition;
  Duration? _positionHighWater;
  Duration? _resumeGraceAt;
  static const _progressTolerance = Duration(milliseconds: 50);

  NativePlaybackInterruption? update(
    PlaybackSnapshot snapshot,
    Duration now, {
    required bool paired,
    Duration? audioPosition,
    int? audioFrames,
    int? videoFrames,
    bool? videoStarved,
    bool requiresAudio = true,
    bool requiresVideo = true,
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
        previous.position - snapshot.position > const Duration(seconds: 1)) {
      _progressAt = now;
      _positionHighWater = snapshot.position;
      _resumeGraceAt = null;
      _tracks.reset();
      _audioPosition = audioPosition != null && audioPosition >= Duration.zero
          ? audioPosition
          : null;
      _tracks.update(
        snapshot,
        now,
        requiresAudio: requiresAudio,
        requiresVideo: requiresVideo,
        audioPosition: _audioPosition,
        audioFrames: audioFrames,
        videoPosition: videoFrames == null ? snapshot.position : null,
        videoFrames: videoFrames,
        videoStarved: videoStarved,
      );
      return null;
    }
    final trackStall =
        paired ||
            audioFrames != null ||
            videoFrames != null ||
            audioPosition != null ||
            videoStarved != null
        ? _tracks.update(
            snapshot,
            now,
            requiresAudio: requiresAudio,
            requiresVideo: requiresVideo,
            audioFrames: audioFrames,
            audioPosition: audioPosition ?? _audioPosition,
            videoPosition: videoFrames == null ? snapshot.position : null,
            videoFrames: videoFrames,
            videoStarved: videoStarved,
          )
        : null;
    if (trackStall != null) {
      return NativePlaybackInterruption(
        kind: trackStall.kind,
        reason: trackStall.reason,
        position: snapshot.position,
        stalledFor: trackStall.stalledFor,
        audioPosition: audioPosition ?? _audioPosition,
      );
    }
    // Cache endpoints and the sampled audio clock can trail the final position
    // at an underrun. While native playback is buffering, retain its paused
    // frame and let the bounded refill watchdog below decide when to recover.
    if (paired &&
        !snapshot.isBuffering &&
        snapshot.buffered > Duration.zero &&
        (snapshot.duration <= Duration.zero ||
            snapshot.duration - snapshot.buffered >
                const Duration(milliseconds: 500)) &&
        snapshot.position - snapshot.buffered >
            const Duration(milliseconds: 250)) {
      return NativePlaybackInterruption(
        kind: PlayerFailureKind.videoInterrupted,
        position: snapshot.buffered,
        reason: PlaybackStallReason.videoBuffer,
        audioPosition: _audioPosition,
      );
    }
    if (paired) {
      // mpv may make audio-pts unavailable once that track reaches EOF. Retain
      // its last clock so video progress cannot disguise the missing audio.
      if (audioPosition != null && audioPosition >= Duration.zero) {
        _audioPosition = audioPosition;
      }
      final audio = _audioPosition;
      // Cached native replies are up to one sample old. Scale that allowance
      // at high playback rates so healthy 4x/8x audio is not treated as EOF.
      final rateAllowance = snapshot.rate.isFinite && snapshot.rate > 1
          ? Duration(
              microseconds:
                  ((snapshot.rate - 1) * sampleInterval.inMicroseconds).round(),
            )
          : Duration.zero;
      if (!snapshot.isBuffering &&
          audio != null &&
          snapshot.position - audio >
              const Duration(milliseconds: 750) + rateAllowance &&
          (snapshot.duration <= Duration.zero ||
              snapshot.duration - snapshot.position >
                  const Duration(milliseconds: 500))) {
        return NativePlaybackInterruption(
          kind: PlayerFailureKind.nativePlayback,
          position: audio,
          reason: PlaybackStallReason.audioClock,
          audioPosition: _audioPosition,
        );
      }
    }
    if (snapshot.position - (_positionHighWater ?? snapshot.position) >
            _progressTolerance &&
        !snapshot.isBuffering) {
      _progressAt = now;
      _positionHighWater = snapshot.position;
      _resumeGraceAt = null;
    } else if (previous.isBuffering && !snapshot.isBuffering) {
      // One grace window per period without real progress. A flickering
      // buffering flag must not keep a frozen source alive indefinitely.
      _resumeGraceAt ??= now;
    }
    final progressAt = snapshot.isBuffering
        ? (_progressAt ??= now)
        : (_resumeGraceAt ?? (_progressAt ??= now));
    // Refilling a network cache is expected to stop the playback clock. Give
    // it a bounded recovery window, while still detecting a silent decoder
    // stall quickly. Buffer events alone never extend either deadline.
    final timeout = snapshot.isBuffering ? bufferingTimeout : stallTimeout;
    if (now - progressAt >= timeout) {
      return NativePlaybackInterruption(
        kind: PlayerFailureKind.nativePlayback,
        position: snapshot.position,
        reason: PlaybackStallReason.playbackClock,
        stalledFor: now - progressAt,
        audioPosition: _audioPosition,
      );
    }
    return null;
  }

  void reset() {
    _last = null;
    _progressAt = null;
    _audioPosition = null;
    _positionHighWater = null;
    _resumeGraceAt = null;
    _tracks.reset();
  }
}

final class NativePlaybackInterruption {
  const NativePlaybackInterruption({
    required this.kind,
    required this.position,
    required this.reason,
    this.stalledFor,
    this.audioPosition,
  });
  final PlayerFailureKind kind;
  final Duration position;
  final PlaybackStallReason reason;
  final Duration? stalledFor;
  final Duration? audioPosition;
}
