import 'dart:async';
import 'dart:io';

import 'package:fvp/fvp.dart' as fvp;
import 'package:fvp/mdk.dart' as mdk;

import 'player_contract.dart';

final class FvpMediaInfo {
  const FvpMediaInfo({
    required this.duration,
    this.dimensions,
    required this.hasAudio,
  });
  final Duration duration;
  final VideoDimensions? dimensions;
  final bool hasAudio;
}

enum FvpNativeStatus { buffering, buffered, ended, invalid }

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
  void interrupt();
  Future<int> seek(Duration target);
  void setRate(double rate);
  void setVolume(double volume, double gainDb);
  Future<void> dispose();
}

Future<void>? _initialization;

Future<FvpPlayerPort> createFvpNativePlayer() async {
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
  }());
  return _MdkPlayerPort();
}

final class _MdkPlayerPort implements FvpPlayerPort {
  mdk.Player? _native;
  mdk.Player get _player => _native!;
  _MdkPlayerPort? _audioProbe;
  final _interrupted = Completer<void>();
  final _statuses = StreamController<FvpNativeStatus>.broadcast(sync: true);
  StreamSubscription<Object?>? _statusSubscription;
  StreamSubscription<Object?>? _eventSubscription;
  StreamSubscription<Object?>? _stateSubscription;
  final _audioOpened = Completer<bool>();
  final _firstFrame = Completer<bool>();
  var _prepared = Completer<bool>();
  var _paused = Completer<void>();
  Future<int>? _textureCreation;
  bool _closed = false;
  bool _closing = false;
  bool _live = false;
  bool _ended = false;
  Duration _startPosition = Duration.zero;
  VideoDimensions? _dimensions;
  Future<void>? _disposal;

  void _initializePlayer() {
    _native = mdk.Player();
    _eventSubscription = _player.onEvent.listen((event) {
      if (_closed) return;
      if (event.category == 'decoder.audio' && !_audioOpened.isCompleted) {
        _audioOpened.complete(event.error >= 0);
      }
      if (event.category == 'render.video' &&
          event.detail == '1st_frame' &&
          !_firstFrame.isCompleted) {
        _firstFrame.complete(event.error >= 0);
      }
    });
    _statusSubscription = _player.onMediaStatus.listen((event) {
      if (_closed) return;
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
      if (_closed) return;
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
  int get positionMilliseconds => _closed ? 0 : _native?.position ?? 0;
  @override
  int get bufferedMilliseconds => _closed ? 0 : _native?.buffered() ?? 0;

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
        if (!await _active(probe.confirmAudio())) {
          throw StateError('Companion audio decoder failed');
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
    _player.videoDecoders = options.videoDecoding == VideoDecodingMode.software
        ? ['FFmpeg', 'dav1d']
        : switch (Platform.operatingSystem) {
            'windows' => ['MFT:d3d=11', 'D3D11', 'DXVA', 'FFmpeg', 'dav1d'],
            'android' => ['AMediaCodec', 'FFmpeg', 'dav1d'],
            'macos' || 'ios' => ['VT', 'FFmpeg', 'dav1d'],
            'linux' => ['VAAPI', 'CUDA', 'VDPAU', 'FFmpeg', 'dav1d'],
            _ => ['FFmpeg', 'dav1d'],
          };
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
      max: options.maxBufferAhead.inMilliseconds.clamp(1, 4000),
    );
    setRate(options.rate);
    _startPosition = options.startPosition;
    setVolume(options.volume, options.audioGainDb);
    _player.media = _uri(media.uri);
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
    );
  }

  // Keep Android's borrowed descriptor alive until confirmed native disposal.
  String _uri(Uri uri) => switch (uri.scheme) {
    'file' => uri.toFilePath(),
    'fd' => 'fd:${uri.host}',
    _ => uri.toString(),
  };

  @override
  Future<int> createTexture() => _textureCreation = _player.updateTexture(
    width: _dimensions?.width,
    height: _dimensions?.height,
    fit: false,
  );
  @override
  Future<bool> confirmVideoFrame() async {
    if (_live) {
      // A live source cannot seek to re-present the prepared frame. Advance
      // its pipeline silently until the new texture has rendered one frame.
      final volume = _player.volume;
      _player.volume = 0;
      _player.state = mdk.PlaybackState.playing;
      try {
        return await _active(_firstFrame.future);
      } finally {
        if (!_closed && !_closing && !_interrupted.isCompleted) {
          _player.state = mdk.PlaybackState.paused;
          _player.volume = volume;
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
    return _active(_firstFrame.future);
  }

  @override
  Future<bool> confirmAudio() => _active(_audioOpened.future);
  @override
  void play() => _native?.state = mdk.PlaybackState.playing;
  @override
  void pause() {
    // Re-apply even when the main player's cached state is already paused:
    // a newly attached external audio pipeline must receive this request too.
    // Keep EOF stopped so replay can prepare it before requesting a pause.
    if (!_closed && !_ended) {
      _native?.state = mdk.PlaybackState.paused;
    }
  }

  @override
  void interrupt() {
    if (!_interrupted.isCompleted) _interrupted.complete();
    _audioProbe?.interrupt();
    if (!_closed) _native?.state = mdk.PlaybackState.stopped;
  }

  @override
  Future<int> seek(Duration target) async {
    // MDK releases the decoding pipelines on EOF. A stopped source must be
    // prepared again; seek alone fails and leaves the old end position intact.
    if (_ended) {
      _prepared = Completer<bool>();
      _paused = Completer<void>();
      final position = await _active(
        _player.prepare(position: target.inMilliseconds, flags: _preciseSeek),
      );
      if (position < 0) return position;
      if (!await _active(_prepared.future)) return -1;
      await _active(_paused.future);
      _ended = false;
    }
    // At zero prepare only confirms loading. Seek also waits for its decoded
    // target frame, preserving the same readiness barrier as ordinary seeks.
    return _active(
      _player.seek(position: target.inMilliseconds, flags: _preciseSeek),
    );
  }

  static const _preciseSeek = mdk.SeekFlag(
    mdk.SeekFlag.fromStart | mdk.SeekFlag.inCache,
  );
  @override
  void setRate(double rate) => _player.playbackRate = rate;
  @override
  void setVolume(double volume, double gainDb) {
    _player.volume = volume / 100;
    _player.setProperty(
      'audio.avfilter',
      gainDb == 0 ? '' : 'volume=${gainDb}dB',
    );
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
    await _statusSubscription?.cancel();
    await _eventSubscription?.cancel();
    await _stateSubscription?.cancel();
    await _statuses.close();
  }
}
