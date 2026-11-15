import 'dart:async';

import 'player_contract.dart';
import 'player_diagnostics.dart';

enum NativeBufferRecoveryReason {
  readError,
  stalledRead,
  audioError,
  videoError,
  decoderError,
}

typedef NativeRecoveryProgress = ({Duration? audio, Duration? video});

/// Sample only during a pending fault. mpv's time-pos follows the video clock
/// while video is active, but falls back to audio when video disappears. Require
/// an active video format (and A/V sync when both tracks are expected) as well.
Future<NativeRecoveryProgress> nativeRecoveryProgress(
  Future<String?> Function(String) read, {
  required bool audio,
  required bool video,
}) async {
  Future<String?> property(String name) async {
    try {
      return await read(name).timeout(const Duration(milliseconds: 400));
    } on Object {
      return null;
    }
  }

  final values = await Future.wait([
    if (audio) property('audio-pts'),
    if (video) property('time-pos'),
    if (video) property('video-format'),
    if (audio && video) property('avsync'),
  ]);
  Duration? clock(String? text) {
    final value = double.tryParse(text ?? '');
    return value != null && value.isFinite && value.abs() < 1e10
        ? Duration(
            microseconds: (value * Duration.microsecondsPerSecond).round(),
          )
        : null;
  }

  final videoIndex = audio ? 1 : 0;
  final format = video ? values[videoIndex + 1] : null;
  final videoActive =
      video &&
      format != null &&
      !const {'', 'no', 'none'}.contains(format) &&
      (!audio || double.tryParse(values.last ?? '')?.isFinite == true);
  return (
    audio: audio ? clock(values.first) : null,
    video: videoActive ? clock(values[videoIndex]) : null,
  );
}

/// One bounded native grace window for read stalls and decoder/output faults.
/// Cached playback is preserved until half the window or a real track stall.
final class NativeBufferRecovery {
  NativeBufferRecovery({
    required this.snapshot,
    required this.onRecoveryRequired,
    this.playbackProgress,
    this.onNativeRecovered,
    this.hasAudio = true,
    this.hasVideo = true,
    this.watchReadStalls = true,
  });

  static const retryInterval = Duration(seconds: 5);
  static const resumedReadGrowth = Duration(seconds: 1);
  static const progressInterval = Duration(milliseconds: 500);
  static const stalledTrackTimeout = Duration(seconds: 2);
  final PlaybackSnapshot Function() snapshot;
  final void Function(NativeBufferRecoveryReason) onRecoveryRequired;
  final Future<NativeRecoveryProgress> Function()? playbackProgress;
  final void Function()? onNativeRecovered;
  final bool hasAudio, hasVideo, watchReadStalls;
  Timer? _readDeadline, _nativeRetry, _progressTimer;
  Timer? _audioDeadline, _videoDeadline;
  Object? _nativeEpisode;
  NativeBufferRecoveryReason? _reason;
  int? _nativeGeneration;
  NativeRecoveryProgress _progress = (audio: null, video: null);
  Duration _nativeBuffered = Duration.zero;
  Duration _nativeRecoveryPosition = Duration.zero;
  Duration _buffered = Duration.zero;
  bool _disposed = false, _reading = false;
  bool _recoveryRequested = false;

  void readingChanged(bool reading, {bool endOfInput = false}) {
    if (!watchReadStalls) return;
    _reading = reading && !endOfInput;
    // Input EOF also means normal prefetch completion. DASH tracks can end at
    // different timestamps; the estimated cache endpoint cannot prove a read
    // failure. Let native playback consume the cache and report real errors or
    // premature playback completion through the existing engine event route.
    // Once the reader becomes idle, a pending silent-read probe is stale too.
    // A reachable origin cannot turn normal cache backpressure into a failure.
    if (!_reading &&
        (_nativeEpisode == null ||
            _reason == NativeBufferRecoveryReason.stalledRead)) {
      cancel();
    }
    update();
  }

  bool get _active {
    final value = snapshot();
    return !_disposed &&
        !_recoveryRequested &&
        value.desiredPlaying &&
        !value.isSeeking &&
        const {
          PlaybackPhase.playing,
          PlaybackPhase.buffering,
        }.contains(value.phase);
  }

