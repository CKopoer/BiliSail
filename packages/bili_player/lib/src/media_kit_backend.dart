import 'dart:async';
import 'dart:io';

import 'package:media_kit/media_kit.dart' as mk;

import 'player_contract.dart';
import 'android_media_leases.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'native_playback_information.dart';
import 'native_readiness.dart';
import 'playback_backend.dart';
import 'validated_source.dart';
import 'native_media_options.dart';
import 'native_player_properties.dart';
import 'native_playback_health.dart';
import 'native_load_observer.dart';
import 'native_audio_gain.dart';
import 'native_rate_audio.dart';
import 'native_video_frame_queue.dart';
import 'native_video_color.dart';
import 'video_dimensions.dart';
import 'media_kit_video_output.dart';
import 'video_output.dart';

/// mpv commands and observations for one source; owns no playback state.
final class MediaKitBackend implements PlaybackBackend {
  MediaKitBackend({
    required this.snapshot,
    this.onDiagnostic,
    bool? experimentalVideoFrameQueue,
    bool? experimentalAndroidViewport,
    this.experimentalAudioAutosync,
  }) : _videoOutput = MediaKitVideoOutput(
         limitAndroidOutputToViewport: experimentalAndroidViewport,
       ),
       experimentalVideoFrameQueue = resolveVideoFrameQueueEnabled(
         isAndroid: Platform.isAndroid,
         enabledOverride: experimentalVideoFrameQueue,
       );
  final PlaybackSnapshot Function() snapshot;
  PlaybackSnapshot get _snapshot => snapshot();
  final void Function(PlayerDiagnosticEvent)? onDiagnostic;
  final bool experimentalVideoFrameQueue;
  final int? experimentalAudioAutosync;
  bool _videoFrameQueueActive = false;
  bool get videoFrameQueueActive => _videoFrameQueueActive;
  final _mediaLeases = AndroidMediaLeases();
  final _events = StreamController<BackendEvent>.broadcast(sync: true);
  final _generationChanges = StreamController<int>.broadcast(sync: true);
  final _seekChanges = StreamController<int>.broadcast(sync: true);
  final MediaKitVideoOutput _videoOutput;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  mk.Player? _player;
  MediaTrack? _seekMedia;
  Duration? _restartSeekTarget;
  bool _replaceSeek = false;
  NativeLoadObserver? _nativeLoad;
  NativeAudioGain? _audioGain;
  Future<mk.Player>? _creating;
  Future<void>? _disposal;
  PlaybackOperation? _preparation;
  PlaybackOperation? _seek;
  bool _disposed = false;
  bool _requiresVideoColorMapping = false;
  bool _paired = false;
  int _generation = 0;
  int _seekRevision = 0;
  NativeReadinessStage? _readinessStage;
  Timer? _colorDeadline;
  NativeReadinessStage? get readinessStage => _readinessStage;
  double get appliedAudioGainDb => _audioGain?.gainDb ?? 0;
  @override
  Duration get seekTimeout => const Duration(seconds: 12);
  @override
  VideoOutput get videoOutput => _videoOutput;
  @override
  Stream<BackendEvent> get events => _events.stream;
  ({int? width, int? height})? get debugRequestedVideoViewport =>
      _videoOutput.debugRequestedViewport;
  void _emit(BackendEvent event) {
    if (!_disposed && !_events.isClosed) _events.add(event);
  }

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

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation(
    int sourceGeneration,
  ) async {
    final player = _player;
    final generation = _generation;
    if (player == null || _disposed) return null;
    final information = await sampleNativePlaybackInformation(
      read: player.getPropertyAsync,
      diagnostics: inspectDiagnostics(),
      audioGainDb: appliedAudioGainDb,
    );
    if (_disposed || generation != _generation || !identical(player, _player)) {
      return null;
    }
    return information;
  }

