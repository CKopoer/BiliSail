import 'dart:async';
import 'dart:convert';

import 'player_contract.dart';
import 'player_diagnostics.dart';

/// A bounded event-triggered sample, not a continuous playback polling loop.
Future<NativePlaybackState> sampleNativeBufferingState(
  Future<String?> Function(String) read,
) async {
  const names = [
    'core-idle',
    'paused-for-cache',
    'demuxer-cache-state',
    'cache-speed',
    'demuxer-cache-duration',
    'audio-pts',
    'time-pos',
    'avsync',
    'frame-drop-count',
    'decoder-frame-drop-count',
    'hwdec-current',
    'video-format',
    'audio-codec-name',
  ];
  final values = await Future.wait([
    for (final name in names)
      () async {
        try {
          final value = await read(name)
              .timeout(const Duration(milliseconds: 400));
          return value != null && value.length <= 16384 ? value : null;
        } on Object {
          return null;
        }
      }(),
  ]);
  final data = Map.fromIterables(names, values);
  bool? flag(String name) => switch (data[name]) {
    'yes' => true,
    'no' => false,
    _ => null,
  };
  int? number(String name, {double scale = 1, bool signed = false}) {
    final value = double.tryParse(data[name] ?? '');
    if (value == null ||
        !value.isFinite ||
        value.abs() > 1e12 ||
        (!signed && value < 0)) {
      return null;
    }
    return (value * scale).round();
  }

  bool? reading, eof;
  int? bytes;
  try {
    final Object? cache = jsonDecode(data['demuxer-cache-state'] ?? 'null');
    if (cache is Map<String, Object?>) {
      if (cache['idle'] case final bool idle) reading = !idle;
      if (cache['eof'] case final bool value) eof = value;
      if (cache['fw-bytes'] case final num value
          when value.isFinite && value >= 0 && value <= 1e12) {
        bytes = value.toInt();
      }
    }
  } on FormatException {
    // Unsupported/unavailable properties are unknown, never a zero measurement.
  }
  final decoder = data['hwdec-current'];
  final video = data['video-format'];
  final audio = data['audio-codec-name'];
  return NativePlaybackState(
    coreIdle: flag('core-idle'),
    pausedForCache: flag('paused-for-cache'),
    cacheReading: reading,
    cacheEof: eof,
    cacheBytes: bytes,
    cacheSpeed: number('cache-speed'),
    cacheDurationMs: number('demuxer-cache-duration', scale: 1000),
    audioPositionMs: number('audio-pts', scale: 1000),
    nativePositionMs: number('time-pos', scale: 1000),
    avSyncMs: number('avsync', scale: 1000, signed: true),
    frameDrops: number('frame-drop-count'),
    decoderDrops: number('decoder-frame-drop-count'),
    hardwareDecoder: NativePlaybackState.hardwareDecoders.contains(decoder)
        ? decoder
        : null,
    videoCodec: NativePlaybackState.videoCodecs.contains(video) ? video : null,
    audioCodec: NativePlaybackState.audioCodecs.contains(audio) ? audio : null,
  );
}

/// At most one native batch, including reads that outlive their Dart timeout.
final class NativePlaybackSampler {
  NativePlaybackSampler(this.read);
  final Future<String?> Function(String) read;
  Future<NativePlaybackState?>? _current;
  int _pendingReads = 0;

  Future<NativePlaybackState?> sample() {
    if (_current case final current?) return current;
    if (_pendingReads != 0) return Future.value();
    final result = sampleNativeBufferingState((name) async {
      _pendingReads++;
      try {
        return await read(name);
      } finally {
        _pendingReads--;
      }
    });
    _current = result;
    unawaited(result.then<void>((_) => _current = null));
    return result;
  }
}

final class NativeBufferingDiagnostics {
  NativeBufferingDiagnostics({
    required Future<String?> Function(String) read,
    required this.snapshot,
    required this.isCurrent,
    required this.emit,
    NativePlaybackSampler? sampler,
  }) : _sampler = sampler ?? NativePlaybackSampler(read);
  final NativePlaybackSampler _sampler;
  final PlaybackSnapshot Function() snapshot;
  final bool Function() isCurrent;
  final void Function(PlayerDiagnosticEvent) emit;
  final _clock = Stopwatch()..start();
  Timer? _timer;
  Duration? _startedAt, _lastSample;
  bool _logged = false, _sampling = false, _disposed = false;

  bool get _active => !_disposed && isCurrent();
  bool get _playing =>
      snapshot().desiredPlaying &&
      !snapshot().isSeeking &&
      const {
        PlaybackPhase.playing,
        PlaybackPhase.buffering,
      }.contains(snapshot().phase);

  void sourceReady() {
    capture(force: true);
    bufferingChanged(snapshot().isBuffering);
  }

  void bufferingChanged(bool buffering) {
    if (!_active) return;
    if (buffering) {
      if (_startedAt != null) return;
      _startedAt = _clock.elapsed;
      _timer = Timer(const Duration(milliseconds: 300), () {
        if (!_active || !_playing || !snapshot().isBuffering) {
          _startedAt = null;
          return;
        }
        _logged = true;
        _record(PlayerDiagnosticKind.bufferingStarted);
        capture(force: true);
        _timer = Timer(const Duration(seconds: 3), () {
          if (_active && _playing && snapshot().isBuffering) capture();
        });
      });
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (_logged && _playing) {
      _record(PlayerDiagnosticKind.bufferingEnded);
      capture(force: true);
    }
    _startedAt = null;
    _logged = false;
  }

  void _record(PlayerDiagnosticKind kind, {NativePlaybackState? state}) => emit(
    PlayerDiagnosticEvent(
      kind: kind,
      snapshot: snapshot(),
      nativeState: state,
      bufferingDuration: _startedAt == null
          ? null
          : _clock.elapsed - _startedAt!,
    ),
  );

  void capture({bool force = false}) {
    if (!_active ||
        _sampling ||
        (!force &&
            _lastSample != null &&
            _clock.elapsed - _lastSample! < const Duration(seconds: 2))) {
      return;
    }
    _sampling = true;
    _lastSample = _clock.elapsed;
    final started = snapshot();
    unawaited(() async {
      try {
        final state = await _sampler.sample();
        if (state != null &&
            _active &&
            snapshot().generation == started.generation &&
            snapshot().desiredPlaying == started.desiredPlaying &&
            snapshot().isSeeking == started.isSeeking) {
          _record(PlayerDiagnosticKind.nativeState, state: state);
        }
      } finally {
        _sampling = false;
      }
    }());
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
  }
}
