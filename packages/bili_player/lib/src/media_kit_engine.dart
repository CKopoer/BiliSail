import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart' as mk;

import 'player_contract.dart';
import 'android_media_leases.dart';
import 'player_diagnostics.dart';
import 'native_readiness.dart';
import 'native_media_options.dart';
import 'native_error_monitor.dart';
import 'dash_video_continuity.dart';
import 'native_load_observer.dart';
import 'native_audio_gain.dart';
import 'native_video_frame_queue.dart';
import 'video_dimensions.dart';
import 'media_kit_video_output.dart';
import 'video_output.dart';

/// Call at application startup before creating an engine.
void initializePlayerBackend() => mk.MediaKit.ensureInitialized();

/// Owns at most one native Player. Each source change replaces it, so events
/// retained by the previous backend cannot enter the next source generation.
final class MediaKitEngine
    implements PlayerEngine, VideoOutputSource, AudioGainControl {
  MediaKitEngine({this.onDiagnostic, bool? experimentalVideoFrameQueue})
    : experimentalVideoFrameQueue = resolveVideoFrameQueueEnabled(
        isAndroid: Platform.isAndroid,
        enabledOverride: experimentalVideoFrameQueue,
      ) {
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
  final _mediaLeases = AndroidMediaLeases();

  /// DASH frame queue, Android-on / desktop-off unless explicitly overridden.
  /// Keeps the selected decoder; hardware-decoder compatibility is experimental.
  final bool experimentalVideoFrameQueue;
  bool _videoFrameQueueActive = false;

  /// True only after the native queue properties have been read back successfully.
  /// This reports configuration, not the number of frames currently buffered.
  bool get videoFrameQueueActive => _videoFrameQueueActive;
  late final NativeErrorMonitor _nativeErrors;
  final _dashContinuity = DashVideoContinuity();
  final _continuityClock = Stopwatch()..start();
  bool _watchDashContinuity = false;
  bool _dashInterruptionPending = false;
  NativeLoadObserver? _nativeLoad;

  void _diagnose(
    PlayerDiagnosticKind kind, {
    NativeErrorSummary? nativeError,
    PlayerFailureKind? failureKind,
    NativeLogSeverity? severity,
    int? nativeErrorCode,
  }) => onDiagnostic?.call(
    PlayerDiagnosticEvent(
      kind: kind,
      snapshot: _snapshot,
      nativeError: nativeError,
      failureKind: failureKind,
      severity: severity,
      nativeErrorCode: nativeErrorCode,
      readinessStage: _readinessStage,
      // openStarted precedes releasing the previous native player.
      diagnostics: kind == PlayerDiagnosticKind.openStarted
          ? null
          : inspectDiagnostics(),
    ),
  );

  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  final _generationChanges = StreamController<int>.broadcast(sync: true);
  final MediaKitVideoOutput _videoOutput = MediaKitVideoOutput();

  @override
  VideoOutput get videoOutput => _videoOutput;

  /// The current Windows output cap, independently of media decoding size.
  ({int? width, int? height})? get debugRequestedVideoViewport =>
      _videoOutput.debugRequestedViewport;

  final List<StreamSubscription<Object?>> _subscriptions = [];
  Future<void> _commands = Future.value();
  mk.Player? _player;
  NativeAudioGain? _audioGain;

  /// Last verified native normalization gain, for playback diagnostics.
  double get appliedAudioGainDb => _audioGain?.gainDb ?? 0;
  bool _disposed = false;
  bool _requiresDecodedAudio = false;
  NativeReadinessStage? _readinessStage;
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
    final output = _videoOutput;
    final outputRect = output.dimensions;
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
      hasVideoOutput: output.hasVideoOutput,
      outputWidth: outputRect?.width.toInt(),
      outputHeight: outputRect?.height.toInt(),
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

  /// Native clock and drop counters for bounded playback validation probes.
  /// Values are absent when mpv has not established both streams yet.
  Future<({double? avsyncSeconds, int? frameDrops, int? decoderDrops})>
  inspectNativePlaybackTiming() async {
    final player = _player;
    final platform = player?.platform;
    final generation = _generation;
    if (platform is! mk.NativePlayer || _disposed) {
      return (avsyncSeconds: null, frameDrops: null, decoderDrops: null);
    }
    Future<String?> read(String property) async {
      try {
        return await platform
            .getProperty(property)
            .timeout(const Duration(seconds: 2));
      } on Object {
        return null;
      }
    }

    final avsync = double.tryParse(await read('avsync') ?? '');
    final frameDrops = int.tryParse(await read('frame-drop-count') ?? '');
    final decoderDrops = int.tryParse(
      await read('decoder-frame-drop-count') ?? '',
    );
    if (_disposed || generation != _generation || !identical(_player, player)) {
      return (avsyncSeconds: null, frameDrops: null, decoderDrops: null);
    }
    return (
      avsyncSeconds: avsync?.isFinite == true ? avsync : null,
      frameDrops: frameDrops,
      decoderDrops: decoderDrops,
    );
  }

  void _publish(PlaybackSnapshot value) {
    if (_disposed || _snapshots.isClosed) return;
    _snapshot = value;
    _videoOutput.updateVideoDimensions(value.videoDimensions);
    _nativeErrors.update(value);
    _snapshots.add(value);
    if (_watchDashContinuity && !_dashInterruptionPending) {
      final boundary = _dashContinuity.update(value, _continuityClock.elapsed);
      if (boundary != null) _interruptDashVideo(boundary, value.generation);
    }
  }

  void _interruptDashVideo(Duration boundary, int generation) {
    _dashInterruptionPending = true;
    // Snapshot delivery is synchronous. Defer commands/publications until the
    // current event has finished, and respect a queued pause/seek/source change.
    scheduleMicrotask(() {
      unawaited(
        _serial(() async {
          if (_disposed || generation != _generation) return;
          if (_snapshot.phase != PlaybackPhase.playing ||
              !_snapshot.desiredPlaying ||
              _snapshot.isSeeking ||
              _snapshot.isBuffering ||
              _snapshot.buffered != boundary) {
            _dashInterruptionPending = false;
            _dashContinuity.reset();
            return;
          }
          final player = _player;
          if (player == null) {
            _dashInterruptionPending = false;
            return;
          }
          _diagnose(PlayerDiagnosticKind.videoInterrupted);
          _publish(
            _snapshot.copyWith(
              position: boundary,
              desiredPlaying: false,
              phase: PlaybackPhase.buffering,
              isBuffering: true,
            ),
          );
          try {
            // A failed phase alone does not stop mpv's external audio clock.
            await player.pause().timeout(const Duration(seconds: 2));
          } on Object {
            if (generation != _generation || _disposed) return;
            await _releasePlayer();
          }
          if (generation != _generation || _disposed) return;
          _dashInterruptionPending = false;
          _publish(
            _snapshot.copyWith(position: boundary, desiredPlaying: false),
          );
          _fail(
            PlayerFailure(
              PlayerFailureKind.videoInterrupted,
              '视频流已中断，音频已暂停，请重新加载或切换清晰度。',
              generation,
            ),
          );
        }),
      );
    });
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
    _dashContinuity.reset();
    _dashInterruptionPending = false;
    final value = ++_generation;
    _videoOutput.advanceGeneration(value);
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

  static const _externalAudioProperty =
      'current-tracks/audio/external-filename';

  Future<Completer<void>> _configureExternalAudio(
    mk.Player player,
    MediaTrack audio,
    int generation,
    Stopwatch watch,
    Duration budget,
  ) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'The playback backend cannot prepare external audio.',
        generation,
      );
    }
    final ready = Completer<void>();
    final uri = audio.uri.toString();
    await platform
        .observeProperty(_externalAudioProperty, (value) async {
          if (value == uri && !ready.isCompleted) ready.complete();
        })
        .timeout(_remaining(watch, budget));
    await platform
        .setProperty(
          'audio-files',
          mpvPathListEntry(audio.uri, windows: Platform.isWindows),
        )
        .timeout(_remaining(watch, budget));
    // The locked SDK does not propagate property errors. Read back before
    // opening, without emitting the signed URL into diagnostics.
    final applied = await platform
        .getProperty('audio-files')
        .timeout(_remaining(watch, budget));
    if (applied != uri) {
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'The playback backend did not apply the external audio source.',
        generation,
      );
    }
    return ready;
  }

  Future<void> _configureBufferAhead(
    mk.Player player,
    Duration window,
    int generation,
    Stopwatch watch,
    Duration budget,
  ) async {
    final platform = player.platform;
    if (platform is! mk.NativePlayer) {
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        'The playback backend cannot limit forward buffering.',
        generation,
      );
    }
    final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
    final properties = {
      // media_kit enables disk caching by default. Keep a transient bounded
      // window in memory instead of accumulating an append-only cache file.
      'cache-on-disk': 'no',
      // mpv uses the larger of these two windows when network cache is enabled.
      'cache-secs': seconds.toString(),
      'demuxer-readahead-secs': seconds.toString(),
    };
    for (final entry in properties.entries) {
      if (generation != _generation || _disposed) {
        throw const SourceSuperseded();
      }
      await platform
          .setProperty(entry.key, entry.value)
          .timeout(_remaining(watch, budget));
      // The locked SDK does not propagate mpv_set_property_string errors.
      // Verify the requested limit before any media URL can start loading.
      final applied = await platform
          .getProperty(entry.key)
          .timeout(_remaining(watch, budget));
      final matches = entry.key == 'cache-on-disk'
          ? applied == 'no'
          : double.tryParse(applied) == seconds;
      if (!matches) {
        throw PlayerFailure(
          PlayerFailureKind.nativePlayback,
          'The playback backend did not apply the forward buffer limit.',
          generation,
        );
      }
    }
  }

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
        changes: [
          ...changes,
          _generationChanges.stream,
          if (_nativeLoad case final load?) load.state.changes,
        ],
        timeout: timeout,
        failure: () => _loadFailure(generation),
      );
    } on TimeoutException {
      throw PlayerFailure(
        PlayerFailureKind.nativePlayback,
        safeMessage,
        generation,
      );
    }
  }

  PlayerFailure? _loadFailure(int generation) {
    final code = _nativeLoad?.state.errorCode;
    return code == null
        ? null
        : PlayerFailure(
            PlayerFailureKind.nativePlayback,
            'Native source loading terminated with an error.',
            generation,
          );
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
    _readinessStage = null;
    _diagnose(PlayerDiagnosticKind.openStarted);
    return _serial(() async {
      if (generation != _generation || _disposed) return;
      await _releasePlayer();
      if (generation != _generation || _disposed) return;
      try {
        final (video, audio) = _validate(source, options, generation);
        _watchDashContinuity = source is DashPairSource && audio != null;
        final mediaTrack = await _mediaLeases.open(video);
        final audioTrack = audio == null
            ? null
            : await _mediaLeases.open(audio);
        if (generation != _generation || _disposed) {
          await _mediaLeases.close();
          return;
        }
        final watch = Stopwatch()..start();
        final openBudget = options.openTimeout;
        initializePlayerBackend();
        final player = mk.Player(
          configuration: const mk.PlayerConfiguration(
            logLevel: mk.MPVLogLevel.warn,
          ),
        );
        _player = player;
        final platform = player.platform;
        if (platform is mk.NativePlayer) {
          _audioGain = NativeAudioGain(
            write: platform.setProperty,
            read: platform.getProperty,
            isCurrent: () =>
                generation == _generation &&
                !_disposed &&
                identical(_player, player),
          );
        }
        _subscribe(player, generation);
        _videoOutput.bindPlayer(
          player,
          generation: generation,
          decoding: options.videoDecoding,
        );
        await _configureBufferAhead(
          player,
          options.maxBufferAhead,
          generation,
          watch,
          openBudget,
        );
        if (experimentalVideoFrameQueue && source is DashPairSource) {
          if (platform is! mk.NativePlayer) {
            throw PlayerFailure(
              PlayerFailureKind.nativePlayback,
              'The playback backend cannot configure video frame buffering.',
              generation,
            );
          }
          await configureNativeVideoFrameQueue(
            write: platform.setProperty,
            read: platform.getProperty,
            isCurrent: () =>
                generation == _generation &&
                !_disposed &&
                identical(_player, player),
            timeout: _remaining(watch, openBudget),
          );
          _videoFrameQueueActive = true;
        }
        if (generation != _generation || _disposed) return;
        // Register the track before loadfile. mpv loads it in its cancellable
        // file-loading worker, instead of holding media_kit's command lock in
        // audio-add while network I/O stalls. Both tracks use the on_load
        // header hook; _validate requires identical, credential-free headers.
        final audioReady = audioTrack == null
            ? null
            : await _configureExternalAudio(
                player,
                audioTrack,
                generation,
                watch,
                openBudget,
              );
        if (generation != _generation || _disposed) return;
        if (platform is mk.NativePlayer) {
          final load = await NativeLoadObserver.attach(
            platform,
            isCurrent: () =>
                generation == _generation &&
                !_disposed &&
                identical(_player, player),
            onFailure: (code) => _diagnose(
              PlayerDiagnosticKind.openTerminated,
              nativeErrorCode: code,
            ),
          ).timeout(_remaining(watch, openBudget));
          _nativeLoad = load;
        }
        if (generation != _generation || _disposed) return;
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
        _readinessStage = NativeReadinessStage.tracks;
        if (source is DashPairSource || source is DashVideoSource) {
          // Player.open only acknowledges loadlist. Wait for actual demuxed
          // tracks after the on_load header hook has run.
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
        if (source is! DashPairSource && source is! DashVideoSource) {
          // Discover whether a progressive/manifest source has video before
          // requiring video decode/output on any platform. Audio-only media
          // must not wait for an output it will never create.
          await _waitReady(
            player,
            generation,
            () =>
                _hasRealTrack(player.state.tracks.video) ||
                player.state.tracks.audio.any(
                  (track) => track.id != 'auto' && track.id != 'no',
                ),
            [player.stream.tracks],
            _remaining(watch, openBudget),
            'Media tracks did not become ready.',
          );
        }
        final requireVideoOutput =
            source is DashPairSource ||
            source is DashVideoSource ||
            _hasRealTrack(player.state.tracks.video);
        Future<void> waitForOutput() => waitForNativeSignal(
          signal: _videoOutput.firstFrameRendered,
          superseded: () =>
              generation != _generation ||
              _disposed ||
              !identical(_player, player),
          changes: [
            _generationChanges.stream,
            if (_nativeLoad case final load?) load.state.changes,
          ],
          timeout: _remaining(watch, openBudget),
          failure: () => _loadFailure(generation),
        );
        if (generation != _generation || _disposed) return;
        if (audioReady != null) {
          _readinessStage = NativeReadinessStage.externalAudio;
          // A real embedded audio track is insufficient: confirm that mpv
          // selected this source's external file, then verify decoding on play.
          await waitForNativeSignal(
            signal: audioReady.future,
            superseded: () =>
                generation != _generation ||
                _disposed ||
                !identical(_player, player),
            changes: [
              _generationChanges.stream,
              if (_nativeLoad case final load?) load.state.changes,
            ],
            timeout: _remaining(watch, openBudget),
            failure: () => _loadFailure(generation),
          );
          await (player.platform as mk.NativePlayer)
              .unobserveProperty(_externalAudioProperty)
              .timeout(_remaining(watch, openBudget));
          _requiresDecodedAudio = true;
        } else if (source is DashPairSource || source is DashVideoSource) {
          await player
              .setAudioTrack(mk.AudioTrack.no())
              .timeout(_remaining(watch, openBudget));
        }
        if (generation != _generation || _disposed) return;
        if (requireVideoOutput) {
          // A listed track can fail decoding while mpv keeps playing the
          // external audio. Confirm video while still paused, inside open's
          // shared deadline, so the caller can use its bounded CDN fallback.
          _readinessStage = NativeReadinessStage.videoDecode;
          await _waitReady(
            player,
            generation,
            () =>
                (player.state.videoParams.w ?? 0) > 0 &&
                (player.state.videoParams.h ?? 0) > 0,
            [player.stream.videoParams],
            _remaining(watch, openBudget),
            'Video did not decode.',
          );
          _readinessStage = NativeReadinessStage.videoOutput;
          // Decoder metadata alone does not establish a native video output.
          // mpv renders a video frame while paused; no audio probe is needed.
          await waitForOutput();
        }
        if (generation != _generation || _disposed) return;
        _readinessStage = null;
        await player
            .setRate(options.rate)
            .timeout(_remaining(watch, openBudget));
        await player
            .setVolume(options.volume)
            .timeout(_remaining(watch, openBudget));
        if (options.audioGainDb != 0) {
          final gain = _audioGain;
          if (gain == null) {
            throw StateError('Native audio gain is unavailable.');
          }
          await gain
              .apply(options.audioGainDb, smooth: false)
              .timeout(_remaining(watch, openBudget));
        }
        if (options.startPosition > Duration.zero) {
          _publish(_snapshot.copyWith(isSeeking: true));
          await player
              .seek(options.startPosition)
              .timeout(_remaining(watch, openBudget));
          // seek acknowledges the command before its position event arrives.
          // Output initialization must not decide whether open exposes the
          // resumed position, especially when the source remains paused.
          final duration = player.state.duration;
          final target =
              duration > Duration.zero && options.startPosition > duration
              ? duration
              : options.startPosition;
          await _waitReady(
            player,
            generation,
            () =>
                (player.state.position - target).abs() <=
                const Duration(milliseconds: 250),
            [player.stream.position],
            _remaining(watch, openBudget),
            'Initial playback position did not become ready.',
          );
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
        if (_loadFailure(generation) case final failure?) throw failure;
        _publish(_snapshot.copyWith(phase: PlaybackPhase.ready));
        _diagnose(PlayerDiagnosticKind.openReady);
        if (options.play) {
          await player.play().timeout(_remaining(watch, openBudget));
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
        if (generation != _generation || _disposed) return;
        if (_loadFailure(generation) case final failure?) throw failure;
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
    final maxBufferAhead = options.maxBufferAhead;
    if (options.startPosition < Duration.zero ||
        !options.rate.isFinite ||
        options.rate <= 0 ||
        !options.volume.isFinite ||
        options.volume < 0 ||
        options.volume > 100 ||
        !NativeAudioGain.valid(options.audioGainDb) ||
        options.openTimeout <= Duration.zero ||
        maxBufferAhead <= Duration.zero ||
        maxBufferAhead > OpenOptions.maximumBufferAhead) {
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
    if (!{
          'http',
          'https',
          'file',
          if (Platform.isAndroid) 'content',
        }.contains(track.uri.scheme) ||
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
    // Native EOF can be followed by playing=false or buffering=false. Keep
    // completion observable until an explicit seek/play or source replacement.
    bool canChangePhase() =>
        active() &&
        _snapshot.phase != PlaybackPhase.failed &&
        _snapshot.phase != PlaybackPhase.ended;
    _subscriptions.add(
      player.stream.videoParams.listen((value) {
        if (!active()) return;
        final dimensions = videoDisplayDimensions(value);
        final previous = _snapshot.videoDimensions;
        if (dimensions != null &&
            (dimensions.width != previous?.width ||
                dimensions.height != previous?.height)) {
          _publish(_snapshot.copyWith(videoDimensions: dimensions));
        }
      }),
    );
    _subscriptions.add(
      player.stream.position.listen((value) {
        if (active() &&
            !_dashInterruptionPending &&
            _snapshot.phase != PlaybackPhase.failed) {
          _publish(_snapshot.copyWith(position: value));
        }
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
          // media_kit emits completion before its final buffering=false event.
          // Ended ignores those late events, so clear transient flags here.
          _publish(
            _snapshot.copyWith(
              phase: PlaybackPhase.ended,
              desiredPlaying: false,
              isBuffering: false,
              isSeeking: false,
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
    _watchDashContinuity = false;
    _dashInterruptionPending = false;
    _dashContinuity.reset();
    _videoFrameQueueActive = false;
    final load = _nativeLoad;
    _nativeLoad = null;
    await load?.dispose();
    _audioGain?.cancel();
    _audioGain = null;
    _nativeErrors.reset();
    _requiresDecodedAudio = false;
    _readinessStage = null;
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _videoOutput.clearPlayer();
    final old = _player;
    _player = null;
    try {
      if (old != null) await old.dispose();
    } finally {
      await _mediaLeases.close();
    }
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
    return _command(
      (player) async {
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
      },
      optimistic: (s) => s.copyWith(
        desiredPlaying: true,
        phase: s.phase == PlaybackPhase.ended ? PlaybackPhase.paused : s.phase,
      ),
    );
  }

  @override
  Future<void> pause() => _command(
    (player) => player.pause(),
    optimistic: (s) => s.copyWith(desiredPlaying: false),
  );
  @override
  Future<void> seek(Duration target) {
    if (target < Duration.zero) throw ArgumentError.value(target, 'target');
    final generation = _generation;
    return _command(
      (player) async {
        await player.seek(target);
        // A command reply can precede the position event. Callers use this
        // completion to save progress and rebuild danmaku, so confirm the
        // backend position before clearing seeking or exposing a checkpoint.
        final duration = player.state.duration;
        final expected = duration > Duration.zero && target > duration
            ? duration
            : target;
        await _waitReady(
          player,
          generation,
          () =>
              (player.state.position - expected).abs() <=
              const Duration(milliseconds: 250),
          [player.stream.position],
          const Duration(seconds: 12),
          'Playback position did not become ready after seeking.',
        );
        if (!_disposed &&
            generation == _generation &&
            identical(_player, player)) {
          _publish(
            _snapshot.copyWith(
              position: player.state.position,
              isSeeking: false,
            ),
          );
        }
      },
      optimistic: (s) => s.copyWith(
        isSeeking: true,
        phase: s.phase == PlaybackPhase.ended ? PlaybackPhase.paused : s.phase,
      ),
    );
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
  Future<void> setAudioGain(double gainDb) {
    if (!NativeAudioGain.valid(gainDb)) {
      throw ArgumentError.value(gainDb, 'gainDb');
    }
    return _command((player) async {
      final gain = _audioGain;
      if (gain == null) throw StateError('Native audio gain is unavailable.');
      await gain.apply(gainDb);
    });
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
    _videoOutput.cancelPendingViewport();
    await _serial(_releasePlayer);
    _disposed = true;
    _videoOutput.dispose();
    await _snapshots.close();
    await _failures.close();
    await _generationChanges.close();
  }
}