  /// Actual native hardware decoder, e.g. d3d11va or "no" for software.
  /// Null means unavailable or superseded; no raw native strings are exposed.
  Future<String?> inspectHardwareDecoder() async {
    final player = _player;
    final platform = player;
    final generation = _generation;
    if (platform == null || _disposed) return null;
    try {
      final value = await platform
          .getPropertyAsync('hwdec-current')
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
  Future<
    ({
      double? avsyncSeconds,
      int? frameDrops,
      int? decoderDrops,
      double? nativeRate,
      double? audioPositionSeconds,
      double? videoPositionSeconds,
    })
  >
  inspectNativePlaybackTiming({bool includeRateClocks = false}) async {
    final player = _player;
    final platform = player;
    final generation = _generation;
    if (platform == null || _disposed) {
      return (
        avsyncSeconds: null,
        frameDrops: null,
        decoderDrops: null,
        nativeRate: null,
        audioPositionSeconds: null,
        videoPositionSeconds: null,
      );
    }
    Future<String?> read(String property) async {
      try {
        return await platform
            .getPropertyAsync(property)
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
    Future<double?> clock(String name) async {
      final value = double.tryParse(await read(name) ?? '');
      return value?.isFinite == true ? value : null;
    }

    final nativeRate = includeRateClocks ? await clock('speed') : null;
    final audioPosition = includeRateClocks ? await clock('audio-pts') : null;
    final videoPosition = includeRateClocks ? await clock('video-pts') : null;
    if (_disposed || generation != _generation || !identical(_player, player)) {
      return (
        avsyncSeconds: null,
        frameDrops: null,
        decoderDrops: null,
        nativeRate: null,
        audioPositionSeconds: null,
        videoPositionSeconds: null,
      );
    }
    return (
      avsyncSeconds: avsync?.isFinite == true ? avsync : null,
      frameDrops: frameDrops,
      decoderDrops: decoderDrops,
      nativeRate: nativeRate,
      audioPositionSeconds: audioPosition,
      videoPositionSeconds: videoPosition,
    );
  }

  /// Safe output/configuration metadata, sampled once rather than every frame.
  /// audio-buffer is a requested minimum, not the audio device's measured delay.
  Future<Map<String, Object?>> inspectNativeOutputConfiguration() async {
    final player = _player;
    final generation = _generation;
    if (player == null || _disposed) return const {};
    Future<String?> read(String name) async {
      try {
        return await player
            .getPropertyAsync(name)
            .timeout(const Duration(seconds: 1));
      } on Object {
        return null;
      }
    }

    String? identifier(String? text) =>
        text != null && RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch(text)
        ? text
        : null;
    final ao = identifier(await read('current-ao'));
    final vo = identifier(await read('current-vo'));
    final buffer = double.tryParse(await read('audio-buffer') ?? '');
    final autosync = int.tryParse(await read('autosync') ?? '');
    final version = await read('mpv-version');
    final androidSize = Platform.isAndroid
        ? await read('android-surface-size')
        : null;
    if (_disposed || generation != _generation || !identical(_player, player)) {
      return const {};
    }
    return {
      'audioOutput': ao,
      'videoOutput': vo,
      'requestedAudioBufferSeconds': buffer?.isFinite == true ? buffer : null,
      'autosync': autosync,
      'androidSurfaceSize':
          androidSize != null &&
              RegExp(r'^[0-9]{1,5}x[0-9]{1,5}$').hasMatch(androidSize)
          ? androidSize
          : null,
      'mpvVersion':
          version != null &&
              RegExp(r'^[A-Za-z0-9 ._+-]{1,80}$').hasMatch(version)
          ? version
          : null,
    };
  }

  /// Validation-only SurfaceView experiment. The caller must pause first and
  /// retain the JNI Surface reference until this engine has stopped/disposed.
  Future<void> replaceAndroidSurfaceForBenchmark(int surface) async {
    final player = _player;
    final generation = _generation;
    if (!Platform.isAndroid ||
        player == null ||
        _disposed ||
        surface <= 0 ||
        _snapshot.desiredPlaying) {
      throw StateError(
        'The Android surface experiment requires paused playback.',
      );
    }
    await player.setPropertyAsync('vo', 'null');
    await player.setPropertyAsync('wid', '$surface');
    await player.setPropertyAsync('vo', 'mediacodec_embed');
    if (_disposed ||
        generation != _generation ||
        !identical(player, _player) ||
        await player.getPropertyAsync('wid') != '$surface') {
      throw StateError('The Android surface experiment was superseded.');
    }
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

  Future<Completer<void>> _configureExternalAudio(
    mk.Player player,
    MediaTrack audio,
    int generation,
    Stopwatch watch,
    Duration budget,
  ) async {
    final platform = player;

    final ready = Completer<void>();
    final uri = audio.uri.toString();
    await platform
        .setPropertyAsync(
          'audio-files',
          mpvPathListEntry(audio.uri, windows: Platform.isWindows),
        )
        .timeout(_remaining(watch, budget));
    // The locked SDK does not propagate property errors. Read back before
    // opening, without emitting the signed URL into diagnostics.
    final applied = await platform
        .getPropertyAsync('audio-files')
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
    ResolvedMediaSource source,
    Duration window,
    int generation,
    Stopwatch watch,
    Duration budget,
  ) async {
    final platform = player;

    final seconds = window.inMicroseconds / Duration.microsecondsPerSecond;
    final live = switch (source) {
      ManifestSource(:final isLive) ||
      ProgressiveSource(:final isLive) => isLive,
      _ => false,
    };
    final preview = source is DashVideoSource;
    final properties = {
      // media_kit enables disk caching by default. Keep a transient bounded
      // window in memory instead of accumulating an append-only cache file.
      'cache-on-disk': 'no',
      'cache': 'yes',
      'cache-pause': 'yes',
      // The SDK's 5s I/O timeout would end a recoverable connection before
      // the buffering watchdog allows it to refill. Open still has its own
      // shorter/shared deadline and can cancel the native loading worker.
      'network-timeout': NativePlaybackHealth.bufferingTimeout.inSeconds
          .toString(),
      // Avoid resuming on the first small burst after an underrun. Live also
      // builds a short cushion before starting; previews keep quick startup.
      'cache-pause-wait': live ? '3' : (preview ? '1' : '2'),
      'cache-pause-initial': live ? 'yes' : 'no',
      // A live stream cannot seek back. Use the existing 64 MiB total packet
      // allowance for forward data instead of retaining consumed packets.
      'demuxer-max-bytes': (live ? 64 * 1024 * 1024 : 32 * 1024 * 1024)
          .toString(),
      'demuxer-max-back-bytes': (live ? 0 : 32 * 1024 * 1024).toString(),
      // mpv uses the larger of these two windows when network cache is enabled.
      'cache-secs': seconds.toString(),
      'demuxer-readahead-secs': seconds.toString(),
    };
    for (final entry in properties.entries) {
      if (generation != _generation || _disposed) {
        throw const SourceSuperseded();
      }
      await platform
          .setPropertyAsync(entry.key, entry.value)
          .timeout(_remaining(watch, budget));
      // The locked SDK does not propagate mpv_set_property_string errors.
      // Verify the requested limit before any media URL can start loading.
      final applied = await platform
          .getPropertyAsync(entry.key)
          .timeout(_remaining(watch, budget));
      final expectedNumber = double.tryParse(entry.value);
      final matches = expectedNumber == null
          ? applied == entry.value
          : double.tryParse(applied) == expectedNumber;
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
    String safeMessage, {
    bool Function()? superseded,
  }) async {
    try {
      await waitForNativeState(
        ready: ready,
        superseded: () =>
            generation != _generation ||
            _disposed ||
            (_preparation?.isCancelled ?? false) ||
            !identical(_player, player) ||
            (superseded?.call() ?? false),
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
    if (_nativeLoad?.state.preparationFailed ?? false) {
      if (_nativeLoad?.state.preparationError
          case final PlayerFailure failure) {
        return failure;
      }
      return PlayerFailure(
        PlayerFailureKind.unsupportedVideoColor,
        '当前播放后端无法正确显示此杜比视界视频',
        generation,
      );
    }
    final code = _nativeLoad?.state.errorCode;
    return code == null
        ? null
        : PlayerFailure(
            // A filter/VO can terminate loading after on_preloaded but
            // before external audio selection, so do not wait for the
            // video-readiness stage to classify this as incompatible.
            _requiresVideoColorMapping
                ? PlayerFailureKind.unsupportedVideoColor
                : PlayerFailureKind.nativePlayback,
            'Native source loading terminated with an error.',
            generation,
          );
  }

  @override
  Future<PreparedTracks> preparePaused(
    ValidatedSource plan,
    PlaybackOperation operation,
  ) async {
    _preparation = operation;
    _generation = operation.generation;
    final generation = _generation;
    final source = plan.source;
    final options = plan.options;
    final video = plan.media;
    final audio = plan.audio;
    _paired = audio != null;
    final watch = Stopwatch()..start();
    final openBudget = operation.remaining;
    _videoOutput.advanceGeneration(generation);
    final mediaTrack = await _mediaLeases.open(video);
    final audioTrack = audio == null ? null : await _mediaLeases.open(audio);
    if (generation != _generation || _disposed) {
      await _mediaLeases.close();
      throw const SourceSuperseded();
    }
    mk.MediaKit.ensureInitialized();
    final creating = _creating = createNativePlayer().then((player) {
      _player = player;
      return player;
    });
    final player = await operation.wait(creating);
    _creating = null;
    _player = player;
    await operation.wait(player.setVolume(options.volume));
    final platform = player;

    _audioGain = NativeAudioGain(
      write: player.setPropertyAsync,
      read: player.getPropertyAsync,
      isCurrent: () =>
          generation == _generation && !_disposed && identical(_player, player),
    );

    await operation.wait(_audioGain!.apply(options.audioGainDb, smooth: false));
    _subscribe(player, generation);
    final audioOnly = source is ProgressiveSource && source.isAudioOnly;
    if (!audioOnly) {
      await waitForNativeSignal(
        signal: _videoOutput.bindPlayer(
          player,
          generation: generation,
          decoding: options.videoDecoding,
          androidOutput: options.androidVideoOutput,
        ),
        superseded: () => generation != _generation || _disposed,
        changes: [_generationChanges.stream],
        timeout: _remaining(watch, openBudget),
      );
    }
    await _configureBufferAhead(
      player,
      source,
      options.maxBufferAhead,
      generation,
      watch,
      openBudget,
    );
    final rateAdjustable = switch (source) {
      DashPairSource(:final audio) => audio != null,
      ProgressiveSource(:final isLive) ||
      ManifestSource(:final isLive) => !isLive,
      DashVideoSource() => false,
    };
    if (rateAdjustable) {
      await configureNativeRateAudio(
        write: player.setPropertyAsync,
        read: player.getPropertyAsync,
        isCurrent: () =>
            generation == _generation &&
            !_disposed &&
            identical(_player, player),
        timeout: _remaining(watch, openBudget),
      );
      final autosync = experimentalAudioAutosync;
      if (autosync != null) {
        await platform
            .setPropertyAsync('autosync', '$autosync')
            .timeout(_remaining(watch, openBudget));
        final applied = await platform
            .getPropertyAsync('autosync')
            .timeout(_remaining(watch, openBudget));
        if (generation != _generation || _disposed) {
          throw const SourceSuperseded();
        }
        if (int.tryParse(applied) != autosync) {
          throw StateError('The native backend rejected validation autosync.');
        }
      }
    }
    if (experimentalVideoFrameQueue && source is DashPairSource) {
      await configureNativeVideoFrameQueue(
        write: player.setPropertyAsync,
        read: player.getPropertyAsync,
        isCurrent: () =>
            generation == _generation &&
            !_disposed &&
            identical(_player, player),
        timeout: _remaining(watch, openBudget),
      );
      _videoFrameQueueActive = true;
    }
    if (generation != _generation || _disposed) throw const SourceSuperseded();
    // Register the track before loadfile. mpv loads it in its cancellable
    // file-loading worker, instead of holding media_kit's command lock in
    // audio-add while network I/O stalls. Both tracks share the player's
    // explicit headers; _validate requires identical credential-free values.
    final audioReady = audioTrack == null
        ? null
        : await _configureExternalAudio(
            player,
            audioTrack,
            generation,
            watch,
            openBudget,
          );
    _seekMedia = mediaTrack;
    if (generation != _generation || _disposed) throw const SourceSuperseded();

    final load = await NativeLoadObserver.attach(
      player.native,
      isCurrent: () =>
          generation == _generation && !_disposed && identical(_player, player),
      onPreloaded: !audioOnly
          ? () async {
              if (generation != _generation ||
                  _disposed ||
                  !identical(_player, player)) {
                return;
              }
              if (_restartSeekTarget case final target?) {
                player.setProperty(
                  'start',
                  (target.inMicroseconds / 1000000).toStringAsFixed(6),
                );
              }
              _requiresVideoColorMapping = configureNativeVideoColor(
                read: player.getProperty,
                write: player.setProperty,
                isAndroid: Platform.isAndroid,
                onAndroidDolbyVision: _videoOutput.enableAndroidDolbyVision,
                codecHint: video.codec,
              );
              if (_requiresVideoColorMapping && !operation.isCancelled) {
                // A converter/VO may accept its options but never produce
                // a frame. Leave time for the caller's compatible source.
                _colorDeadline = Timer(const Duration(seconds: 6), () {
                  if (generation == _generation &&
                      !_disposed &&
                      identical(_player, player)) {
                    _nativeLoad?.state.failPreparation();
                  }
                });
              }
              try {
                // Size the active renderer after any source-specific
                // switch, including Android's Dolby Vision output.
                await _videoOutput.prepareAndroidSurface(player.getProperty);
              } on Object {
                throw PlayerFailure(
                  _requiresVideoColorMapping
                      ? PlayerFailureKind.unsupportedVideoColor
                      : PlayerFailureKind.nativePlayback,
                  'Android video surface could not be prepared.',
                  generation,
                );
              }
            }
          : null,
      onExternalAudio: audioReady == null
          ? null
          : (uri) {
              if (uri == audioTrack?.uri.toString() &&
                  !audioReady.isCompleted) {
                audioReady.complete();
              }
            },
      onFailure: (code) =>
          _diagnose(PlayerDiagnosticKind.openTerminated, nativeErrorCode: code),
    ).timeout(_remaining(watch, openBudget));
    _nativeLoad = load;

    if (generation != _generation || _disposed) throw const SourceSuperseded();
    await player
        .open(
          mk.Media(
            mediaTrack.uri.toString(),
            httpHeaders: mediaTrack.requestPolicy.headers,
            // Resume as part of loading, before decoding the first frame.
            // Opening at zero and seeking afterward buffers twice when
            // returning from audio-only playback.
            start: options.startPosition > Duration.zero
                ? options.startPosition
                : null,
          ),
          play: false,
        )
        .timeout(_remaining(watch, openBudget));
    if (generation != _generation || _disposed) throw const SourceSuperseded();
    _readinessStage = NativeReadinessStage.tracks;
    if (source is DashPairSource || source is DashVideoSource) {
      // Player.open acknowledges playlist setup. Wait for the actual
      // demuxed tracks after headers have been applied.
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
    if (audioOnly && requireVideoOutput) {
      throw PlayerFailure(
        PlayerFailureKind.invalidSource,
        'An audio-only source must not contain a video track.',
        generation,
      );
    }
    if (generation != _generation || _disposed) throw const SourceSuperseded();
    if (audioReady != null) {
      _readinessStage = NativeReadinessStage.externalAudio;
      // A real embedded audio track is insufficient: confirm that mpv
      // selected this source's external file, then verify paused decoding.
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
    } else if (source is DashPairSource || source is DashVideoSource) {
      await player
          .setAudioTrack(mk.AudioTrack.no())
          .timeout(_remaining(watch, openBudget));
    }

    if (options.startPosition > Duration.zero) {
      if (requireVideoOutput) {
        // At/beyond EOF mpv confirms the clamped time only after its paused
        // final frame is rendered. Preserve that native ordering on resume.
        await confirmVideo(operation);
        if (!options.play && !_requiresVideoColorMapping) {
          await operation.wait(_videoOutput.videoFramePresented);
        }
      }
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
        operation.remaining,
        'Initial position did not become ready.',
      );
    }
    return PreparedTracks(
      hasVideo: requireVideoOutput,
      hasAudio:
          audioTrack != null ||
          player.state.tracks.audio.any((t) => t.id != 'auto' && t.id != 'no'),
      externalAudioSelected: audioReady?.isCompleted ?? false,
      duration: plan.live ? Duration.zero : player.state.duration,
      position: player.state.position,
      dimensions: videoDisplayDimensions(player.state.videoParams),
    );
  }

  @override
  Future<VideoDimensions?> confirmVideo(PlaybackOperation operation) async {
    final player = _player!;
    final generation = _generation;
    final watch = Stopwatch()..start();
    final openBudget = operation.remaining;
    final load = _nativeLoad!;
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
    await operation.wait(_videoOutput.firstFrameRendered);
    if (_requiresVideoColorMapping) {
      // The official controller may publish dimensions before the
      // filtered frame's output parameters. Confirm conversion through
      // this source's native events before inspecting its final matrix.
      await _waitReady(
        player,
        generation,
        () => Platform.isAndroid
            ? load.state.videoOutputDriver == 'gpu-next'
            : load.state.videoOutputMatrix == 'bt.709',
        const [],
        _remaining(watch, openBudget),
        'Video color conversion did not become ready.',
      );
    }
    final profile = player.getProperty(
      'current-tracks/video/dolby-vision-profile',
    );
    final outputMatrix = player.getProperty('video-out-params/colormatrix');
    final unmappedDolby =
        !_requiresVideoColorMapping &&
        outputMatrix == 'dolbyvision' &&
        (profile.isEmpty || profile == '5');
    final mappingFailed =
        _requiresVideoColorMapping &&
        (Platform.isAndroid
            ? player.getProperty('current-vo') != 'gpu-next'
            : outputMatrix != 'bt.709');
    if (unmappedDolby || mappingFailed) {
      throw PlayerFailure(
        PlayerFailureKind.unsupportedVideoColor,
        '当前播放后端无法正确显示此杜比视界视频',
        generation,
      );
    }

    _colorDeadline?.cancel();
    _readinessStage = null;
    return videoDisplayDimensions(player.state.videoParams);
  }

  @override
  Future<void> confirmAudio(PlaybackOperation operation) =>
      _waitForDecodedAudio(_player!, _generation, operation);
  @override
  Future<void> confirmPresentation(PlaybackOperation operation) =>
      operation.wait(_videoOutput.videoFramePresented);
  Future<void> _waitForDecodedAudio(
    mk.Player player,
    int generation,
    PlaybackOperation operation,
  ) => _waitReady(
    player,
    generation,
    () =>
        (player.state.audioParams.channelCount ?? 0) > 0 &&
        (player.state.audioParams.sampleRate ?? 0) > 0 &&
        _nativeLoad?.state.tracksReady == true,
    [
      player.stream.audioParams,
      operation.changes,
      if (_nativeLoad case final load?) load.state.changes,
    ],
    operation.remaining,
    'External audio did not decode.',
    superseded: () => operation.isCancelled,
  );

  @override
  Future<Duration> seekTo(Duration target, PlaybackOperation operation) async {
    operation.check();
    _seek = operation;
    final player = _player!;
    final generation = _generation;
    final revision = ++_seekRevision;
    final replacePending = _replaceSeek;
    _replaceSeek = false;
    if (replacePending) await operation.wait(pauseAndWait());
    final watch = Stopwatch()..start();
    final budget = operation.remaining;
    // Keep the confirmed source's video barrier while native events settle.
    final video =
        _snapshot.videoDimensions != null ||
        _hasRealTrack(player.state.tracks.video);
    final load = _nativeLoad;
    final previousSeek = load?.state.seekCount ?? 0;
    final previousLoad = load?.state.loadCount ?? 0;
    // mpv owns seeking and cache-pause for the whole pair. Preserve native
    // playback intent and packet cache instead of stopping/reloading the source.
    if (revision != _seekRevision || generation != _generation) {
      throw const SourceSuperseded();
    }
    final media = _seekMedia;
    if (replacePending && media != null) {
      _restartSeekTarget = target;
      await player.native.command([
        'loadfile',
        media.uri.toString(),
        'replace',
        '-1',
        'start=${(target.inMicroseconds / 1000000).toStringAsFixed(6)}',
      ]);
    } else {
      await player.seek(target);
    }
    // time-pos may jump before any target video data has arrived. Require
    // SEEK -> PLAYBACK_RESTART as well as the confirmed target position.
    final duration = player.state.duration;
    final expected = duration > Duration.zero && target > duration
        ? duration
        : target;
    await _waitReady(
      player,
      generation,
      () =>
          (!video ||
              load != null &&
                  (replacePending
                      ? load.state.loadCount > previousLoad &&
                            load.state.restartedLoadCount ==
                                load.state.loadCount
                      : load.state.seekCount > previousSeek &&
                            load.state.restartedSeekCount ==
                                load.state.seekCount)) &&
          (player.state.position - expected).abs() <=
              const Duration(milliseconds: 250),
      [player.stream.position, _seekChanges.stream],
      _remaining(watch, budget),
      'Audio and video did not become ready after seeking.',
      superseded: () => revision != _seekRevision,
    );

    operation.check();
    _restartSeekTarget = null;
    _seek = null;
    return player.state.position;
  }

  @override
  Future<void> cancelSeek() async {
    if (_seek == null) return;
    _seek?.cancel();
    _seekChanges.add(++_seekRevision);
    // The next native seek replaces this target. Retiring only the Dart wait
    // keeps mpv's source, demuxer cache and selected external audio intact.
    if (_player?.state.buffering != true) return;
    // A blocked demux read cannot accept another seek until its socket exits.
    // Reserve source retirement for that native buffering path.
    _replaceSeek = true;
    await _player?.native.command(['stop']);
    await Future<void>.delayed(Duration.zero);
  }

  void _subscribe(mk.Player player, int generation) {
    bool active() =>
        !_disposed && generation == _generation && identical(player, _player);
    void event(BackendEvent value) {
      if (active()) _emit(value);
    }

    _subscriptions.addAll([
      player.stream.videoParams.listen((value) {
        if (!active()) return;
        final dimensions = videoDisplayDimensions(value);
        _videoOutput.updateVideoDimensions(dimensions);
        event(BackendEvent(BackendEventKind.sample, dimensions: dimensions));
      }),
      player.stream.position.listen(
        (value) =>
            event(BackendEvent(BackendEventKind.sample, position: value)),
      ),
      player.stream.duration.listen(
        (value) =>
            event(BackendEvent(BackendEventKind.sample, duration: value)),
      ),
      player.stream.buffer.listen(
        (value) =>
            event(BackendEvent(BackendEventKind.sample, buffered: value)),
      ),
      player.stream.buffering.listen(
        (value) =>
            event(BackendEvent(BackendEventKind.buffering, value: value)),
      ),
      player.stream.playing.listen(
        (value) => event(BackendEvent(BackendEventKind.playing, value: value)),
      ),
      player.stream.completed.listen((value) {
        if (!value || _seek != null || _replaceSeek) return;
        final revision = _seekRevision;
        unawaited(() async {
          try {
            // A stop/reload can leave a completed event for the retired load.
            final eof = await player
                .getPropertyAsync('eof-reached')
                .timeout(const Duration(seconds: 1));
            if (!active() ||
                revision != _seekRevision ||
                eof != 'yes' ||
                _seek != null ||
                _replaceSeek) {
              return;
            }
            event(
              BackendEvent(
                BackendEventKind.ended,
                position: player.state.position,
              ),
            );
          } on Object {
            // The bounded health sampler still detects a stopped current load.
          }
        }());
      }),
      player.stream.log.listen((log) {
        if (!active()) return;
        final severity = switch (log.level) {
          'warn' => NativeLogSeverity.warning,
          'error' => NativeLogSeverity.error,
          'fatal' => NativeLogSeverity.fatal,
          _ => null,
        };
        if (severity != null) {
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
      player.stream.error.listen((message) {
        if (!active()) return;
        _diagnose(
          PlayerDiagnosticKind.nativeError,
          nativeError: NativeErrorSummary.classify(message),
        );
        event(const BackendEvent(BackendEventKind.warning));
      }),
    ]);
  }

  @override
  Future<void> play() => _player!.play();
  @override
  Future<bool> pauseAndWait() async {
    await (_nativeLoad?.pause() ?? _player?.pause());
    return true;
  }

  @override
  Future<void> setRate(double rate) => _player!.setRate(rate);
  @override
  Future<void> setVolume(double volume) => _player!.setVolume(volume);
  @override
  Future<void> setGainDb(double gainDb) =>
      _audioGain!.apply(gainDb, smooth: false);
  @override
  BackendHealth sampleHealth() {
    final state = _player?.state;
    final audio = _nativeLoad?.state.audioPosition;
    _nativeLoad?.sampleClocks();
    return BackendHealth(
      position: state?.position,
      buffered: state?.buffer,
      audioPosition: audio,
      comparePairedClocks: _paired,
    );
  }

  @override
  void resetHealth() => _nativeLoad?.state.resetClocks();
  @override
  void interrupt() {
    ++_generation;
    _preparation?.cancel();
    unawaited(cancelSeek().catchError((Object _) {}));
    _generationChanges.add(_generation);
    _audioGain?.cancel();
    _videoOutput.cancelPendingViewport();
    final player = _player;
    if (player != null) {
      // stop is dispatched outside media_kit's synchronous property path so
      // a blocked network load can be cancelled before release is queued.
      unawaited(
        player.native
            .command(['stop'])
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      );
    }
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();
  Future<void> _dispose() async {
    interrupt();
    _disposed = true;
    _colorDeadline?.cancel();
    _videoOutput.clearPlayer();
    final creating = _creating;
    if (creating != null) {
      try {
        await creating;
      } on Object {
        /* The factory did not allocate. */
      }
    }
    await _nativeLoad?.dispose();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final player = _player;
    // Keep the player and leases when native release is uncertain.
    if (player != null) await player.dispose();
    _player = null;
    await _mediaLeases.close();
    _videoOutput.dispose();
    await _events.close();
    await _generationChanges.close();
    await _seekChanges.close();
  }
}