  bool get _eligible =>
      _active &&
      (snapshot().duration == Duration.zero ||
          snapshot().duration - snapshot().buffered >
              const Duration(milliseconds: 500)) &&
      // A blocked native read can delay its cache-time notification even
      // while queued packets keep playing. Do not require that notification
      // to detect the read stall. Empty, already-buffering playback keeps its
      // existing normal underrun recovery path.
      (snapshot().phase == PlaybackPhase.playing ||
          snapshot().buffered - snapshot().position >
              const Duration(seconds: 1));

  void reportError(NativeErrorSummary error, {bool decoderErrors = false}) {
    // Both SDK log/error streams use this policy. A new cause must explicitly
    // choose whether it proves a media read failure, even while cache plays.
    final readFailure = switch (error.cause) {
      NativeErrorCause.http ||
      NativeErrorCause.timeout ||
      NativeErrorCause.connection ||
      NativeErrorCause.tls ||
      NativeErrorCause.inputOutput => true,
      NativeErrorCause.hardwareDecoder ||
      NativeErrorCause.videoOutput ||
      NativeErrorCause.decoder ||
      NativeErrorCause.missingFile ||
      NativeErrorCause.openFailed ||
      NativeErrorCause.unsupportedProperty ||
      NativeErrorCause.unknown => false,
    };
    if (readFailure) {
      reportNetworkError(confirmed: true);
    } else if (decoderErrors &&
        const {
          NativeErrorCause.decoder,
          NativeErrorCause.hardwareDecoder,
          NativeErrorCause.videoOutput,
        }.contains(error.cause)) {
      // The SDK error stream can omit the original component. Preserve that
      // uncertainty instead of letting the shared clock clear a real fault.
      reportDecoderError(switch (error.component) {
        'ad' || 'ffmpeg/audio' => NativeBufferRecoveryReason.audioError,
        'vd' || 'ffmpeg/video' || 'vo' => NativeBufferRecoveryReason.videoError,
        _ => NativeBufferRecoveryReason.decoderError,
      });
    }
  }

  void reportNetworkError({bool confirmed = false}) {
    if (confirmed) {
      if (!_active ||
          (snapshot().duration > Duration.zero &&
              snapshot().duration - snapshot().buffered <=
                  const Duration(milliseconds: 500))) {
        return;
      }
      _waitForNative(NativeBufferRecoveryReason.readError);
      return;
    }
    if (_eligible) _waitForNative(NativeBufferRecoveryReason.stalledRead);
  }

  void reportDecoderError(NativeBufferRecoveryReason reason) {
    assert(
      reason == NativeBufferRecoveryReason.audioError ||
          reason == NativeBufferRecoveryReason.videoError ||
          reason == NativeBufferRecoveryReason.decoderError,
    );
    _waitForNative(reason);
  }

  void _waitForNative(NativeBufferRecoveryReason reason) {
    if (!_active) return;
    if (_nativeEpisode != null) {
      // Decoder faults cannot be cleared by input cache growth. Preserve the
      // original window even when a second kind of fault arrives.
      if (reason == NativeBufferRecoveryReason.audioError ||
          reason == NativeBufferRecoveryReason.videoError ||
          (reason == NativeBufferRecoveryReason.decoderError && _readFault)) {
        _reason = reason;
      }
      return;
    }
    final value = snapshot();
    final halfWindow = (value.buffered - value.position) ~/ 2;
    if (value.phase != PlaybackPhase.playing ||
        value.isBuffering ||
        !value.rate.isFinite ||
        value.rate <= 0 ||
        halfWindow <= Duration.zero) {
      _requestRecovery(reason);
      return;
    }
    // mpv/FFmpeg can reconnect the same HTTP reader without losing packets.
    // Do not let its first error log retire a still-playing native pair.
    // Use half of the actual native window, already limited by time/bytes.
    // Repeated errors never extend this window; speed-ups also reach the
    // media midpoint sooner, leaving the other half available for fallback.
    cancel();
    final episode = _nativeEpisode = Object();
    _reason = reason;
    _nativeGeneration = value.generation;
    _progress = (audio: null, video: null);
    _nativeBuffered = value.buffered;
    _nativeRecoveryPosition = value.position + halfWindow;
    _nativeRetry = Timer(
      Duration(microseconds: (halfWindow.inMicroseconds / value.rate).floor()),
      () {
        update();
        if (identical(_nativeEpisode, episode)) {
          _requestRecovery(_reason!);
        }
      },
    );
    if (playbackProgress != null) {
      if (hasAudio) _audioDeadline = Timer(stalledTrackTimeout, _trackStalled);
      if (hasVideo) _videoDeadline = Timer(stalledTrackTimeout, _trackStalled);
      unawaited(_sampleProgress(episode));
    }
  }

