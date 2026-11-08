import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;

import 'android_fvp_player.dart';
import 'android_fvp_worker.dart';
import 'player_contract.dart';
import 'fvp_playback_information.dart';
import 'fvp_video_decoders.dart';
import 'fvp_surface_preroll.dart';
import 'fvp_seek.dart';
import 'player_playback_information.dart';
import 'third_party/fvp_audio_activity.g.dart' as audio_activity;

final class FvpMediaInfo {
  const FvpMediaInfo({
    required this.duration,
    this.dimensions,
    required this.hasAudio,
    this.directSurface = false,
    this._hasVideo,
  });
  final Duration duration;
  final VideoDimensions? dimensions;
  final bool hasAudio;
  final bool directSurface;
  final bool? _hasVideo;
  bool get hasVideo => _hasVideo ?? dimensions != null;
}

enum FvpNativeStatus { buffering, buffered, ended, invalid, processExited }

/// Small native boundary for deterministic cancellation and failure tests.
abstract interface class FvpPlayerPort {
  Stream<FvpNativeStatus> get statuses;
  int get positionMilliseconds;
  int get bufferedMilliseconds;
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    MediaTrack? audioProbe,
    bool isLive = false,
  });
  Future<int> createTexture();
  Future<bool> confirmVideoFrame();
  Future<bool> confirmAudio();
  void play();
  void pause();
  Future<void> pauseAndWait();
  void interrupt();
  Future<int> seek(Duration target);
  // Cancels only in-flight preparation; the next seek restores this source.
  void cancelSeek();
  void setRate(double rate);
  void setVolume(double volume, double gainDb);
  Future<void> dispose();
}

/// Optional statistics capability, independent of playback commands so remote
/// or test adapters can be introduced without inventing native observations.
abstract interface class FvpInformationPort {
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation({
    required int generation,
    required double audioGainDb,
  });
}

/// Count of frames decoded by the actual native audio pipeline, not a probe.
abstract interface class FvpAudioActivityPort {
  int get decodedAudioFrames;
}

/// IPC acknowledgement for commands used by mute and playback barriers.
/// Legacy in-process/test ports can keep their synchronous command API.
abstract interface class FvpCommandCompletionPort {
  Future<void> playAndWait();
  Future<void> setRateAndWait(double rate);
  Future<void> setVolumeAndWait(double volume, double gainDb);
}

/// Native confirmation travels in the pause reply, including across IPC.
abstract interface class FvpPauseConfirmationPort {
  Future<bool> pauseAndConfirm();
}

Future<void>? _initialization;

Future<FvpPlayerPort> createFvpNativePlayer({int? windowsAdapterIndex}) async {
  if (Platform.isAndroid) return AndroidFvpPlayer.create();
  return createInProcessFvpNativePlayer(
    windowsAdapterIndex: windowsAdapterIndex,
  );
}

// The Android service starts this headless entrypoint, without app bootstrap,
// account repositories, or a second visible Flutter application.
@pragma('vm:entry-point')
void fvpWorkerMain() => runFvpWorker(
  createInProcessFvpNativePlayer,
  (player) {
    final local = player as _MdkPlayerPort;
    local._textureDimensions = local._dimensions;
    return local._player.nativeHandle;
  },
  (player) {
    final local = player as _MdkPlayerPort;
    local._videoRendered = true;
    local._videoDecoded = true;
    local._firstFrame.surfaceConsumed();
  },
);

Future<FvpPlayerPort> createInProcessFvpNativePlayer({
  int? windowsAdapterIndex,
}) async {
  await (_initialization ??= () async {
    // Install fvp's bundled Flutter key without forwarding raw URL/header logs.
    fvp.registerWith(
      options: <String, Object>{
        'global': <String, Object>{'log': 'off'},
      },
    );
    await Future<void>.delayed(Duration.zero);
    mdk.setLogHandler((_, _) {});
    mdk.setGlobalOption('logLevel', mdk.LogLevel.off);
    mdk.setGlobalOption('videoout.clear_on_stop', 0);
  }());
  return _MdkPlayerPort(windowsAdapterIndex: windowsAdapterIndex);
}

