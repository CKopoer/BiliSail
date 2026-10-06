import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart' as mk;
import 'package:media_kit_video/media_kit_video.dart' as mkv;

import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'native_readiness.dart';
import 'native_error_monitor.dart';

/// Call at application startup before creating an engine.
void initializePlayerBackend() => mk.MediaKit.ensureInitialized();

/// Owns at most one native Player. Each source change replaces it, so events
/// retained by the previous backend cannot enter the next source generation.
final class MediaKitEngine implements PlayerEngine, VideoSurfaceSource {
  MediaKitEngine({this.onDiagnostic}) {
    _nativeErrors = NativeErrorMonitor(
      onStalled: (generation) => _fail(
        PlayerFailure(
          PlayerFailureKind.nativePlayback,
          '播放器报告异常后进度持续停滞，请重新加载或切换清晰度。',
          generation,
        ),
      ),
      onRecovered: (_) => _diagnose(PlayerDiagnosticKind.recovered),
    );
  }

  final void Function(PlayerDiagnosticEvent)? onDiagnostic;
  late final NativeErrorMonitor _nativeErrors;

  void _diagnose(
    PlayerDiagnosticKind kind, {
    NativeErrorSummary? nativeError,
    PlayerFailureKind? failureKind,
    NativeLogSeverity? severity,
  }) => onDiagnostic?.call(
    PlayerDiagnosticEvent(
      kind: kind,
      snapshot: _snapshot,
      nativeError: nativeError,
      failureKind: failureKind,
      severity: severity,
    ),
  );

  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  final _generationChanges = StreamController<int>.broadcast(sync: true);
  final ValueNotifier<mkv.VideoController?> _videoController = ValueNotifier(
    null,
  );
  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _commands = Future.value();
  mk.Player? _player;
  bool _disposed = false;
  bool _requiresDecodedAudio = false;
  int _generation = 0;
  PlaybackSnapshot _snapshot = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );

  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PlayerFailure> get failures => _failures.stream;
  @override
  PlaybackSnapshot get currentSnapshot => _snapshot;
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);

  /// Track IDs can be signed URLs; this reads only safe decoder parameters.
  PlayerDiagnostics inspectDiagnostics() {
    final state = _player?.state;
    final width = state?.videoParams.w ?? state?.width;
    final height = state?.videoParams.h ?? state?.height;
    final channels = state?.audioParams.channelCount;
    final sampleRate = state?.audioParams.sampleRate;
    String? safeCodec(String? value) =>
        value != null && RegExp(r'^[A-Za-z0-9._-]{1,32}$').hasMatch(value)
        ? value
        : null;
    String? videoCodec;
    String? audioCodec;
    if (state != null) {
      videoCodec = safeCodec(state.track.video.codec);
      for (final track in state.tracks.video) {
        if (track.id == state.track.video.id) {
          videoCodec ??= safeCodec(track.codec);
          break;
        }
      }
      for (final track in state.tracks.audio) {
        if (track.id == state.track.audio.id) {
          audioCodec = safeCodec(track.codec);
          break;
        }
      }
    }
    return PlayerDiagnostics(
      generation: _generation,
      position: state?.position ?? _snapshot.position,
      hasDecodedVideo:
          width != null && width > 0 && height != null && height > 0,
      hasDecodedAudio:
          channels != null &&
          channels > 0 &&
          sampleRate != null &&
          sampleRate > 0,
      videoWidth: width,
      videoHeight: height,
      audioChannels: channels,
      audioSampleRate: sampleRate,
      videoCodec: videoCodec,
      audioCodec: audioCodec,
    );
  }

  /// Actual native hardware decoder, e.g. d3d11va or "no" for software.
  /// Null means unavailable or superseded; no raw native strings are exposed.
  Future<String?> inspectHardwareDecoder() async {
    final player = _player;
    final platform = player?.platform;
    final generation = _generation;
    if (platform is! mk.NativePlayer || _disposed) return null;
    try {
      final value = await platform
          .getProperty('hwdec-current')
          .timeout(const Duration(seconds: 2));
      if (_disposed ||
          generation != _generation ||
          !identical(_player, player)) {
        return null;
      }
      return RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(value) ? value : null;
    } on Object {
      return null;
    }
  }

  void _publish(PlaybackSnapshot value) {
    if (_disposed || _snapshots.isClosed) return;
    _snapshot = value;
    _nativeErrors.update(value);
    _snapshots.add(value);
  }

  void _fail(PlayerFailure failure) {
    if (_disposed || _failures.isClosed || failure.generation != _generation) {
      return;
    }
    _diagnose(PlayerDiagnosticKind.failed, failureKind: failure.kind);
    _publish(
      _snapshot.copyWith(
        phase: PlaybackPhase.failed,
        isBuffering: false,
        isSeeking: false,
      ),
    );
    _failures.add(failure);
  }

  Future<void> _serial(Future<void> Function() operation) {
    final result = _commands.then((_) => operation());
    _commands = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _requireActive() {
    if (_disposed) {
      throw PlayerFailure(
        PlayerFailureKind.disposed,
        'Player is disposed.',
        _generation,
      );
    }
  }

  int _advanceGeneration() {
    _nativeErrors.reset();
    final value = ++_generation;
    if (!_generationChanges.isClosed) {
      _generationChanges.add(value);
    }
    return value;
  }

  Duration _remaining(Stopwatch watch, Duration budget) {
    final remaining = budget - watch.elapsed;
    if (remaining <= Duration.zero) {
      throw TimeoutException('Native source readiness deadline');
    }
    return remaining;
  }

  bool _hasRealTrack(List<mk.VideoTrack> tracks) =>
      tracks.any((track) => track.id != 'auto' && track.id != 'no');

  Set<String> _realAudioIds(mk.Player player) => player.state.tracks.audio
      .where((track) => track.id != 'auto' && track.id != 'no')
      .map((track) => track.id)
      .toSet();

  Future<void> _waitReady(
    mk.Player player,
    int generation,
    bool Function() ready,
    List<Stream<Object?>> changes,
    Duration timeout,
    String safeMessage,
  ) async {
    try {
      await waitForNativeState(
        ready: ready,
        superseded: () =>
            generation != _generation ||
            _disposed ||
            !identical(_player, player),
        changes: [...changes, _generationChanges.stream],
        timeout: timeout,
      );
    } on TimeoutException {
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        safeMessage,
        generation,
      );
    }
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    _requireActive();
    final generation = _advanceGeneration();
    _publish(
      PlaybackSnapshot(
        phase: PlaybackPhase.opening,
        generation: generation,
        desiredPlaying: options.play,
        rate: options.rate,
        volume: options.volume,
      ),
    );
    _diagnose(PlayerDiagnosticKind.openStarted);
    return _serial(() async {
      if (generation != _generation || _disposed) return;
      await _releasePlayer();
      if (generation != _generation || _disposed) return;
      try {
        final (mediaTrack, audioTrack) = _validate(source, options, generation);
        final watch = Stopwatch()..start();
        final openBudget = options.openTimeout;
        initializePlayerBackend();
        final player = mk.Player(
          configuration: const mk.PlayerConfiguration(
            logLevel: mk.MPVLogLevel.warn,
          ),
        );
        _player = player;
        _subscribe(player, generation);
        _videoController.value = mkv.VideoController(
          player,
          configuration: mkv.VideoControllerConfiguration(
            // Keep GPU rendering independent of software video decoding.
            // Null retains SDK platform defaults (including Android emulator).
            hwdec: options.videoDecoding == VideoDecodingMode.software
                ? 'no'
                : null,
          ),
        );
        await player
            .open(
              mk.Media(
                mediaTrack.uri.toString(),
                httpHeaders: mediaTrack.requestPolicy.headers,
              ),
              play: false,
            )
            .timeout(_remaining(watch, openBudget));
        if (generation != _generation || _disposed) return;
        if (source is DashPairSource || source is DashVideoSource) {
          // Player.open acknowledges loadlist before mpv has run the on_load
          // header hook and demuxed the video. The real track-list appears
          // only after that stage, and is the prerequisite for audio-add.
          await _waitReady(
            player,
            generation,
            () =>
                _hasRealTrack(player.state.tracks.video) ||
                ((player.state.videoParams.w ?? 0) > 0 &&
                    (player.state.videoParams.h ?? 0) > 0),
            [player.stream.tracks, player.stream.videoParams],
            _remaining(watch, openBudget),
            'Video track did not become ready.',
          );
        }
        if (generation != _generation || _disposed) return;
        if (audioTrack != null) {
          // media_kit's native implementation sets http-header-fields on the
          // same mpv instance for Media before audio-add. It has no per-audio
          // header parameter, so _validate requires identical header sets.
          final existingAudio = _realAudioIds(player);
          await player
              .setAudioTrack(mk.AudioTrack.uri(audioTrack.uri.toString()))
              .timeout(_remaining(watch, openBudget));
          await _waitReady(
            player,
            generation,
            () => _realAudioIds(player).difference(existingAudio).isNotEmpty,
            [player.stream.tracks],
            _remaining(watch, openBudget),
            'External audio track did not become ready.',
          );
          _requiresDecodedAudio = true;
        } else if (source is DashPairSource || source is DashVideoSource) {
          await player
              .setAudioTrack(mk.AudioTrack.no())
              .timeout(_remaining(watch, openBudget));
        }
        if (generation != _generation || _disposed) return;
        await player
            .setRate(options.rate)
            .timeout(_remaining(watch, openBudget));
        await player
            .setVolume(options.volume)
            .timeout(_remaining(watch, openBudget));
        if (options.startPosition > Duration.zero) {
          _publish(_snapshot.copyWith(isSeeking: true));
          await player
              .seek(options.startPosition)
              .timeout(_remaining(watch, openBudget));
          if (generation == _generation && !_disposed) {
            _publish(
              _snapshot.copyWith(
                position: player.state.position,
                isSeeking: false,
              ),
            );
          }
        }
        if (generation != _generation || _disposed) return;
        _publish(_snapshot.copyWith(phase: PlaybackPhase.ready));
        _diagnose(PlayerDiagnosticKind.openReady);
        if (options.play) {
          await player.play().timeout(_remaining(watch, openBudget));
          if (source is DashVideoSource) {
            await _waitReady(
              player,
              generation,
              () =>
                  (player.state.videoParams.w ?? 0) > 0 &&
                  (player.state.videoParams.h ?? 0) > 0,
              [player.stream.videoParams],
              _remaining(watch, openBudget),
              'Preview video did not decode.',
            );
          }
          if (_requiresDecodedAudio) {
            await _waitForDecodedAudio(
              player,
              generation,
              _remaining(watch, openBudget),
            );
          }
          if (generation == _generation && !_disposed) {
            _publish(_snapshot.copyWith(phase: PlaybackPhase.playing));
          }
        } else {
          await player.pause().timeout(_remaining(watch, openBudget));
          if (generation == _generation && !_disposed) {
            _publish(_snapshot.copyWith(phase: PlaybackPhase.paused));
          }
        }
      } on SourceSuperseded {
        await _releasePlayer();
      } on PlayerFailure catch (error) {
        _fail(error);
        await _releasePlayer();
        rethrow;
      } on Object {
        const message = 'Native player could not open this source.';
        final failure = PlayerFailure(
          PlayerFailureKind.nativePlayback,
          message,
          generation,
        );
        _fail(failure);
        await _releasePlayer();
        throw failure;
      }
    });
  }

  Future<void> _waitForDecodedAudio(
    mk.Player player,
    int generation,
    Duration timeout,
  ) => _waitReady(
    player,
    generation,
    () =>
        (player.state.audioParams.channelCount ?? 0) > 0 &&
        (player.state.audioParams.sampleRate ?? 0) > 0,
    [player.stream.audioParams],
    timeout,
    'External audio did not decode.',
  );

  (MediaTrack, MediaTrack?) _validate(
    ResolvedMediaSource source,
    OpenOptions options,
    int generation,
  ) {
    if (options.startPosition < Duration.zero ||
        !options.rate.isFinite ||
        options.rate <= 0 ||
        !options.volume.isFinite ||
        options.volume < 0 ||
        options.volume > 100 ||
        options.openTimeout <= Duration.zero) {
      throw PlayerFailure(
        PlayerFailureKind.invalidSource,
        'Invalid playback options.',
        generation,
      );
    }
    final MediaTrack media;
    MediaTrack? audio;
    switch (source) {
      case DashVideoSource(:final video):
        if (options.volume != 0) {
          throw PlayerFailure(
            PlayerFailureKind.invalidSource,
            'Video-only DASH requires a muted preview.',
            generation,
          );
        }
        return (_validateTrack(video, generation), null);
      case ProgressiveSource(:final media):
        return (_validateTrack(media, generation), null);
      case ManifestSource(:final media):
        return (_validateTrack(media, generation), null);
      case DashPairSource(
        video: final video,
        audio: final selectedAudio,
        isIntentionallySilent: final silent,
      ):
        media = _validateTrack(video, generation);
        if (selectedAudio == null && !silent) {
          throw PlayerFailure(
            PlayerFailureKind.invalidSource,
            'DASH audio track is missing.',
            generation,
          );
        }
        audio = selectedAudio == null
            ? null
            : _validateTrack(selectedAudio, generation);
        if (audio != null &&
            !_sameHeaders(
              media.requestPolicy.headers,
              audio.requestPolicy.headers,
            )) {
          throw PlayerFailure(
            PlayerFailureKind.unsupportedHeaders,
            'DASH tracks require different request headers.',
            generation,
          );
        }
        return (media, audio);
    }
  }

  MediaTrack _validateTrack(MediaTrack track, int generation) {
    if (!{'http', 'https', 'file'}.contains(track.uri.scheme) ||
        track.uri.host.isEmpty && track.uri.scheme != 'file') {
      throw PlayerFailure(
        PlayerFailureKind.invalidSource,
        'Unsupported media URI.',
        generation,
      );
    }
    for (final entry in track.requestPolicy.headers.entries) {
      final name = entry.key.toLowerCase();
      if (!{'user-agent', 'referer', 'origin', 'accept'}.contains(name) ||
          entry.key.contains('\r') ||
          entry.key.contains('\n') ||
          entry.value.contains('\r') ||
          entry.value.contains('\n')) {
        throw PlayerFailure(
          PlayerFailureKind.unsupportedHeaders,
          'Unsupported media request header.',
          generation,
        );
      }
    }
    return track;
  }

  bool _sameHeaders(Map<String, String> left, Map<String, String> right) {
    Map<String, String> normalize(Map<String, String> value) => {
      for (final entry in value.entries) entry.key.toLowerCase(): entry.value,
    };
    final a = normalize(left);
    final b = normalize(right);
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  void _subscribe(mk.Player player, int generation) {
    bool active() =>
        !_disposed && generation == _generation && identical(_player, player);
    bool canChangePhase() =>
        active() && _snapshot.phase != PlaybackPhase.failed;
    _subscriptions.add(
      player.stream.position.listen((value) {
        if (active()) _publish(_snapshot.copyWith(position: value));
      }),
    );
    _subscriptions.add(
      player.stream.duration.listen((value) {
        if (active()) _publish(_snapshot.copyWith(duration: value));
      }),
    );
    _subscriptions.add(
      player.stream.buffer.listen((value) {
        if (active()) _publish(_snapshot.copyWith(buffered: value));
      }),
    );
    _subscriptions.add(
      player.stream.buffering.listen((value) {
        if (!canChangePhase() || _snapshot.phase == PlaybackPhase.opening) {
          return;
        }
        _publish(
          _snapshot.copyWith(
            isBuffering: value,
            phase: value
                ? PlaybackPhase.buffering
                : (_snapshot.desiredPlaying
                      ? PlaybackPhase.playing
                      : PlaybackPhase.paused),
          ),
        );
      }),
    );
    _subscriptions.add(
      player.stream.playing.listen((value) {
        if (!canChangePhase() || _snapshot.phase == PlaybackPhase.opening) {
          return;
        }
        _publish(
          _snapshot.copyWith(
            phase: value ? PlaybackPhase.playing : PlaybackPhase.paused,
          ),
        );
      }),
    );
    _subscriptions.add(
      player.stream.completed.listen((value) {
        if (canChangePhase() && value) {
          _publish(
            _snapshot.copyWith(
              phase: PlaybackPhase.ended,
              desiredPlaying: false,
            ),
          );
        }
      }),
    );
    _subscriptions.add(
      player.stream.log.listen((log) {
        final severity = switch (log.level) {
          'warn' => NativeLogSeverity.warning,
          'error' => NativeLogSeverity.error,
          'fatal' => NativeLogSeverity.fatal,
          _ => null,
        };
        if (active() && severity != null) {
          _diagnose(
            PlayerDiagnosticKind.nativeLog,
            severity: severity,
            nativeError: NativeErrorSummary.classify(
              log.text,
              prefix: log.prefix,
            ),
          );
        }
      }),
    );
    _subscriptions.add(
      player.stream.error.listen((message) {
        if (active()) {
          _diagnose(
            PlayerDiagnosticKind.nativeError,
            nativeError: NativeErrorSummary.classify(message),
          );
          _nativeErrors.report(_snapshot);
        }
      }),
    );
  }

  Future<void> _releasePlayer() async {
    _nativeErrors.reset();
    _requiresDecodedAudio = false;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _videoController.value = null;
    final old = _player;
    _player = null;
    if (old != null) await old.dispose();
  }

  Future<void> _command(
    Future<void> Function(mk.Player) operation, {
    PlaybackSnapshot Function(PlaybackSnapshot)? optimistic,
  }) {
    _requireActive();
    final generation = _generation;
    return _serial(() async {
      if (generation != _generation || _disposed) return;
      final player = _player;
      if (player == null) return;
      if (optimistic != null) _publish(optimistic(_snapshot));
      try {
        await operation(player).timeout(const Duration(seconds: 15));
      } on SourceSuperseded {
        return;
      } on Object {
        if (generation != _generation || _disposed) return;
        final failure = PlayerFailure(
          PlayerFailureKind.nativePlayback,
          'Native playback command failed.',
          generation,
        );
        _fail(failure);
        throw failure;
      }
    });
  }

  @override
  Future<void> play() {
    final generation = _generation;
    return _command((player) async {
      await player.play();
      if (_requiresDecodedAudio) {
        try {
          await _waitForDecodedAudio(
            player,
            generation,
            const Duration(seconds: 12),
          );
        } on PlayerFailure {
          // A video-only result is not a successful DASH playback session.
          await player.pause();
          rethrow;
        }
      }
    }, optimistic: (s) => s.copyWith(desiredPlaying: true));
  }

  @override
  Future<void> pause() => _command(
    (player) => player.pause(),
    optimistic: (s) => s.copyWith(desiredPlaying: false),
  );
  @override
  Future<void> seek(Duration target) {
    if (target < Duration.zero) throw ArgumentError.value(target, 'target');
    return _command((player) async {
      await player.seek(target);
      if (!_disposed) {
        _publish(
          _snapshot.copyWith(position: player.state.position, isSeeking: false),
        );
      }
    }, optimistic: (s) => s.copyWith(isSeeking: true));
  }

  @override
  Future<void> setRate(double rate) {
    if (!rate.isFinite || rate <= 0) throw ArgumentError.value(rate, 'rate');
    return _command(
      (player) => player.setRate(rate),
      optimistic: (s) => s.copyWith(rate: rate),
    );
  }

  @override
  Future<void> setVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 100) {
      throw ArgumentError.value(volume, 'volume');
    }
    return _command(
      (player) => player.setVolume(volume),
      optimistic: (s) => s.copyWith(volume: volume),
    );
  }

  @override
  Future<void> stop() {
    _requireActive();
    final generation = _advanceGeneration();
    _publish(
      PlaybackSnapshot(phase: PlaybackPhase.idle, generation: generation),
    );
    return _serial(_releasePlayer);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _advanceGeneration();
    await _serial(_releasePlayer);
    _disposed = true;
    _videoController.dispose();
    await _snapshots.close();
    await _failures.close();
    await _generationChanges.close();
  }

  @override
  Widget buildVideoSurface() => ValueListenableBuilder<mkv.VideoController?>(
    valueListenable: _videoController,
    builder: (context, controller, _) => controller == null
        ? const ColoredBox(color: Color(0xFF000000))
        : mkv.Video(controller: controller, controls: mkv.NoVideoControls),
  );
}
