import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'dolby_audio_output.dart';
import 'native_hdr_output.dart';
import 'native_readiness.dart';
import 'playback_backend.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'validated_source.dart';
import 'video_composition.dart';

/// Tries the platform Dolby decoder while paused. The shared engine owns the
/// sole timeline and falls back to mpv after a rejected player is released.
final class AndroidDolbyBackend
    implements PlaybackBackend, FlutterVideoOutput, VideoFrameReadiness {
  AndroidDolbyBackend._(this._generation);
  static const _channel = MethodChannel('bilisail/dolby_player');
  static int _nextId = 0;
  final int _id = ++_nextId;
  final int _generation;
  final _events = StreamController<BackendEvent>.broadcast();
  final _frame = ValueNotifier(false);
  Map<Object?, Object?> _state = const {};
  Timer? _samples;
  bool _closed = false, _polling = false;
  int _seek = 0;
  Future<void>? _release;

  static bool candidate(ValidatedSource plan) {
    if (plan.silent ||
        plan.live ||
        plan.options.audioGainDb != 0 ||
        (!plan.audioOnly &&
            plan.options.videoDecoding == VideoDecodingMode.software)) {
      return false;
    }
    final track = plan.audio ?? plan.media;
    if (plan.source is ProgressiveSource && track.embeddedAudioCodec != null) {
      return isDolbyDigitalPlus(track.embeddedAudioCodec);
    }
    if (plan.audioOnly) return isDolbyDigitalPlus(track.codec);
    return isDolbyDigitalPlus(track.codec) ||
        (plan.source is ProgressiveSource &&
            (track.uri.scheme == 'file' || track.uri.scheme == 'content'));
  }

  static Future<PlaybackBackend?> tryOpen(
    ValidatedSource plan,
    PlaybackOperation operation,
  ) async {
    if (!candidate(plan)) return null;
    final backend = AndroidDolbyBackend._(operation.generation);
    var accepted = false;
    try {
      // Reserve the rest of the shared opening budget for the ordinary player.
      final deadline = operation.remaining ~/ 3;
      final clock = Stopwatch()..start();
      await operation.wait(
        backend._command('open', {
          'media': plan.media.uri.toString(),
          'audio': plan.audio?.uri.toString(),
          'headers': plan.media.requestPolicy.headers,
          'position': plan.options.startPosition.inMilliseconds,
          'volume': plan.options.volume,
          'bufferMs': plan.options.maxBufferAhead.inMilliseconds,
        }),
      );
      while (clock.elapsed < deadline &&
          clock.elapsed < const Duration(seconds: 8)) {
        await operation.wait(backend._sample());
        if (backend._state['failed'] == true) return null;
        if (backend._state['ready'] == true &&
            backend._state['audio'] == 'audio/eac3-joc' &&
            backend._state['dolbyRenderer'] == true &&
            (plan.audioOnly || !plan.requiresVideo || backend._frame.value) &&
            (backend._state['video'] == null || backend._frame.value) &&
            (!plan.audioOnly || backend._state['video'] == null)) {
          accepted = true;
          return backend;
        }
        await operation.wait(
          Future<void>.delayed(const Duration(milliseconds: 50)),
        );
      }
      return null;
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } finally {
      if (!accepted) await backend.dispose();
    }
  }

  Future<void> _command(
    String method, [
    Map<String, Object?> args = const {},
  ]) => _channel.invokeMethod<void>(method, {'id': _id, ...args});
  Future<void> _sample() async {
    final state = await _channel.invokeMapMethod<Object?, Object?>('state', {
      'id': _id,
    });
    if (_closed) return;
    _state = state ?? const {'failed': true};
    _frame.value = _state['frame'] == true;
  }

  int _number(String key) => (_state[key] as int?) ?? 0;
  Duration _time(String key) => Duration(milliseconds: _number(key));
  VideoDimensions? get _dimensions =>
      _number('width') > 0 && _number('height') > 0
      ? VideoDimensions(_number('width'), _number('height'))
      : null;
  Future<void> _tick() async {
    if (_polling || _closed) return;
    _polling = true;
    try {
      await _sample();
      if (_closed) return;
      if (_state['failed'] == true) {
        _samples?.cancel();
        _events.add(const BackendEvent(BackendEventKind.failure));
        return;
      }
      _events.add(
        BackendEvent(
          BackendEventKind.sample,
          position: _time('position'),
          duration: _time('duration'),
          buffered: buffered,
          dimensions: _dimensions,
        ),
      );
      _events.add(
        BackendEvent(
          BackendEventKind.buffering,
          value: _state['buffering'] == true,
        ),
      );
      if (_state['ended'] == true) {
        _events.add(
          BackendEvent(BackendEventKind.ended, position: _time('position')),
        );
      }
    } on PlatformException {
      if (!_closed) _events.add(const BackendEvent(BackendEventKind.failure));
    } finally {
      _polling = false;
    }
  }

  @override
  Future<PreparedTracks> prepare(
    ValidatedSource plan,
    PlaybackOperation operation, {
    Future<void> Function()? onLiveLoaded,
  }) async {
    operation.check();
    _samples = Timer.periodic(
      const Duration(milliseconds: 200),
      (_) => _tick(),
    );
    return PreparedTracks(
      hasVideo: _dimensions != null,
      hasAudio: true,
      externalAudioSelected: plan.audio != null,
      duration: _time('duration'),
      position: _time('position'),
      dimensions: _dimensions,
    );
  }

  @override
  Future<VideoDimensions?> confirmVideo(PlaybackOperation operation) async =>
      _dimensions;
  @override
  Future<void> confirmAudio(PlaybackOperation operation) async {
    operation.check();
    // Media3 can defer creating AudioTrack until play. A prepared, selected
    // platform renderer is sufficient for paused startup.
    if (_state['audio'] != 'audio/eac3-joc') {
      throw StateError('Dolby track missing');
    }
  }

  @override
  Future<void> confirmPresentation(PlaybackOperation operation) async {
    operation.check();
  }

  @override
  Duration get seekTimeout => const Duration(seconds: 12);
  @override
  Future<Duration> seekTo(Duration target, PlaybackOperation operation) async {
    final revision = ++_seek;
    final duration = _time('duration');
    if (duration > Duration.zero && target > duration) target = duration;
    await operation.wait(_command('seek', {'value': target.inMilliseconds}));
    while (true) {
      operation.check();
      if (_closed || revision != _seek) throw const SourceSuperseded();
      await operation.wait(_sample());
      if (_state['failed'] == true) throw StateError('Platform seek failed');
      if ((_state['ready'] == true || _state['ended'] == true) &&
          (_time('position') - target).abs() <
              const Duration(milliseconds: 250)) {
        return _time('position');
      }
      await operation.wait(
        Future<void>.delayed(const Duration(milliseconds: 30)),
      );
    }
  }

  @override
  Future<void> cancelSeek() async {
    ++_seek;
  }

  @override
  Future<void> play() => _command('play');
  @override
  Future<bool> pauseAndWait() async {
    await _command('pause');
    return true;
  }

  @override
  Future<void> setRate(double rate) => _command('rate', {'value': rate});
  @override
  Future<void> setVolume(double volume) =>
      _command('volume', {'value': volume / 100});
  @override
  Future<void> setGainDb(double gainDb) => _command('gain', {'value': gainDb});
  @override
  Duration get buffered => _time('buffered');
  @override
  Stream<BackendEvent> get events => _events.stream;
  PlayerDiagnostics get diagnostics => PlayerDiagnostics(
    generation: _generation,
    position: _time('position'),
    hasDecodedVideo: _frame.value,
    hasDecodedAudio: _state['audioDecoder'] != null,
    hasVideoOutput: _frame.value,
    videoWidth: _dimensions?.width,
    videoHeight: _dimensions?.height,
    audioChannels: _state['channels'] as int?,
    audioSampleRate: _state['sampleRate'] as int?,
    audioCodec: _state['audio'] as String?,
    videoCodec: _state['video'] as String?,
  );
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation(
    int generation,
  ) async {
    return PlayerPlaybackInformation(
      generation: generation,
      backend: 'Android Media3',
      diagnostics: diagnostics,
      audioCodec: _state['audio'] as String?,
      videoCodec: _state['video'] as String?,
      hardwareDecoder: _state['videoDecoder'] as String?,
      atmosSource: _state['audio'] == 'audio/eac3-joc',
      audioDecoder: _state['audioDecoder'] as String?,
      audioOutput: 'AudioTrack',
      audioOutputFormat: _state['output'] as String?,
      audioGainDb: (_state['gain'] as num?)?.toDouble(),
    );
  }

  @override
  FlutterVideoOutput get videoOutput => this;
  @override
  ValueListenable<bool> get frameReady => _frame;
  @override
  Widget buildVideoSurface() {
    final id = _state['surface'] as int?;
    final dimensions = _dimensions;
    if (id == null || dimensions == null) return const SizedBox.shrink();
    return Center(
      child: AspectRatio(
        aspectRatio: dimensions.width / dimensions.height,
        child: buildAndroidDecoderSurface(id),
      ),
    );
  }

  @override
  void attach(Object owner) {}
  @override
  void detach(Object owner) {}
  @override
  void updateViewport(
    Object owner, {
    required double logicalWidth,
    required double logicalHeight,
    required double devicePixelRatio,
  }) {}
  @override
  void interrupt() {
    ++_seek;
    _samples?.cancel();
    if (!_closed) unawaited(_command('pause').catchError((Object _) {}));
  }

  @override
  Future<void> dispose() => _release ??= _dispose();
  Future<void> _dispose() async {
    _closed = true;
    _samples?.cancel();
    try {
      await _command('release');
    } on MissingPluginException {
      // Older Android versions have no registered native Dolby player.
    } finally {
      await _events.close();
      _frame.dispose();
    }
  }
}
