import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import 'android_media_leases.dart';
import 'fsplayer_source.dart';
import 'fsplayer_input_lease.dart';
import 'native_audio_gain.dart';
import 'native_playback_health.dart';
import 'native_texture_video_output.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'video_output.dart';

/// One native FSPlayer and one clock for progressive, manifest and DASH inputs.
final class FsPlayerEngine
    implements
        PlayerEngine,
        VideoOutputSource,
        AudioGainControl,
        PlayerInformationSource {
  FsPlayerEngine({this.onDiagnostic, MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('dev.bilisail/fsplayer');

  static bool get supported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  final void Function(PlayerDiagnosticEvent)? onDiagnostic;
  final MethodChannel _channel;
  final _output = NativeTextureVideoOutput();
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  final _health = NativePlaybackHealth();
  final _clock = Stopwatch()..start();
  Future<void> _commands = Future.value();
  Future<void>? _disposal;
  Future<void>? _lateCreationRelease;
  AndroidMediaLeases? _leases;
  FsPlayerInputLease? _inputLease;
  Completer<void> _cancel = Completer<void>();
  Timer? _timer;
  int? _id, _texture;
  int _generation = 0, _seekRevision = 0;
  bool _disposed = false, _sampling = false, _live = false;
  double _gain = 0;
  Map<String, Object?> _native = {};
  PlaybackSnapshot _snapshot = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );

  @override
  VideoOutput get videoOutput => _output;
  @override
  Stream<PlaybackSnapshot> get snapshots => _snapshots.stream;
  @override
  Stream<PlayerFailure> get failures => _failures.stream;
  @override
  PlaybackSnapshot get currentSnapshot => _snapshot;
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);

  void _publish(PlaybackSnapshot value) {
    if (_disposed) return;
    _snapshot = value;
    _snapshots.add(value);
  }

  void _diagnose(PlayerDiagnosticKind kind) => onDiagnostic?.call(
    PlayerDiagnosticEvent(kind: kind, snapshot: _snapshot),
  );

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _commands.then((_) => operation());
    _commands = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  Future<T?> _call<T>(String method, [Map<String, Object?> args = const {}]) =>
      _channel
          .invokeMethod<T>(method, {'id': _id, ...args})
          .timeout(const Duration(seconds: 10));

  void _invalidate() {
    ++_generation;
    ++_seekRevision;
    if (!_cancel.isCompleted) _cancel.complete();
    _timer?.cancel();
  }

  Future<void> _release() async {
    _timer?.cancel();
    _output.clear();
    await _lateCreationRelease;
    _lateCreationRelease = null;
    final id = _id;
    // Preserve a failed release as a barrier: no new runtime may overlap it.
    if (id != null) await _call<void>('dispose');
    _id = _texture = null;
    await _inputLease?.close();
    _inputLease = null;
    await _leases?.close();
    _leases = null;
    _native = {};
    _health.reset();
  }

  Future<Map<String, Object?>> _status() async => Map<String, Object?>.from(
    await _call<Map<Object?, Object?>>('status') ?? const {},
  );

  Future<void> _until(
    bool Function(Map<String, Object?>) condition,
    Completer<void> cancel,
    Stopwatch watch,
    Duration budget,
  ) async {
    while (true) {
      if (cancel.isCompleted) throw const _Superseded();
      final remaining = budget - watch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('fsplayer readiness');
      }
      final status = await Future.any([
        _status(),
        cancel.future.then<Map<String, Object?>>(
          (_) => throw const _Superseded(),
        ),
      ]).timeout(remaining);
      if (cancel.isCompleted) throw const _Superseded();
      if (status['unsupportedColor'] == true) {
        throw const PlayerFailure(
          PlayerFailureKind.unsupportedVideoColor,
          'fsplayer 当前纹理输出不支持此 HDR 色彩空间',
          0,
        );
      }
      if (status['error'] != null) throw StateError('Native playback failed');
      _native = status;
      if (condition(status)) return;
      await Future.any([
        Future<void>.delayed(const Duration(milliseconds: 40)),
        cancel.future,
      ]);
    }
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    if (_disposed) {
      return Future.error(
        const PlayerFailure(PlayerFailureKind.disposed, '播放器已关闭', 0),
      );
    }
    _invalidate();
    final generation = _generation;
    final cancel = _cancel = Completer<void>();
    return _enqueue(() async {
      await _release();
      if (_disposed || cancel.isCompleted) return;
      final watch = Stopwatch()..start();
      _publish(
        PlaybackSnapshot(
          phase: PlaybackPhase.opening,
          generation: generation,
          rate: options.rate,
          volume: options.volume,
        ),
      );
      _diagnose(PlayerDiagnosticKind.openStarted);
      try {
        final leases = _leases = AndroidMediaLeases();
        final leased = switch (source) {
          DashPairSource(
            :final video,
            :final audio,
            :final duration,
            :final isIntentionallySilent,
          ) =>
            DashPairSource(
              video: await leases.open(video),
              audio: audio == null ? null : await leases.open(audio),
              duration: duration,
              isIntentionallySilent: isIntentionallySilent,
            ),
          ProgressiveSource(:final media, :final isAudioOnly, :final isLive) =>
            ProgressiveSource(
              await leases.open(media),
              isAudioOnly: isAudioOnly,
              isLive: isLive,
            ),
          ManifestSource(:final media, :final isLive) => ManifestSource(
            await leases.open(media),
            isLive: isLive,
          ),
          DashVideoSource(:final video) => DashVideoSource(
            await leases.open(video),
          ),
        };
        final input = fsPlayerInput(leased, options);
        if (cancel.isCompleted) throw const _Superseded();
        _live = input.live;
        _gain = options.audioGainDb;
        final inputLease = _inputLease = await FsPlayerInputLease.open(input);
        if (cancel.isCompleted) throw const _Superseded();
        final creation = _channel.invokeMethod<Map<Object?, Object?>>(
          'create',
          {
            'url': inputLease.url,
            'headers': input.headers,
            'video': input.video,
            'software': options.videoDecoding == VideoDecodingMode.software,
            'bufferMs': options.maxBufferAhead.inMilliseconds,
            'durationMs': input.duration?.inMilliseconds ?? 0,
          },
        );
        Map<Object?, Object?>? created;
        try {
          created = await creation.timeout(const Duration(seconds: 10));
        } on Object {
          // A platform invocation cannot be cancelled. Retire any runtime that
          // returns after our timeout before another source may be opened.
          _lateCreationRelease = creation
              .then((late) async {
                final id = late?['id'];
                if (id is int) {
                  await _channel.invokeMethod<void>('dispose', {'id': id});
                }
              })
              .timeout(const Duration(seconds: 10));
          rethrow;
        }
        _id = created?['id'] as int?;
        _texture = created?['texture'] as int?;
        if (_id == null) throw StateError('No native player');
        await _until(
          (s) => s['prepared'] == true,
          cancel,
          watch,
          options.openTimeout,
        );
        if (input.video && _texture != null) {
          final w = (_native['width'] as num?)?.toInt() ?? 0;
          final h = (_native['height'] as num?)?.toInt() ?? 0;
          // Consume startup frames while still painting black, otherwise the
          // producer queue can fill before first-frame/seek confirmation.
          if (w > 0 && h > 0) _output.bind(_texture!, VideoDimensions(w, h));
        }
        await _call<void>('volume', {'amplitude': 0.0});
        await _call<void>('rate', {'rate': options.rate});
        await _call<void>('play');
        await _until(
          (s) =>
              (!input.video || s['videoFrame'] == true) &&
              (!input.audio || s['audioDecoded'] == true),
          cancel,
          watch,
          options.openTimeout,
        );
        await _call<void>('pause');
        if (!_live) {
          await _call<void>('seek', {
            'positionMs': options.startPosition.inMilliseconds,
          });
          await _until(
            (s) => s['seekDone'] == true,
            cancel,
            watch,
            options.openTimeout,
          );
        }
        if (cancel.isCompleted) throw const _Superseded();
        final width = (_native['width'] as num?)?.toInt() ?? 0;
        final height = (_native['height'] as num?)?.toInt() ?? 0;
        final dimensions = width > 0 && height > 0
            ? VideoDimensions(width, height)
            : null;
        if (input.video) {
          if (_texture == null || dimensions == null) {
            throw StateError('No native video output');
          }
          _output.bind(_texture!, dimensions);
          _output.confirmFrame();
        }
        await _applyVolume(options.volume);
        if (options.play) await _call<void>('play');
        if (cancel.isCompleted) throw const _Superseded();
        _publish(
          PlaybackSnapshot(
            phase: options.play ? PlaybackPhase.playing : PlaybackPhase.paused,
            generation: generation,
            duration:
                input.duration ??
                Duration(
                  milliseconds: (_native['durationMs'] as num?)?.toInt() ?? 0,
                ),
            position: options.startPosition,
            desiredPlaying: options.play,
            rate: options.rate,
            volume: options.volume,
            videoDimensions: dimensions,
          ),
        );
        _timer = Timer.periodic(
          NativePlaybackHealth.sampleInterval,
          (_) => unawaited(_sample(generation)),
        );
        _diagnose(PlayerDiagnosticKind.openReady);
      } on _Superseded {
        await _release();
      } on Object catch (error) {
        if (cancel.isCompleted || generation != _generation || _disposed) {
          await _release();
          return;
        }
        final failure = error is PlayerFailure
            ? PlayerFailure(error.kind, error.message, generation)
            : PlayerFailure(
                PlayerFailureKind.nativePlayback,
                'fsplayer 打开失败，可切回 media_kit 后重试',
                generation,
              );
        _fail(failure.message, failure.kind);
        await _release();
        throw failure;
      }
    });
  }

  Future<void> _sample(int generation) async {
    if (_sampling ||
        _disposed ||
        generation != _generation ||
        _id == null ||
        _snapshot.isSeeking) {
      return;
    }
    _sampling = true;
    try {
      final status = await _status();
      if (_disposed || generation != _generation || _snapshot.isSeeking) return;
      _native = status;
      if (status['error'] != null) {
        _fail('fsplayer 播放失败');
        return;
      }
      final ended = status['ended'] == true;
      final buffering = status['buffering'] == true && _snapshot.desiredPlaying;
      _publish(
        _snapshot.copyWith(
          position: Duration(
            milliseconds: (status['positionMs'] as num?)?.toInt() ?? 0,
          ),
          buffered: Duration(
            milliseconds: (status['bufferedMs'] as num?)?.toInt() ?? 0,
          ),
          isBuffering: buffering,
          phase: ended
              ? PlaybackPhase.ended
              : buffering
              ? PlaybackPhase.buffering
              : _snapshot.desiredPlaying
              ? PlaybackPhase.playing
              : PlaybackPhase.paused,
        ),
      );
      if (_health.update(_snapshot, _clock.elapsed, paired: false) != null) {
        _fail('fsplayer 播放停滞，正在尝试恢复');
      }
    } on Object {
      if (!_disposed && generation == _generation) _fail('fsplayer 状态读取失败');
    } finally {
      _sampling = false;
    }
  }

  void _fail(
    String message, [
    PlayerFailureKind kind = PlayerFailureKind.nativePlayback,
  ]) {
    if (_disposed || _snapshot.phase == PlaybackPhase.failed) return;
    _timer?.cancel();
    if (_id != null) {
      unawaited(_call<void>('pause').catchError((Object _) {}));
    }
    _publish(
      _snapshot.copyWith(
        phase: PlaybackPhase.failed,
        desiredPlaying: false,
        isSeeking: false,
        isBuffering: false,
      ),
    );
    _failures.add(PlayerFailure(kind, message, _generation));
    _diagnose(PlayerDiagnosticKind.failed);
  }

  Future<void> _command(String name, [Map<String, Object?> args = const {}]) {
    final generation = _generation;
    return _enqueue(() async {
      if (!_disposed && generation == _generation && _id != null) {
        await _call<void>(name, args);
      }
    });
  }

  @override
  Future<void> play() async {
    _publish(_snapshot.copyWith(desiredPlaying: true));
    if (_snapshot.isSeeking) return;
    await _command('play');
    _health.reset();
  }

  @override
  Future<void> pause() async {
    _publish(_snapshot.copyWith(desiredPlaying: false));
    // Pause is allowed while a queued seek is awaiting native confirmation.
    if (_id != null) await _call<void>('pause');
    _health.reset();
  }

  @override
  Future<void> seek(Duration target) {
    final generation = _generation;
    final revision = ++_seekRevision;
    return _enqueue(() async {
      if (_disposed ||
          generation != _generation ||
          revision != _seekRevision ||
          _id == null ||
          _live) {
        return;
      }
      _publish(_snapshot.copyWith(isSeeking: true));
      _health.reset();
      try {
        await _call<void>('pause');
        await _call<void>('seek', {
          'positionMs': target.inMilliseconds.clamp(0, 1 << 53),
        });
        await _until(
          (s) => s['seekDone'] == true,
          _cancel,
          Stopwatch()..start(),
          const Duration(seconds: 15),
        );
        if (generation != _generation || _disposed) return;
        // The latest queued target supersedes this one without resuming audio.
        if (revision != _seekRevision) return;
        if (_snapshot.desiredPlaying) await _call<void>('play');
        _publish(
          _snapshot.copyWith(
            position: target < Duration.zero ? Duration.zero : target,
            isSeeking: false,
            isBuffering: false,
            phase: _snapshot.desiredPlaying
                ? PlaybackPhase.playing
                : PlaybackPhase.paused,
          ),
        );
      } on _Superseded {
        return;
      } on Object {
        if (generation == _generation && !_disposed) _fail('fsplayer 跳转失败');
      }
    });
  }

  @override
  Future<void> setRate(double rate) async {
    if (!rate.isFinite || rate <= 0) throw ArgumentError.value(rate);
    final generation = _generation;
    await _command('rate', {'rate': rate});
    if (_disposed || generation != _generation) return;
    _health.reset();
    _publish(_snapshot.copyWith(rate: rate));
  }

  Future<void> _applyVolume(double volume) => _call<void>('volume', {
    'amplitude': volume / 100 * fsPlayerGainAmplitude(_gain),
  });
  @override
  Future<void> setVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 100) {
      throw ArgumentError.value(volume);
    }
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || _disposed || _id == null) return;
      await _applyVolume(volume);
      _publish(_snapshot.copyWith(volume: volume));
    });
  }

  @override
  Future<void> setAudioGain(double gainDb) {
    if (!NativeAudioGain.valid(gainDb)) throw ArgumentError.value(gainDb);
    final generation = _generation;
    return _enqueue(() async {
      if (generation != _generation || _disposed || _id == null) return;
      _gain = gainDb;
      await _applyVolume(_snapshot.volume);
    });
  }

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async {
    if (_id == null || _disposed) return null;
    final generation = _generation;
    final s = _native;
    final w = (s['width'] as num?)?.toInt(), h = (s['height'] as num?)?.toInt();
    return PlayerPlaybackInformation(
      generation: generation,
      backend: 'fsplayer / FFmpeg',
      hardwareDecoder: s['decoder'] as String?,
      videoCodec: s['videoCodec'] as String?,
      audioCodec: s['audioCodec'] as String?,
      sourceFps: (s['fps'] as num?)?.toDouble(),
      outputFps: (s['outputFps'] as num?)?.toDouble(),
      videoOutput: s['output'] as String?,
      frameDrops: (s['frameDrops'] as num?)?.toInt(),
      avSyncSeconds: (s['avSync'] as num?)?.toDouble(),
      cacheBytes: (s['cacheBytes'] as num?)?.toInt(),
      cacheSpeed: (s['cacheSpeed'] as num?)?.toDouble(),
      cacheSeconds: (s['cacheMs'] as num?)?.toDouble() == null
          ? null
          : (s['cacheMs'] as num).toDouble() / 1000,
      audioGainDb: _gain,
      diagnostics: PlayerDiagnostics(
        generation: generation,
        position: _snapshot.position,
        hasDecodedVideo: s['videoFrame'] == true,
        hasDecodedAudio: s['audioDecoded'] == true,
        hasVideoOutput: s['videoFrame'] == true,
        outputWidth: w,
        outputHeight: h,
        videoWidth: w,
        videoHeight: h,
        audioSampleRate: (s['sampleRate'] as num?)?.toInt(),
        audioChannels: (s['channels'] as num?)?.toInt(),
        videoCodec: s['videoCodec'] as String?,
        audioCodec: s['audioCodec'] as String?,
      ),
    );
  }

  @override
  Future<void> stop() {
    if (_disposed) return _disposal ?? Future.value();
    _invalidate();
    return _enqueue(() async {
      await _release();
      _publish(
        PlaybackSnapshot(phase: PlaybackPhase.idle, generation: _generation),
      );
    });
  }

  @override
  Future<void> dispose() {
    if (_disposal case final disposal?) return disposal;
    _invalidate();
    _disposed = true;
    return _disposal = _enqueue(() async {
      await _release();
      _output.dispose();
      _clock.stop();
      await _snapshots.close();
      await _failures.close();
    });
  }
}

final class _Superseded implements Exception {
  const _Superseded();
}
