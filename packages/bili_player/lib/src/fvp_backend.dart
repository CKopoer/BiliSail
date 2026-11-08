import 'dart:async';

import 'android_fvp_player.dart';
import 'android_media_leases.dart';
import 'fvp_native_player.dart';
import 'fvp_video_output.dart';
import 'playback_backend.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'validated_source.dart';
import 'video_output.dart';

/// MDK commands and observations, shared by the local and Android IPC ports.
final class FvpBackend implements PlaybackBackend {
  FvpBackend({
    required this.createPlayer,
    required this.isolated,
    this.onStage,
  });
  final Future<FvpPlayerPort> Function() createPlayer;
  final bool isolated;
  final void Function(NativeReadinessStage)? onStage;
  final _output = FvpVideoOutput();
  final _leases = AndroidMediaLeases();
  final _events = StreamController<BackendEvent>.broadcast(sync: true);
  Future<FvpPlayerPort>? _creating;
  FvpPlayerPort? _player;
  StreamSubscription<FvpNativeStatus>? _subscription;
  Future<void>? _disposal;
  PlaybackOperation? _preparation;
  bool _disposed = false;
  bool _nativeEnded = false;
  double _volume = 0, _gain = 0;
  int? get processExitStatus => switch (_player) {
    final AndroidFvpPlayer player => player.exitStatus,
    _ => null,
  };

  @override
  VideoOutput get videoOutput => _output;
  @override
  Stream<BackendEvent> get events => _events.stream;
  @override
  Duration get seekTimeout => const Duration(seconds: 15);

  @override
  Future<PreparedTracks> preparePaused(
    ValidatedSource plan,
    PlaybackOperation operation,
  ) async {
    _preparation = operation;
    Future<MediaTrack> lease(MediaTrack track) async {
      if (isolated) return track;
      final opened = await _leases.open(track);
      if (operation.isCancelled || _disposed) {
        await _leases.close();
        operation.check();
      }
      return opened;
    }

    try {
      final main = await operation.wait(lease(plan.media));
      final sound = plan.audio == null
          ? null
          : await operation.wait(lease(plan.audio!));
      final creating = _creating = createPlayer().then((player) {
        _player = player;
        return player;
      });
      final player = await operation.wait(creating);
      _creating = null;
      _subscription = player.statuses.listen((status) {
        if (_disposed) return;
        if (status == FvpNativeStatus.ended) _nativeEnded = true;
        _events.add(switch (status) {
          FvpNativeStatus.buffering => const BackendEvent(
            BackendEventKind.buffering,
            value: true,
          ),
          FvpNativeStatus.buffered => const BackendEvent(
            BackendEventKind.buffering,
            value: false,
          ),
          FvpNativeStatus.ended => BackendEvent(
            BackendEventKind.ended,
            position: Duration(milliseconds: player.positionMilliseconds),
          ),
          FvpNativeStatus.invalid => const BackendEvent(
            BackendEventKind.failure,
          ),
          FvpNativeStatus.audioEnded => const BackendEvent(
            BackendEventKind.failure,
            stallReason: PlaybackStallReason.audioClock,
          ),
          FvpNativeStatus.processExited => const BackendEvent(
            BackendEventKind.failure,
            failureKind: PlayerFailureKind.nativeProcessExited,
          ),
        });
      });
      onStage?.call(NativeReadinessStage.tracks);
      operation.check();
      final info = await operation.wait(
        player.prepare(
          main,
          sound,
          plan.options,
          silent: plan.silent,
          isLive: plan.live,
        ),
      );
      _gain = plan.options.audioGainDb;
      _dimensions = info.dimensions;
      await operation.wait(setVolume(plan.options.volume));
      return PreparedTracks(
        hasVideo: info.hasVideo,
        hasAudio: info.hasAudio,
        externalAudioSelected: sound != null && info.hasAudio,
        duration: info.duration,
        position: plan.options.startPosition,
        dimensions: info.dimensions,
      );
    } on FvpProcessException {
      throw PlayerFailure(
        PlayerFailureKind.nativeProcessExited,
        '播放器异常退出，请退出播放页后重新打开',
        operation.generation,
      );
    }
  }