final class _MdkPlayerPort
    implements
        FvpPlayerPort,
        FvpInformationPort,
        FvpAudioActivityPort,
        FvpPauseConfirmationPort {
  _MdkPlayerPort({this.windowsAdapterIndex});

  final int? windowsAdapterIndex;
  mdk.Player? _native;
  mdk.Player get _player => _native!;
  _MdkPlayerPort? _audioProbe;
  final _interrupted = Completer<void>();
  final _statuses = StreamController<FvpNativeStatus>.broadcast(sync: true);
  StreamSubscription<Object?>? _statusSubscription;
  StreamSubscription<Object?>? _eventSubscription;
  StreamSubscription<Object?>? _stateSubscription;
  final _audioOpened = Completer<bool>();
  final _firstFrame = FvpFirstVideoFrame();
  final _prepared = Completer<bool>();
  final _paused = Completer<void>();
  Future<int>? _textureCreation;
  bool _closed = false;
  bool _closing = false;
  bool _live = false;
  bool _ended = false;
  Duration _startPosition = Duration.zero;
  int? _preparedAudioPosition;
  VideoDimensions? _dimensions;
  Future<void>? _disposal;
  Completer<int>? _seekCancelled;
  Future<void>? _retiringSeek;
  bool _repreparing = false;
  int _nativeSeekRevision = 0;
  String _mediaUri = '';
  String? _audioUri;
  bool _silent = false;
  double? _appliedGainDb;
  mdk.AudioCodecParameters? _externalAudio;
  String? _videoDecoder;
  bool _videoDecoded = false;
  bool _audioDecoded = false;
  bool _videoRendered = false;
  bool _directSurface = false;
  VideoDimensions? _textureDimensions;
  Pointer<Void> _audioActivity = nullptr;

  @override
  int get decodedAudioFrames =>
      audio_activity.bili_fvp_audio_frames(_audioActivity);

  void _initializePlayer() {
    _native = mdk.Player();
    _audioActivity = audio_activity.bili_fvp_audio_attach(_player.nativeHandle);
    if (_audioActivity == nullptr) {
      throw StateError('MDK audio activity observation unavailable');
    }
    _eventSubscription = _player.onEvent.listen((event) {
      if (_closed) return;
      if (event.category == 'decoder.video') {
        if (event.detail == 'open' && event.error < 0) {
          _videoDecoded = false;
          _videoDecoder = null;
        } else if (event.error == 0 && fvpDecoderName(event.detail) != null) {
          _videoDecoder = event.detail;
          _videoDecoded = true;
        }
      }
      if (event.category == 'decoder.audio' &&
          event.error >= 0 &&
          event.detail != 'decode error') {
        _audioDecoded = true;
      }
      if (event.category == 'decoder.audio' && !_audioOpened.isCompleted) {
        _audioOpened.complete(event.error >= 0);
      }
      if (event.category == 'render.video' && event.detail == '1st_frame') {
        if (!_directSurface) {
          _videoRendered = event.error >= 0;
          _videoDecoded = _videoRendered;
        }
        _firstFrame.rendered(event.error >= 0);
      }
    });
    _statusSubscription = _player.onMediaStatus.listen((event) {
      if (_closed || _repreparing) return;
      final status = event.newValue;
      if (status.test(mdk.MediaStatus.invalid)) {
        if (!_prepared.isCompleted) _prepared.complete(false);
        _statuses.add(FvpNativeStatus.invalid);
      } else if (status.test(
        mdk.MediaStatus.buffering | mdk.MediaStatus.stalled,
      )) {
        _statuses.add(FvpNativeStatus.buffering);
      } else if (status.test(mdk.MediaStatus.buffered)) {
        _statuses.add(FvpNativeStatus.buffered);
      }
      if (status.test(mdk.MediaStatus.prepared) && !_prepared.isCompleted) {
        _prepared.complete(true);
      }
    });
    _stateSubscription = _player.onStateChanged.listen((event) {
      if (_closed || _repreparing) return;
      if (event.newValue == mdk.PlaybackState.paused && !_paused.isCompleted) {
        _paused.complete();
      }
      if (event.newValue == mdk.PlaybackState.stopped &&
          event.oldValue != mdk.PlaybackState.stopped) {
        // Demux EOF can precede completion while decoded data remains buffered.
        _ended = _player.mediaStatus.test(mdk.MediaStatus.end);
        _statuses.add(_ended ? FvpNativeStatus.ended : FvpNativeStatus.invalid);
      }
    });
  }

  @override
  Stream<FvpNativeStatus> get statuses => _statuses.stream;
  @override
  int get positionMilliseconds {
    if (_closed) return 0;
    final position = _native?.position ?? 0;
    // Pure audio has no presentation clock until first play. Use the native
    // prepare/seek confirmation while paused, then retire it on the first tick.
    final prepared = _preparedAudioPosition;
    if (position == 0 && prepared != null) {
      return prepared;
    }
    _preparedAudioPosition = null;
    return position;
  }

  @override
  int get bufferedMilliseconds => _closed ? 0 : _native?.buffered() ?? 0;

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation({
    required int generation,
    required double audioGainDb,
  }) async {
    final player = _native;
    if (_closed ||
        _closing ||
        _repreparing ||
        player == null ||
        _interrupted.isCompleted ||
        !player.mediaStatus.test(mdk.MediaStatus.loaded)) {
      return null;
    }
    return sampleFvpPlaybackInformation(
      media: player.mediaInfo,
      externalAudio: _externalAudio,
      silent: _silent,
      videoDecoded: _videoDecoded,
      audioDecoded: _audioDecoded || decodedAudioFrames > 0,
      videoRendered: _videoRendered,
      videoDecoder: _videoDecoder,
      outputDimensions: _textureDimensions,
      generation: generation,
      positionMilliseconds: positionMilliseconds,
      bufferedMilliseconds: player.buffered(),
      audioGainDb: audioGainDb,
      directSurface: _directSurface,
    );
  }

  Future<T> _active<T>(Future<T> operation) => Future.any<T>([
    operation,
    _interrupted.future.then<T>((_) => throw StateError('MDK interrupted')),
  ]);

  @override
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    MediaTrack? audioProbe,
    bool isLive = false,
  }) async {
    if (audio != null) {
      // MDK does not forward external-pipeline decoder events. Validate the
      // companion with a muted, sequential probe, then confirm its release
      // before allocating the player used for synchronized playback.
      final probe = _audioProbe = _MdkPlayerPort();
      try {
        final info = await _active(
          probe.prepare(
            audioProbe ?? audio,
            null,
            OpenOptions(volume: 0, maxBufferAhead: options.maxBufferAhead),
            silent: false,
          ),
        );
        if (!info.hasAudio) throw StateError('No companion audio track');
        if (!await _active(probe._audioOpened.future)) {
          throw StateError('Companion audio decoder failed');
        }
        // The probe is about to be released. Retain owned scalars only, not
        // MediaInfo metadata, codec extra-data views or its native handle.
        final codec = probe._player.mediaInfo.audio?.firstOrNull?.codec;
        if (codec != null) {
          _externalAudio = mdk.AudioCodecParameters()
            ..codec = codec.codec
            ..bitRate = codec.bitRate
            ..channels = codec.channels
            ..sampleRate = codec.sampleRate;
        }
      } finally {
        await probe.dispose();
        _audioProbe = null;
      }
      if (!_audioOpened.isCompleted) _audioOpened.complete(true);
    }
    if (_interrupted.isCompleted || _closing) {
      throw StateError('MDK preparation cancelled');
    }
    _initializePlayer();
    _player.videoDecoders = fvpVideoDecoders(
      operatingSystem: Platform.operatingSystem,
      decoding: options.videoDecoding,
      windowsAdapterIndex: windowsAdapterIndex,
    );
    _player.setProperty('subtitle', '0');
    _player.setProperty(
      'avio.headers',
      media.requestPolicy.headers.entries
          .map((entry) => '${entry.key}: ${entry.value}\r\n')
          .join(),
    );
    // The application owns bounded retries and source refreshes.
    _player.setProperty('avio.reconnect', '0');
    _player.setProperty('avio.rw_timeout', '30000000');
    _player.setBufferRange(
      min: options.maxBufferAhead.inMilliseconds.clamp(1, 1000),
      max: options.maxBufferAhead.inMilliseconds.clamp(
        1,
        OpenOptions.maximumBufferAhead.inMilliseconds,
      ),
    );
    setRate(options.rate);
    _startPosition = options.startPosition;
    // External audio can start independently while the video Surface prepares.
    // The engine restores the user's volume only after the shared startup gate.
    setVolume(0, options.audioGainDb);
    _mediaUri = _uri(media.uri);
    _audioUri = audio == null ? null : _uri(audio.uri);
    _silent = silent;
    _player.media = _mediaUri;
    _player.activeSubtitleTracks = const [];
    if (silent) _player.activeAudioTracks = const [];
    final result = await _active(_player.prepare());
    if (_closing || _closed || result < 0) {
      throw StateError('MDK preparation failed');
    }
    if (!await _active(_prepared.future)) {
      throw StateError('MDK tracks did not prepare');
    }
    await _active(_paused.future);
    if (_closing || _closed) throw StateError('MDK preparation cancelled');
    // fvp.prepare stops the current source first. Attach the external pipeline
    // afterwards so preparing the main source cannot interrupt its initial I/O.
    if (audio != null) _player.setMedia(_uri(audio.uri), mdk.MediaType.audio);
    final info = _player.mediaInfo;
    _live = isLive || _player.isLive;
    final video = info.video?.firstOrNull;
    if (video == null && !_live) {
      // Pure audio never enters confirmVideoFrame. Confirm its resume target
      // here, while still paused, before publishing a ready source.
      final position = options.startPosition > Duration.zero
          ? await _active(
              _player.seek(
                position: options.startPosition.inMilliseconds,
                flags: _preciseSeek,
              ),
            )
          : result;
      if (position < 0) throw StateError('MDK audio position did not prepare');
      _preparedAudioPosition = position;
    }
    _directSurface =
        Platform.isAndroid &&
        options.androidVideoOutput == AndroidVideoOutputMode.directTexture &&
        options.videoDecoding == VideoDecodingMode.automatic &&
        video != null &&
        !{
          mdk.ColorSpace.bt2100PQ,
          mdk.ColorSpace.bt2100hlg,
          mdk.ColorSpace.scrgb,
        }.contains(video.codec.colorSpace);
    VideoDimensions? dimensions;
    if (video != null && video.codec.width > 0 && video.codec.height > 0) {
      var width = video.codec.width;
      var height = (video.codec.height / video.codec.par).round();
      if (video.rotation % 180 == 90) (width, height) = (height, width);
      dimensions = VideoDimensions(width, height);
    }
    _dimensions = dimensions;
    return FvpMediaInfo(
      duration: _live || info.duration <= 0
          ? Duration.zero
          : Duration(milliseconds: info.duration),
      dimensions: dimensions,
      hasAudio: audio != null || (!silent && info.audio?.isNotEmpty == true),
      hasVideo: info.video?.isNotEmpty == true,
      directSurface: _directSurface,
    );
  }

  // Keep Android's borrowed descriptor alive until confirmed native disposal.
  String _uri(Uri uri) => switch (uri.scheme) {
    'file' => uri.toFilePath(),
    'fd' => 'fd:${uri.host}',
    _ => uri.toString(),
  };

  @override
  Future<int> createTexture() => _textureCreation = () async {
    final texture = await _player.updateTexture(
      width: _dimensions?.width,
      height: _dimensions?.height,
      fit: false,
    );
    if (!_closing && !_closed && texture >= 0) _textureDimensions = _dimensions;
    return texture;
  }();
  @override
  Future<bool> confirmVideoFrame() async {
    if (_live || Platform.isAndroid) {
      // Android's new cross-process Surface needs the pipeline to advance
      // before it can present the paused prepared frame. Keep this preroll
      // muted and restore the caller's pause intent after confirmation.
      _player.volume = 0;
      _player.state = mdk.PlaybackState.playing;
      try {
        if (_directSurface) {
          return await confirmFvpSurfacePreroll(
            firstFrame: _active(_firstFrame.ready(directSurface: true)),
            pauseAndWait: _pauseAndWait,
            seek: _live
                ? null
                : () => _active(
                    _player.seek(
                      position: _startPosition.inMilliseconds,
                      flags: _preciseSeek,
                    ),
                  ),
          );
        }
        if (!_live) {
          final target = await _active(
            _player.seek(
              position: _startPosition.inMilliseconds,
              flags: _preciseSeek,
            ),
          );
          if (target < 0) return false;
        }
        return await _active(_firstFrame.ready(directSurface: false));
      } finally {
        if (!_closed && !_closing && !_interrupted.isCompleted) {
          await _pauseAndWait();
        }
      }
    }
    final result = await _active(
      _player.seek(
        position: _startPosition.inMilliseconds,
        flags: _preciseSeek,
      ),
    );
    if (result < 0) return false;
    return _active(_firstFrame.ready(directSurface: false));
  }

  Future<void> _pauseAndWait() async {
    _player.state = mdk.PlaybackState.paused;
    while (!_player.waitFor(mdk.PlaybackState.paused, timeout: 0)) {
      await _active(Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  @override
  Future<bool> confirmAudio() async {
    if (!await _active(_audioOpened.future)) return false;
    // A paused probe only confirms decoder initialization. Playing must also
    // confirm frames from this player's real (possibly external) audio pipe.
    while (decodedAudioFrames == 0) {
      if (_ended || _closed || _closing) return false;
      await _active(Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    _audioDecoded = true;
    return true;
  }

  @override
  void play() => _native?.state = mdk.PlaybackState.playing;
  @override
  void pause() {
    // Re-apply even when the main player's cached state is already paused:
    // a newly attached external audio pipeline must receive this request too.
    // Keep EOF stopped so replay can prepare it before requesting a pause.
    if (!_closed && !_ended && !_repreparing) {
      _native?.state = mdk.PlaybackState.paused;
    }
  }

  @override
  Future<void> pauseAndWait() async {
    await pauseAndConfirm();
  }

  @override
  Future<bool> pauseAndConfirm() async {
    if (_closed) return true;
    if (_closing || _ended || _repreparing) return false;
    await _pauseAndWait();
    return !_ended && !_repreparing;
  }

  @override
  void interrupt() {
    final cancelled = _seekCancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete(-2);
    if (!_interrupted.isCompleted) _interrupted.complete();
    _audioProbe?.interrupt();
    if (!_closed && _native != null) {
      // The main video may already be Stopped at premature EOF while external
      // audio survives. Clearing the source also retires that companion pipe.
      _native!.media = '';
      _native!.state = mdk.PlaybackState.stopped;
    }
  }

  @override
  Future<int> seek(Duration target) async {
    final revision = ++_nativeSeekRevision;
    final cancelled = _seekCancelled = Completer<int>();
    var reuseRetirement = _repreparing;
    bool isCancelled() =>
        cancelled.isCompleted || revision != _nativeSeekRevision;
    Future<int> restoreTarget() async {
      _repreparing = true;
      if (!reuseRetirement) {
        _retiringSeek ??= _retireSeek().whenComplete(
          () => _retiringSeek = null,
        );
      }
      await _retiringSeek;
      // A replacement reuses cancelSeek's completed teardown once. A native
      // busy/unloaded reply after prepare needs a fresh teardown of that load.
      reuseRetirement = false;
      if (isCancelled()) return -2;
      _player.media = _mediaUri;
      _player.activeSubtitleTracks = const [];
      if (_silent) _player.activeAudioTracks = const [];
      final result = await _active(
        _player.prepare(position: target.inMilliseconds, flags: _preciseSeek),
      );
      if (isCancelled()) return -2;
      if (result < 0) return result;
      _ended = false;
      if (_audioUri case final audio?) {
        _player.setMedia(audio, mdk.MediaType.audio);
      }
      return result;
    }

    Future<int> prepareTarget() async {
      await _retiringSeek;
      return seekFvpTarget(
        isCancelled: isCancelled,
        needsPrepare: () => _ended || _repreparing,
        prepare: restoreTarget,
        pauseAndWait: () async {
          _player.state = mdk.PlaybackState.paused;
          if (!_directSurface) return true;
          while (!_player.waitFor(mdk.PlaybackState.paused, timeout: 0)) {
            if (isCancelled() ||
                _player.waitFor(mdk.PlaybackState.stopped, timeout: 0)) {
              return false;
            }
            await _active(
              Future<void>.delayed(const Duration(milliseconds: 10)),
            );
          }
          return true;
        },
        seek: () => _active(
          _player.seek(position: target.inMilliseconds, flags: _preciseSeek),
        ),
      );
    }

    try {
      final result = await _active(
        Future.any([prepareTarget(), cancelled.future]),
      );
      if (result >= 0 &&
          revision == _nativeSeekRevision &&
          _dimensions == null) {
        _preparedAudioPosition = result;
      }
      return result;
    } finally {
      if (revision == _nativeSeekRevision) {
        _seekCancelled = null;
        _repreparing = false;
      }
    }
  }

  @override
  void cancelSeek() {
    final cancelled = _seekCancelled;
    if (cancelled == null || cancelled.isCompleted) return;
    ++_nativeSeekRevision;
    _repreparing = true;
    cancelled.complete(-2);
    _retiringSeek ??= _retireSeek().whenComplete(() => _retiringSeek = null);
    // Stop/dispose can supersede the replacement before anyone awaits it.
    unawaited(
      _retiringSeek!.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> _retireSeek() async {
    // Changing media also aborts an in-flight prepare, whose playback state
    // can already be Stopped while its network open is still pending.
    _player.media = '';
    _player.state = mdk.PlaybackState.stopped;
    while (true) {
      if (_closed || _closing || _interrupted.isCompleted) {
        throw StateError('MDK seek retirement cancelled');
      }
      if (_player.waitFor(mdk.PlaybackState.stopped, timeout: 0)) break;
      await _active(Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    // Native teardown has retired its callbacks. Drain queued Dart replies
    // before reusing fvp's single prepare-completion slot.
    await _active(Future<void>.delayed(Duration.zero));
  }

  static const _preciseSeek = mdk.SeekFlag(
    mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache,
  );
  @override
  void setRate(double rate) => _player.playbackRate = rate;
  @override
  void setVolume(double volume, double gainDb) {
    _player.volume = volume / 100;
    // Updating base volume must not rebuild an unchanged MDK audio filter.
    // Restore mute/gain while paused, before the target timeline advances.
    if (_appliedGainDb == gainDb) return;
    _player.setProperty(
      'audio.avfilter',
      gainDb == 0 ? '' : 'volume=${gainDb}dB',
    );
    _appliedGainDb = gainDb;
  }

  @override
  Future<void> dispose() => _disposal ??= _dispose();

  Future<void> _dispose() async {
    if (_closed) return;
    _closing = true;
    interrupt();
    await _audioProbe?.dispose();
    // Own a late CreateRT reply before deleting the native player.
    try {
      await _textureCreation;
    } on Object {
      // Texture creation already reports its failure; release remains required.
    }
    _closed = true;
    await _native?.disposeAsync();
    // Destruction joins MDK's decoder threads. Only then can the observer's
    // opaque state be freed; unregistering alone is not a callback barrier.
    audio_activity.bili_fvp_audio_release(_audioActivity);
    _audioActivity = nullptr;
    await _statusSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _statuses.close();
  }
}
