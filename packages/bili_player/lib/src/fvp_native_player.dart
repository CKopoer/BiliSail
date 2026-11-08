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

enum FvpNativeStatus {
  buffering,
  buffered,
  ended,
  audioEnded,
  invalid,
  processExited,
}

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
    bool isLive = false,
  });
  Future<int> createTexture();
  Future<bool> confirmVideoFrame();
  Future<bool> confirmAudio();
  void play();
  void pause();
  Future<void> pauseAndWait();
  void interrupt();
  // Completes after the video and companion audio targets are ready.
  Future<int> seek(Duration target);
  // Retires in-flight preparation; the next seek restores this source.
  Future<void> cancelSeek();
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

abstract interface class FvpAudioClockPort {
  int? get audioPositionMilliseconds;
}

/// IPC acknowledgement for commands used by playback barriers.
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
        FvpAudioClockPort,
        FvpPauseConfirmationPort {
  _MdkPlayerPort({this.windowsAdapterIndex, this.audioOnly = false});

  final int? windowsAdapterIndex;
  final bool audioOnly;
  mdk.Player? _native;
  mdk.Player get _player => _native!;
  _MdkPlayerPort? _audioCompanion;
  StreamSubscription<FvpNativeStatus>? _audioSubscription;
  Pointer<Void> _audioClock = nullptr;
  int _durationMilliseconds = 0;
  bool _videoBuffering = false, _audioBuffering = false;
  final _playingClock = Stopwatch();
  double _rate = 1;
  int _audioReadyPosition = 0;
  bool _audioTargetReady = false;

  @override
  int? get audioPositionMilliseconds =>
      _audioCompanion?.positionMilliseconds ??
      (!_silent ? positionMilliseconds : null);
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
  mdk.PlaybackState _observedState = mdk.PlaybackState.stopped;
  Duration _startPosition = Duration.zero;
  int? _preparedAudioPosition;
  VideoDimensions? _dimensions;
  Future<void>? _disposal;
  Completer<int>? _seekCancelled;
  Future<void>? _retiringSeek;
  bool _repreparing = false;
  int _nativeSeekRevision = 0;
  String _mediaUri = '';
  bool _silent = false;
  bool _primingDirectSurface = false;
  bool _mutedAudioSeek = false;
  double _volume = 100;
  bool get _needsAudioSeekPlayback => audioOnly && Platform.isAndroid;
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
      _audioCompanion?.decodedAudioFrames ??
      audio_activity.bili_fvp_audio_frames(_audioActivity);

  void _buffering(bool value, {bool audio = false}) {
    if (audio) {
      _audioBuffering = value;
    } else {
      _videoBuffering = value;
    }
    _statuses.add(
      _audioBuffering || _videoBuffering
          ? FvpNativeStatus.buffering
          : FvpNativeStatus.buffered,
    );
  }

  void _companionStatus(FvpNativeStatus status) {
    if (_closed || _closing || _repreparing || _seekCancelled != null) return;
    switch (status) {
      case FvpNativeStatus.buffering:
        _buffering(true, audio: true);
      case FvpNativeStatus.buffered:
        _buffering(false, audio: true);
      case FvpNativeStatus.invalid ||
          FvpNativeStatus.processExited ||
          FvpNativeStatus.audioEnded:
        _statuses.add(status);
      case FvpNativeStatus.ended:
        // MDK may reset audio.position to zero as the output reaches EOS.
        // The still displayed video frame confirms a natural paired ending.
        final audioPosition = _audioCompanion?.positionMilliseconds ?? 0;
        final videoPosition = _native?.position ?? 0;
        final position = audioPosition > videoPosition
            ? audioPosition
            : videoPosition;
        if (_durationMilliseconds - position > 500) {
          _statuses.add(FvpNativeStatus.audioEnded);
        } else {
          // Natural audio EOS has no further clock ticks. Drain only the
          // paired final video frame, instead of waiting on a reset AO clock.
          _holdClock(_durationMilliseconds);
        }
    }
  }

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
      if (_closed || _repreparing || _seekCancelled != null) return;
      final status = event.newValue;
      if (status.test(mdk.MediaStatus.invalid)) {
        if (!_prepared.isCompleted) _prepared.complete(false);
        _statuses.add(FvpNativeStatus.invalid);
      } else if (status.test(
        mdk.MediaStatus.buffering | mdk.MediaStatus.stalled,
      )) {
        _buffering(true);
      } else if (status.test(mdk.MediaStatus.buffered)) {
        _buffering(false);
      }
      if (status.test(mdk.MediaStatus.prepared) && !_prepared.isCompleted) {
        _prepared.complete(true);
      }
    });
    _stateSubscription = _player.onStateChanged.listen((event) {
      if (_closed) return;
      _observedState = event.newValue;
      if (_repreparing) return;
      if (event.newValue == mdk.PlaybackState.paused && !_paused.isCompleted) {
        _paused.complete();
      }
      if (event.newValue == mdk.PlaybackState.stopped &&
          event.oldValue != mdk.PlaybackState.stopped) {
        // Demux EOF can precede completion while decoded data remains buffered.
        _ended = _player.mediaStatus.test(mdk.MediaStatus.end);
        // Keep the native EOF fact even while the shared engine ignores seek
        // events. Otherwise the next pause can wait forever on an EOF player.
        if (_seekCancelled != null) return;
        if (_ended) _audioCompanion?.pause();
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
    if (prepared != null) {
      if (!_playingClock.isRunning ||
          position == 0 && prepared > 0 ||
          (position - prepared).abs() >
              500 + _playingClock.elapsedMilliseconds * _rate) {
        return prepared;
      }
    }
    _preparedAudioPosition = null;
    return position;
  }

  @override
  int get bufferedMilliseconds {
    if (_closed) return 0;
    final video = _native?.buffered() ?? 0;
    final audio = _audioCompanion?.bufferedMilliseconds;
    return audio != null && audio < video ? audio : video;
  }

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
      bufferedMilliseconds: bufferedMilliseconds,
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
    bool isLive = false,
  }) async {
    if (audio != null) {
      // Keep a real paused audio player. Both native targets are decoded before
      // play, and video follows this player's native audio presentation clock.
      final companion = _audioCompanion = _MdkPlayerPort(audioOnly: true);
      final info = await _active(
        companion.prepare(audio, null, options, silent: false),
      );
      if (!info.hasAudio) throw StateError('No companion audio track');
      if (!await _active(companion._audioOpened.future)) {
        throw StateError('Companion audio decoder failed');
      }
      final codec = companion._player.mediaInfo.audio?.firstOrNull?.codec;
      if (codec != null) {
        _externalAudio = mdk.AudioCodecParameters()
          ..codec = codec.codec
          ..bitRate = codec.bitRate
          ..channels = codec.channels
          ..sampleRate = codec.sampleRate;
      }
      _audioSubscription = companion.statuses.listen(_companionStatus);
      if (!_audioOpened.isCompleted) _audioOpened.complete(true);
    }
    if (_interrupted.isCompleted || _closing) {
      throw StateError('MDK preparation cancelled');
    }
    _initializePlayer();
    // Android's Surface is bound after prepare. Its replacement decoder must
    // submit an image before the paused audio clock can become video master.
    if (!Platform.isAndroid) _connectAudioClock();
    _holdClock(options.startPosition.inMilliseconds);
    _audioReadyPosition = options.startPosition.inMilliseconds;
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
    // Both real pipelines prepare while paused at the user's selected volume.
    setVolume(options.volume, options.audioGainDb);
    _mediaUri = _uri(media.uri);
    _silent = silent;
    _player.media = _mediaUri;
    _player.activeSubtitleTracks = const [];
    if (_silent || _audioCompanion != null) {
      _player.activeAudioTracks = const [];
    }
    if (audioOnly) _player.activeVideoTracks = const [];
    final result = await _active(_player.prepare());
    if (_closing || _closed || result < 0) {
      throw StateError('MDK preparation failed');
    }
    if (!await _active(_prepared.future)) {
      throw StateError('MDK tracks did not prepare');
    }
    await _active(_paused.future);
    if (_closing || _closed) throw StateError('MDK preparation cancelled');
    final info = _player.mediaInfo;
    _live = isLive || _player.isLive;
    _durationMilliseconds = info.duration;
    final video = info.video?.firstOrNull;
    if ((video == null || audioOnly) && !_live) {
      // Pure audio never enters confirmVideoFrame. Confirm its resume target
      // here, while still paused, before publishing a ready source.
      final position = await _active(
        _player.seek(
          position: options.startPosition.inMilliseconds,
          flags: _preciseSeek,
        ),
      );
      if (position < 0) throw StateError('MDK audio position did not prepare');
      _preparedAudioPosition = position;
      _audioTargetReady = true;
      _audioDecoded = true;
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
    if (!audioOnly &&
        video != null &&
        video.codec.width > 0 &&
        video.codec.height > 0) {
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
      hasVideo: !audioOnly && info.video?.isNotEmpty == true,
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
    if (_directSurface) {
      void checkActive() {
        if (_closing || _closed || _interrupted.isCompleted) {
          throw StateError('MDK preparation cancelled');
        }
      }

      _primingDirectSurface = true;
      // DASH video has no active audio track. A progressive source can contain
      // embedded audio; keep that native output silent during Surface setup.
      if (_audioCompanion == null) _player.volume = 0;
      try {
        final ready = await confirmFvpDirectSurface(
          // Do not call play(): the companion and its clock must stay paused.
          startVideo: () => _player.state = mdk.PlaybackState.playing,
          firstFrame: () => _active(_firstFrame.ready(directSurface: true)),
          pauseAndWait: () async {
            if (!_closing && !_closed && !_interrupted.isCompleted) {
              await _pauseAndWait();
            }
          },
          checkActive: checkActive,
          seek: _live
              ? null
              : () => _active(
                  _player.seek(
                    position: _startPosition.inMilliseconds,
                    flags: _preciseSeek,
                  ),
                ),
        );
        if (!ready) return false;
      } finally {
        _primingDirectSurface = false;
        if (!_closing && !_closed && !_interrupted.isCompleted) {
          _player.volume = _volume / 100;
        }
      }
      _connectAudioClock();
      _holdClock(_startPosition.inMilliseconds);
      return true;
    }
    _connectAudioClock();
    _holdClock(_startPosition.inMilliseconds);
    // Live has no network seek. Decode the first already buffered target
    // while paused, without advancing the live clock to obtain a frame.
    final result = await _active(
      _player.seek(
        position: _live ? 0 : _startPosition.inMilliseconds,
        flags: _live
            ? const mdk.SeekFlag(mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache)
            : _preciseSeek,
      ),
    );
    if (result < 0) return false;
    return _active(_firstFrame.ready(directSurface: _directSurface));
  }

  void _connectAudioClock() {
    if (_audioClock != nullptr) return;
    if (_audioCompanion case final companion?) {
      _audioClock = audio_activity.bili_fvp_audio_clock(
        _player.nativeHandle,
        companion._player.nativeHandle,
      );
      if (_audioClock == nullptr) {
        throw StateError('Audio master clock unavailable');
      }
    }
  }

  Future<void> _pauseAndWait() async {
    _player.state = mdk.PlaybackState.paused;
    while (!_player.waitFor(mdk.PlaybackState.paused, timeout: 0)) {
      // waitFor(Stopped) can join native I/O even with a zero timeout. Keep
      // normal pause polling on Paused and use the asynchronous EOF evidence.
      if (_ended ||
          _repreparing ||
          _observedState == mdk.PlaybackState.stopped &&
              _player.mediaStatus.test(mdk.MediaStatus.end)) {
        _ended = _player.mediaStatus.test(mdk.MediaStatus.end);
        return;
      }
      await _active(Future<void>.delayed(const Duration(milliseconds: 10)));
    }
  }

  @override
  Future<bool> confirmAudio() async {
    var revision = _nativeSeekRevision;
    if (_audioCompanion case final companion?) {
      final ready = await _active(companion.confirmAudio());
      if (revision != _nativeSeekRevision || _repreparing) return false;
      _audioDecoded = ready;
      return ready;
    }
    if (!await _active(_audioOpened.future)) return false;
    if (revision != _nativeSeekRevision ||
        _repreparing ||
        _closed ||
        _closing ||
        _ended) {
      return false;
    }
    final target = positionMilliseconds;
    if (!_live &&
        _dimensions == null &&
        (!_audioTargetReady || (target - _audioReadyPosition).abs() > 100)) {
      final seeking = seek(Duration(milliseconds: target));
      revision = _nativeSeekRevision;
      if (await seeking < 0 || revision != _nativeSeekRevision) return false;
    }
    while (!_player.mediaStatus.test(mdk.MediaStatus.prepared) ||
        (!_live && _dimensions == null && !_audioTargetReady)) {
      if (_ended ||
          _closed ||
          _closing ||
          _repreparing ||
          revision != _nativeSeekRevision) {
        return false;
      }
      await _active(Future<void>.delayed(const Duration(milliseconds: 10)));
    }
    if (revision != _nativeSeekRevision) return false;
    _audioDecoded = true;
    return true;
  }

  @override
  void play() {
    _audioCompanion?.play();
    audio_activity.bili_fvp_audio_clock_play(_audioClock);
    _playingClock
      ..reset()
      ..start();
    _native?.state = mdk.PlaybackState.playing;
  }

  void _holdClock(int position) =>
      audio_activity.bili_fvp_audio_clock_hold(_audioClock, position);
  @override
  void pause() {
    if (_dimensions == null && _native != null) {
      _preparedAudioPosition = positionMilliseconds;
    }
    _playingClock.stop();
    _audioCompanion?.pause();
    if (_seekCancelled == null) {
      _holdClock(_audioCompanion?.positionMilliseconds ?? positionMilliseconds);
    }
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
    if (_audioCompanion case final companion?) {
      if (!await companion.pauseAndConfirm()) return false;
      if (_seekCancelled == null) _holdClock(companion.positionMilliseconds);
    }
    await _pauseAndWait();
    return !_ended && !_repreparing;
  }

  @override
  void interrupt() {
    _holdClock(_audioCompanion?.positionMilliseconds ?? positionMilliseconds);
    final cancelled = _seekCancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete(-2);
    if (!_interrupted.isCompleted) _interrupted.complete();
    _audioCompanion?.interrupt();
    if (!_closed && _native != null) {
      // Clear the video source as well as retiring the audio companion.
      _native!.media = '';
      _native!.state = mdk.PlaybackState.stopped;
    }
  }

  @override
  Future<int> seek(Duration target) async {
    final forward = target.inMilliseconds - positionMilliseconds;
    final flags =
        !_ended &&
            !_repreparing &&
            forward > 0 &&
            forward <= bufferedMilliseconds
        ? const mdk.SeekFlag(mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache)
        : _preciseSeek;
    final revision = ++_nativeSeekRevision;
    final cancelled = _seekCancelled = Completer<int>();
    // Freeze the old timeline until video acknowledges pause. Moving its master
    // to a backward target before that acknowledgement can strand an old frame.
    if (!_repreparing) {
      _holdClock(_audioCompanion?.positionMilliseconds ?? positionMilliseconds);
    }
    _audioCompanion?.pause();
    _playingClock.stop();
    _audioReadyPosition = target.inMilliseconds;
    _audioTargetReady = false;
    var reuseRetirement = _repreparing;
    int? confirmedPosition;
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
      audio_activity.bili_fvp_audio_clock_seek(_audioClock);
      _player.media = _mediaUri;
      _player.activeSubtitleTracks = const [];
      if (_silent || _audioCompanion != null) {
        _player.activeAudioTracks = const [];
      }
      final result = await _active(
        _player.prepare(position: target.inMilliseconds, flags: _preciseSeek),
      );
      if (isCancelled()) return -2;
      if (result < 0) return result;
      _ended = false;
      return result;
    }

    Future<bool> pauseTarget() async {
      _player.state = mdk.PlaybackState.paused;
      while (!_player.waitFor(mdk.PlaybackState.paused, timeout: 0)) {
        if (isCancelled() || _observedState == mdk.PlaybackState.stopped) {
          return false;
        }
        await _active(Future<void>.delayed(const Duration(milliseconds: 10)));
      }
      return true;
    }

    Future<int> prepareTarget() async {
      await _retiringSeek;
      return seekFvpTarget(
        isCancelled: isCancelled,
        needsPrepare: () => _ended || _repreparing,
        prepare: restoreTarget,
        pauseAndWait: pauseTarget,
        seek: () {
          audio_activity.bili_fvp_audio_clock_seek(_audioClock);
          Future<int> decodeTarget() => _active(
            _player.seek(position: target.inMilliseconds, flags: flags),
          );
          if (!_needsAudioSeekPlayback) return decodeTarget();
          return seekFvpAudioTarget(
            isCancelled: isCancelled,
            setMuted: (muted) {
              _mutedAudioSeek = muted;
              _player.volume = muted ? 0 : _volume / 100;
            },
            playAndWait: () async {
              _player.state = mdk.PlaybackState.playing;
              while (!_player.waitFor(mdk.PlaybackState.playing, timeout: 0)) {
                if (isCancelled()) return;
                await _active(
                  Future<void>.delayed(const Duration(milliseconds: 10)),
                );
              }
            },
            seek: decodeTarget,
            pauseAndConfirm: pauseTarget,
          );
        },
      );
    }

    try {
      final result = await _active(
        Future.any([prepareTarget(), cancelled.future]),
      );
      final audio = _audioCompanion;
      if (result >= 0 && !isCancelled() && audio != null) {
        final audioResult = await _active(
          Future.any([
            audio.seek(Duration(milliseconds: result)),
            cancelled.future,
          ]),
        );
        if (audioResult < 0 || isCancelled()) return audioResult;
        if ((audioResult - result).abs() > 100) return -8;
        if (!await _active(
          Future.any([
            audio.confirmAudio(),
            cancelled.future.then((_) => false),
          ]),
        )) {
          return isCancelled() ? -2 : -8;
        }
      }
      if (isCancelled()) return -2;
      if (result >= 0) confirmedPosition = result;
      if (result >= 0 &&
          revision == _nativeSeekRevision &&
          _dimensions == null) {
        _preparedAudioPosition = result;
        _audioTargetReady = true;
        _audioDecoded = true;
      }

      return result;
    } finally {
      if (revision == _nativeSeekRevision) {
        // Only this seek may end its clock override. A retired callback cannot
        // freeze the replacement at an old target or release its audio early.
        _holdClock(
          confirmedPosition ??
              _audioCompanion?.positionMilliseconds ??
              _audioReadyPosition,
        );
        _seekCancelled = null;
        _repreparing = false;
        if (!_closed && !_closing) {
          _audioBuffering =
              _audioCompanion?._player.mediaStatus.test(
                mdk.MediaStatus.buffering | mdk.MediaStatus.stalled,
              ) ??
              false;
          _buffering(
            _player.mediaStatus.test(
              mdk.MediaStatus.buffering | mdk.MediaStatus.stalled,
            ),
          );
        }
      }
    }
  }

  @override
  Future<void> cancelSeek() => _cancelSeek();

  Future<void> _cancelSeek({bool retire = false}) async {
    final cancelled = _seekCancelled;
    if (!retire && (cancelled == null || cancelled.isCompleted)) return;
    if (_native == null || _closed || _closing) return;
    ++_nativeSeekRevision;
    _repreparing = true;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete(-2);
    _retiringSeek ??= _retireSeek().whenComplete(() => _retiringSeek = null);
    // Stop/dispose can supersede the replacement before anyone awaits it.
    unawaited(
      _retiringSeek!.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
    await Future.wait([
      _retiringSeek!,
      // Shared transport cancellation retires both tracks' HTTP readers. The
      // audio demuxer must stop even if video has not reached its seek yet.
      if (_audioCompanion case final audio?) audio._cancelSeek(retire: true),
    ]);
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

  // Preparation, backward and uncached seeks use ordinary precise demux seek.
  static const _preciseSeek = mdk.SeekFlag(mdk.SeekFlag.fromStart);
  @override
  void setRate(double rate) {
    _rate = rate;
    _audioCompanion?.setRate(rate);
    _player.playbackRate = rate;
  }

  @override
  void setVolume(double volume, double gainDb) {
    _volume = volume;
    _audioCompanion?.setVolume(volume, gainDb);
    _player.volume =
        _primingDirectSurface && _audioCompanion == null || _mutedAudioSeek
        ? 0
        : volume / 100;
    // Updating base volume must not rebuild an unchanged MDK audio filter.
    // Apply gain while paused, before the target timeline advances.
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

    // Own a late CreateRT reply before deleting the native player.
    try {
      await _textureCreation;
    } on Object {
      // Texture creation already reports its failure; release remains required.
    }
    _closed = true;
    await _native?.disposeAsync();
    audio_activity.bili_fvp_audio_clock_release(_audioClock);
    _audioClock = nullptr;
    await _audioSubscription?.cancel();
    await _audioCompanion?.dispose();
    _audioCompanion = null;
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