  @override
  Future<VideoDimensions?> confirmVideo(PlaybackOperation operation) async {
    final player = _player!;
    onStage?.call(NativeReadinessStage.videoOutput);
    operation.check();
    final texture = await operation.wait(player.createTexture());
    if (texture < 0) throw StateError('Video output unavailable');
    // The prepared scalar dimensions are owned by the player, not the probe.
    final dimensions = _dimensions;
    if (dimensions == null) throw StateError('Video did not decode');
    _output.bind(texture, dimensions);
    onStage?.call(NativeReadinessStage.videoDecode);
    operation.check();
    if (!await operation.wait(player.confirmVideoFrame())) {
      throw StateError('Video did not render');
    }
    return dimensions;
  }

  VideoDimensions? _dimensions;

  @override
  Future<void> confirmAudio(PlaybackOperation operation) async {
    onStage?.call(NativeReadinessStage.externalAudio);
    operation.check();
    if (!await operation.wait(_player!.confirmAudio())) {
      throw StateError('Audio did not decode');
    }
  }

  @override
  Future<void> confirmPresentation(PlaybackOperation operation) =>
      operation.wait(_output.confirmFrame());
  @override
  Future<void> play() async {
    final player = _player!;
    if (player is FvpCommandCompletionPort) {
      await (player as FvpCommandCompletionPort).playAndWait();
    } else {
      player.play();
    }
  }

  @override
  Future<bool> pauseAndWait() async {
    final player = _player;
    if (player is FvpPauseConfirmationPort) {
      return (player as FvpPauseConfirmationPort).pauseAndConfirm();
    }
    await player?.pauseAndWait();
    // MDK keeps EOF stopped for replay; its pause request cannot acknowledge
    // that a surviving external audio pipe has stopped too.
    return !_nativeEnded;
  }

  @override
  Future<void> setRate(double rate) async {
    final player = _player!;
    if (player is FvpCommandCompletionPort) {
      await (player as FvpCommandCompletionPort).setRateAndWait(rate);
    } else {
      player.setRate(rate);
    }
  }

  Future<void> _applyVolume() async {
    final player = _player!;
    if (player is FvpCommandCompletionPort) {
      await (player as FvpCommandCompletionPort).setVolumeAndWait(
        _volume,
        _gain,
      );
    } else {
      player.setVolume(_volume, _gain);
    }
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume;
    await _applyVolume();
  }

  @override
  Future<void> setGainDb(double gainDb) async {
    _gain = gainDb;
    await _applyVolume();
  }

  @override
  Future<Duration> seekTo(Duration target, PlaybackOperation operation) async {
    try {
      final position = await operation.wait(_player!.seek(target));
      if (position < 0) throw NativeSeekFailure(position);
      _nativeEnded = false;
      return Duration(milliseconds: position);
    } on FvpProcessException {
      throw PlayerFailure(
        PlayerFailureKind.nativeProcessExited,
        '播放器异常退出，请退出播放页后重新打开',
        operation.generation,
      );
    }
  }

  @override
  Future<void> cancelSeek() async => await _player?.cancelSeek();
  @override
  void interrupt() {
    _preparation?.cancel();
    _player?.interrupt();
  }

  @override
  BackendHealth sampleHealth() {
    final player = _player;
    if (player == null) return const BackendHealth();
    final position = Duration(
      milliseconds: player.positionMilliseconds.clamp(0, 1 << 53),
    );
    final audioPosition = player is FvpAudioClockPort
        ? (player as FvpAudioClockPort).audioPositionMilliseconds
        : null;
    return BackendHealth(
      position: position,
      buffered:
          position +
          Duration(milliseconds: player.bufferedMilliseconds.clamp(0, 1 << 53)),
      audioPosition: audioPosition == null
          ? null
          : Duration(milliseconds: audioPosition),
      audioFrames: player is FvpAudioClockPort
          ? null
          : player is FvpAudioActivityPort
          ? (player as FvpAudioActivityPort).decodedAudioFrames
          : null,
    );
  }

  @override
  void resetHealth() {}
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation(
    int generation,
  ) async {
    final player = _player;
    if (player is FvpInformationPort) {
      return (player as FvpInformationPort).inspectPlaybackInformation(
        generation: generation,
        audioGainDb: _gain,
      );
    }
    return PlayerPlaybackInformation(
      generation: generation,
      backend: 'fvp / MDK',
      audioGainDb: _gain,
    );
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    interrupt();
    _disposed = true;
    _output.clear();
    await _subscription?.cancel();
    final creating = _creating;
    if (creating != null) {
      try {
        await creating;
      } on Object {
        /* No native resource was returned. */
      }
    }
    if (_player case final player?) {
      await player.dispose().timeout(const Duration(seconds: 10));
    }
    _player = null;
    await _leases.close();
    _output.dispose();
    await _events.close();
  }
}