  void _trackStalled() {
    update();
    if (_nativeEpisode != null) _requestRecovery(_reason!);
  }

  Future<void> _sampleProgress(Object episode) async {
    if (!identical(_nativeEpisode, episode)) return;
    try {
      NativeRecoveryProgress progress;
      try {
        progress = await playbackProgress!().timeout(
          const Duration(seconds: 1),
        );
      } on Object {
        progress = (audio: null, video: null);
      }
      if (!identical(_nativeEpisode, episode)) return;
      final tracksAdvancing =
          (!hasAudio ||
              (progress.audio != null &&
                  _progress.audio != null &&
                  progress.audio! > _progress.audio!)) &&
          (!hasVideo ||
              (progress.video != null &&
                  _progress.video != null &&
                  progress.video! > _progress.video!));
      if (progress.audio case final audio?) {
        if (_progress.audio == null || audio > _progress.audio!) {
          _audioDeadline?.cancel();
          if (hasAudio) {
            _audioDeadline = Timer(stalledTrackTimeout, _trackStalled);
          }
        }
      }
      if (progress.video case final video?) {
        if (_progress.video == null || video > _progress.video!) {
          _videoDeadline?.cancel();
          if (hasVideo) {
            _videoDeadline = Timer(stalledTrackTimeout, _trackStalled);
          }
        }
      }
      _progress = progress;
      update();
      if (identical(_nativeEpisode, episode) &&
          _readFault &&
          tracksAdvancing &&
          snapshot().buffered >= _nativeBuffered + resumedReadGrowth) {
        _buffered = snapshot().buffered;
        cancel();
      }
    } finally {
      if (identical(_nativeEpisode, episode)) {
        _progressTimer = Timer(
          progressInterval,
          () => unawaited(_sampleProgress(episode)),
        );
      }
    }
  }

  bool get _readFault =>
      _reason == NativeBufferRecoveryReason.readError ||
      _reason == NativeBufferRecoveryReason.stalledRead;

  void update() {
    if (_disposed) return;
    final buffered = snapshot().buffered;
    if (_nativeEpisode != null) {
      if (!_active || snapshot().generation != _nativeGeneration) {
        cancel();
      } else if (snapshot().isBuffering ||
          snapshot().position >= _nativeRecoveryPosition) {
        _requestRecovery(_reason!);
        return;
      }
    }
    if (_nativeEpisode != null) {
      // Input growth proves HTTP recovery, never decoder/output recovery.
      if (_readFault &&
          buffered >= _nativeBuffered + resumedReadGrowth &&
          playbackProgress == null) {
        _buffered = buffered;
        cancel();
      } else {
        return;
      }
    }
    // Cache growth restarts read-stall detection. Consuming existing packets
    // does not. A backward seek changes the baseline and cancels old timers.
    if (buffered > _buffered + const Duration(milliseconds: 50)) {
      _buffered = buffered;
      cancel();
    } else if (buffered < _buffered - const Duration(milliseconds: 50)) {
      // Seeking or native cache eviction can move the endpoint backwards.
      // Later growth must be compared to this range, not a retired high-water
      // mark.
      _buffered = buffered;
      cancel();
    } else if (!_eligible) {
      cancel();
    }
    // Native idle distinguishes a full packet cache from a blocked read. This
    // arrives through SDK property events, not periodic native clock polling.
    if (!_reading || !_eligible) {
      _readDeadline?.cancel();
      _readDeadline = null;
    } else {
      _readDeadline ??= Timer(retryInterval, () {
        _readDeadline = null;
        reportNetworkError();
      });
    }
  }

  void _requestRecovery(NativeBufferRecoveryReason reason) {
    _recoveryRequested = true;
    cancel();
    onRecoveryRequired(reason);
  }

  void cancel() {
    final hadNativeEpisode = _nativeEpisode != null;
    _nativeEpisode = null;
    _nativeRetry?.cancel();
    _nativeRetry = null;
    _reason = null;
    _nativeGeneration = null;
    _progressTimer?.cancel();
    _audioDeadline?.cancel();
    _videoDeadline?.cancel();
    _readDeadline?.cancel();
    _readDeadline = null;
    if (hadNativeEpisode) onNativeRecovered?.call();
  }

  void dispose() {
    _disposed = true;
    cancel();
  }
}
