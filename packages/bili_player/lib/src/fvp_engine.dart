import 'dart:async';
import 'dart:io';

import 'android_media_leases.dart';
import 'android_fvp_player.dart';
import 'fvp_native_player.dart';
import 'fvp_video_output.dart';
import 'native_audio_gain.dart';
import 'native_playback_health.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'video_output.dart';

/// Experimental single-clock MDK runtime. Every source owns one native player.
final class FvpEngine
    implements
        PlayerEngine,
        VideoOutputSource,
        AudioGainControl,
        PlayerInformationSource {
  FvpEngine({this.onDiagnostic, Future<FvpPlayerPort> Function()? createPlayer})
    : _createPlayer = createPlayer ?? createFvpNativePlayer,
      _isolated = createPlayer == null && Platform.isAndroid;

  final void Function(PlayerDiagnosticEvent)? onDiagnostic;
  final Future<FvpPlayerPort> Function() _createPlayer;
  final bool _isolated;
  NativeReadinessStage? _stage;
  bool _processLost = false;
  final _output = FvpVideoOutput();
  AndroidMediaLeases? _leases;
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  final _health = NativePlaybackHealth();
  final _clock = Stopwatch()..start();
  Future<void> _commands = Future.value();
  FvpPlayerPort? _player;
  StreamSubscription<FvpNativeStatus>? _statusSubscription;
  Completer<void> _cancelled = Completer<void>();
  Timer? _timer;
  bool _disposed = false;
  bool _opening = false;
  bool _live = false;
  bool _requiresAudio = false;
  bool _audioConfirmed = false;
  Duration _audioBudget = Duration.zero;
  Completer<void>? _playCancelled;
  double _gainDb = 0;
  int _generation = 0;
  int _seekRevision = 0;
  int _pauseRevision = 0;
  Future<void>? _disposal;
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

  void _publish(PlaybackSnapshot snapshot) {
    if (_disposed) return;
    _snapshot = snapshot;
    _snapshots.add(snapshot);
  }

  void _diagnose(PlayerDiagnosticKind kind) => onDiagnostic?.call(
    PlayerDiagnosticEvent(
      kind: kind,
      snapshot: _snapshot,
      readinessStage: _stage,
      nativeErrorCode: kind == PlayerDiagnosticKind.nativeProcessExited
          ? switch (_player) {
              final AndroidFvpPlayer player => player.exitStatus,
              _ => null,
            }
          : null,
    ),
  );

  void _openingStage(NativeReadinessStage stage) {
    _stage = stage;
    _diagnose(PlayerDiagnosticKind.openStageChanged);
  }

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async {
    final player = _player;
    final generation = _generation;
    if (_disposed || _opening || player == null || _cancelled.isCompleted) {
      return null;
    }
    if (player is! FvpInformationPort) {
      return PlayerPlaybackInformation(
        generation: generation,
        backend: 'fvp / MDK',
        audioGainDb: _gainDb,
      );
    }
    try {
      final information = await (player as FvpInformationPort)
          .inspectPlaybackInformation(
            generation: generation,
            audioGainDb: _gainDb,
          )
          .timeout(const Duration(seconds: 1));
      return !_disposed &&
              !_cancelled.isCompleted &&
              generation == _generation &&
              information?.generation == generation &&
              identical(player, _player)
          ? information
          : null;
    } on Object {
      // Optional native statistics must not interrupt playback or disposal.
      return null;
    }
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final next = _commands.then((_) => action());
    _commands = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _invalidate() {
    ++_generation;
    if (!_cancelled.isCompleted) _cancelled.complete();
    _cancelPlay();
    _timer?.cancel();
    _player?.interrupt();
  }

  Future<T> _wait<T>(
    Future<T> operation,
    Completer<void> cancellation,
    Stopwatch watch,
    Duration budget,
  ) => Future.any<T>([
    operation,
    cancellation.future.then<T>((_) => throw const _Cancelled()),
  ]).timeout(budget - watch.elapsed);

  Future<void> _release() async {
    _timer?.cancel();
    _output.clear();
    await _statusSubscription?.cancel();
    _statusSubscription = null;
    if (_player case final player?) {
      await player.dispose().timeout(const Duration(seconds: 10));
      _player = null;
    }
    await _leases?.close();
    _leases = null;
    _health.reset();
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    if (_disposed) {
      return Future.error(
        PlayerFailure(PlayerFailureKind.disposed, '播放器已关闭', _generation),
      );
    }
    _invalidate();
    final generation = _generation;
    final cancellation = _cancelled = Completer<void>();
    return _enqueue(() async {
      await _release();
      if (_disposed || generation != _generation) return;
      final watch = Stopwatch()..start();
      _opening = true;
      _stage = null;
      _processLost = false;
      _live = switch (source) {
        ManifestSource(:final isLive) ||
        ProgressiveSource(:final isLive) => isLive,
        _ => false,
      };
      _publish(
        PlaybackSnapshot(
          phase: PlaybackPhase.opening,
          generation: generation,
          position: options.startPosition,
          rate: options.rate,
          volume: options.volume,
        ),
      );
      _diagnose(PlayerDiagnosticKind.openStarted);
      var stage = '初始化';
      final leases = _leases = AndroidMediaLeases();
      Future<MediaTrack> lease(MediaTrack track) async {
        // Descriptor numbers are process-local. The worker owns its leases.
        if (_isolated) return track;
        final opened = await leases.open(track);
        if (cancellation.isCompleted ||
            generation != _generation ||
            _disposed) {
          await leases.close();
          throw const _Cancelled();
        }
        return opened;
      }

      try {
        final (media, audio, video, silent) = _validate(
          source,
          options,
          generation,
        );
        final main = await _wait(
          lease(media),
          cancellation,
          watch,
          options.openTimeout,
        );
        final sound = audio == null
            ? null
            : await _wait(
                lease(audio),
                cancellation,
                watch,
                options.openTimeout,
              );
        // dup() shares a descriptor's offset. Give the Android probe its own
        // provider lease so it cannot consume the final player's audio input.
        final audioProbe = audio != null && audio.uri.scheme == 'content'
            ? await _wait(
                lease(audio),
                cancellation,
                watch,
                options.openTimeout,
              )
            : sound;
        // The factory is also owned if cancellation wins before it resolves.
        final player = await _createPlayer();
        _player = player;
        if (_disposed || generation != _generation) throw const _Cancelled();
        _statusSubscription = player.statuses.listen((status) {
          if (!_disposed &&
              generation == _generation &&
              status == FvpNativeStatus.processExited) {
            if (_processLost) return;
            _processLost = true;
            _diagnose(PlayerDiagnosticKind.nativeProcessExited);
            _fail(
              '播放器异常退出，请退出播放页后重新打开',
              kind: PlayerFailureKind.nativeProcessExited,
            );
            _output.clear();
            return;
          }
          if (_disposed ||
              generation != _generation ||
              _opening ||
              _snapshot.phase == PlaybackPhase.failed) {
            return;
          }
          // EOF remains observable until an explicit seek/play. Trailing
          // buffer notifications must not turn replay into a normal resume.
          if (_snapshot.phase == PlaybackPhase.ended &&
              status != FvpNativeStatus.invalid) {
            return;
          }
          switch (status) {
            case FvpNativeStatus.processExited:
              return;
            case FvpNativeStatus.invalid:
              _fail('fvp 无法继续播放此媒体');
            case FvpNativeStatus.ended:
              _timer?.cancel();
              _publish(
                _snapshot.copyWith(
                  phase: PlaybackPhase.ended,
                  desiredPlaying: false,
                  isBuffering: false,
                  isSeeking: false,
                ),
              );
            case FvpNativeStatus.buffering:
              _publish(
                _snapshot.copyWith(
                  isBuffering: true,
                  phase: _snapshot.desiredPlaying
                      ? PlaybackPhase.buffering
                      : PlaybackPhase.paused,
                ),
              );
            case FvpNativeStatus.buffered:
              _publish(
                _snapshot.copyWith(
                  isBuffering: false,
                  phase: _snapshot.desiredPlaying
                      ? (_snapshot.isSeeking
                            ? PlaybackPhase.buffering
                            : PlaybackPhase.playing)
                      : PlaybackPhase.paused,
                ),
              );
          }
        });
        stage = '准备音视频';
        _openingStage(NativeReadinessStage.tracks);
        final info = await _wait(
          player.prepare(
            main,
            sound,
            options,
            silent: silent,
            audioProbe: audioProbe,
            isLive: _live,
          ),
          cancellation,
          watch,
          options.openTimeout,
        );
        stage = '验证视频';
        if (!video && info.dimensions != null) {
          throw PlayerFailure(
            PlayerFailureKind.invalidSource,
            '听视频音频源包含视频轨道',
            generation,
          );
        }
        if (video && info.dimensions == null) {
          throw StateError('No decoded video');
        }
        if (video) {
          stage = '创建画面';
          _openingStage(NativeReadinessStage.videoOutput);
          final texture = await _wait(
            player.createTexture(),
            cancellation,
            watch,
            options.openTimeout,
          );
          if (texture < 0) throw StateError('No video texture');
          _output.bind(texture, info.dimensions!);
          stage = '确认首帧';
          _openingStage(NativeReadinessStage.videoDecode);
          if (!await _wait(
            player.confirmVideoFrame(),
            cancellation,
            watch,
            options.openTimeout,
          )) {
            throw StateError('No rendered video frame');
          }
          _output.confirmFrame();
        }
        _requiresAudio = audio != null || !video || info.hasAudio;
        _audioConfirmed = false;
        _gainDb = options.audioGainDb;
        _opening = false;
        if (options.play) {
          player.play();
          stage = '验证音轨';
          _openingStage(NativeReadinessStage.externalAudio);
          if (_requiresAudio &&
              !await _wait(
                player.confirmAudio(),
                cancellation,
                watch,
                options.openTimeout,
              )) {
            throw StateError('No decoded audio');
          }
          _audioConfirmed = true;
        } else {
          player.pause();
        }
        _audioBudget = options.openTimeout - watch.elapsed;
        _publish(
          PlaybackSnapshot(
            phase: options.play ? PlaybackPhase.playing : PlaybackPhase.paused,
            generation: generation,
            position: options.startPosition,
            duration: info.duration,
            desiredPlaying: options.play,
            rate: options.rate,
            volume: options.volume,
            videoDimensions: info.dimensions,
          ),
        );
        _startSampling(generation);
        _diagnose(PlayerDiagnosticKind.openReady);
      } on _Cancelled {
        await _release();
      } on Object catch (error) {
        if (!cancellation.isCompleted) cancellation.complete();
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        if (error is FvpProcessException && !_processLost) {
          _processLost = true;
          _diagnose(PlayerDiagnosticKind.nativeProcessExited);
        }
        final failure = error is FvpProcessException
            ? PlayerFailure(
                PlayerFailureKind.nativeProcessExited,
                '播放器异常退出，请退出播放页后重新打开',
                generation,
              )
            : error is PlayerFailure
            ? error
            : PlayerFailure(
                PlayerFailureKind.nativePlayback,
                'fvp $stage失败，可切回 media_kit 后重试',
                generation,
              );
        _fail(failure.message, kind: failure.kind);
        await _release();
        throw failure;
      } finally {
        if (generation == _generation) _opening = false;
      }
    });
  }

  void _startSampling(int generation) {
    if (_timer?.isActive ?? false) return;
    _timer = Timer.periodic(
      NativePlaybackHealth.sampleInterval,
      (_) => _sample(generation),
    );
  }

  void _sample(int generation) {
    final player = _player;
    if (_disposed ||
        generation != _generation ||
        player == null ||
        _opening ||
        _snapshot.isSeeking ||
        _snapshot.phase == PlaybackPhase.failed ||
        _snapshot.phase == PlaybackPhase.ended) {
      return;
    }
    final position = Duration(
      milliseconds: player.positionMilliseconds.clamp(0, 1 << 53),
    );
    final buffered =
        position +
        Duration(milliseconds: player.bufferedMilliseconds.clamp(0, 1 << 53));
    _publish(_snapshot.copyWith(position: position, buffered: buffered));
    if (_health.update(_snapshot, _clock.elapsed, paired: false) != null) {
      _fail('fvp 播放停滞，正在尝试恢复');
    }
  }

  void _fail(
    String message, {
    PlayerFailureKind kind = PlayerFailureKind.nativePlayback,
  }) {
    if (_disposed || _snapshot.phase == PlaybackPhase.failed) return;
    _timer?.cancel();
    _player?.pause();
    _publish(
      _snapshot.copyWith(
        phase: PlaybackPhase.failed,
        desiredPlaying: false,
        isBuffering: false,
        isSeeking: false,
      ),
    );
    _failures.add(PlayerFailure(kind, message, _generation));
    _diagnose(PlayerDiagnosticKind.failed);
  }

  (MediaTrack, MediaTrack?, bool, bool) _validate(
    ResolvedMediaSource source,
    OpenOptions options,
    int generation,
  ) {
    Never invalid(
      String message, [
      PlayerFailureKind kind = PlayerFailureKind.invalidSource,
    ]) => throw PlayerFailure(kind, message, generation);
    if (options.startPosition < Duration.zero ||
        options.openTimeout <= Duration.zero ||
        !options.rate.isFinite ||
        options.rate <= 0 ||
        !options.volume.isFinite ||
        options.volume < 0 ||
        options.volume > 100 ||
        !NativeAudioGain.valid(options.audioGainDb) ||
        options.maxBufferAhead <= Duration.zero ||
        options.maxBufferAhead > OpenOptions.maximumBufferAhead) {
      invalid('无效的播放参数');
    }
    final (media, audio, video, silent) = switch (source) {
      ProgressiveSource(:final media, :final isAudioOnly) => (
        media,
        null,
        !isAudioOnly,
        false,
      ),
      ManifestSource(:final media) => (media, null, true, false),
      DashPairSource(
        :final video,
        :final audio,
        :final isIntentionallySilent,
      ) =>
        (video, audio, true, audio == null && isIntentionallySilent),
      DashVideoSource(:final video) => (video, null, true, true),
    };
    if (source is DashPairSource && audio == null && !silent) {
      invalid('DASH 音轨缺失');
    }
    if (source is DashVideoSource && options.volume != 0) invalid('无音轨预览必须静音');
    for (final track in [media, ?audio]) {
      if (!{
            'http',
            'https',
            'file',
            if (Platform.isAndroid) 'content',
          }.contains(track.uri.scheme) ||
          (track.uri.scheme != 'file' && track.uri.host.isEmpty)) {
        invalid('不支持的媒体地址');
      }
      for (final entry in track.requestPolicy.headers.entries) {
        if (!{
              'user-agent',
              'referer',
              'origin',
              'accept',
            }.contains(entry.key.toLowerCase()) ||
            entry.key.contains(RegExp(r'[\r\n]')) ||
            entry.value.contains(RegExp(r'[\r\n]'))) {
          invalid('不支持的媒体请求头', PlayerFailureKind.unsupportedHeaders);
        }
      }
    }
    Map<String, String> headers(MediaTrack track) => {
      for (final entry in track.requestPolicy.headers.entries)
        entry.key.toLowerCase(): entry.value,
    };
    final first = headers(media);
    if (audio != null) {
      final second = headers(audio);
      if (first.length != second.length ||
          first.entries.any((entry) => second[entry.key] != entry.value)) {
        invalid('fvp 暂不支持不同的分轨请求头', PlayerFailureKind.unsupportedHeaders);
      }
    }
    return (media, audio, video, silent);
  }

  Future<void> _command(void Function(FvpPlayerPort) action) {
    final generation = _generation;
    return _enqueue(() async {
      if (!_disposed && generation == _generation && _player != null) {
        action(_player!);
      }
    });
  }

  @override
  Future<void> play() {
    _cancelPlay();
    final cancelled = _playCancelled = Completer<void>();
    final generation = _generation;
    return _enqueue(() async {
      final player = _player;
      if (_disposed ||
          generation != _generation ||
          player == null ||
          _snapshot.phase == PlaybackPhase.failed ||
          cancelled.isCompleted) {
        return;
      }
      if (_snapshot.isSeeking) {
        _publish(_snapshot.copyWith(desiredPlaying: true));
        return;
      }
      final watch = Stopwatch()..start();
      player.play();
      try {
        if (_requiresAudio && !_audioConfirmed) {
          final ready = await _wait(
            Future.any<bool>([
              player.confirmAudio(),
              cancelled.future.then<bool>((_) => throw const _Cancelled()),
            ]),
            _cancelled,
            watch,
            _audioBudget,
          );
          if (!ready) throw StateError('No decoded audio');
          _audioConfirmed = true;
        }
        _health.reset();
        _publish(
          _snapshot.copyWith(
            phase: PlaybackPhase.playing,
            desiredPlaying: true,
          ),
        );
        _startSampling(generation);
      } on _Cancelled {
        return;
      } on Object {
        if (!_disposed && generation == _generation) {
          const message = 'fvp 音轨未能就绪，可切回 media_kit 后重试';
          _fail(message);
          throw PlayerFailure(
            PlayerFailureKind.nativePlayback,
            message,
            generation,
          );
        }
      } finally {
        _audioBudget -= watch.elapsed;
      }
    });
  }

  void _cancelPlay() {
    final cancelled = _playCancelled;
    if (cancelled != null && !cancelled.isCompleted) cancelled.complete();
  }

  @override
  Future<void> pause() {
    ++_pauseRevision;
    _cancelPlay();
    _player?.pause();
    return _command((player) {
      if (_snapshot.phase == PlaybackPhase.failed) return;
      player.pause();
      _health.reset();
      _publish(
        _snapshot.copyWith(
          phase: _snapshot.phase == PlaybackPhase.ended
              ? PlaybackPhase.ended
              : PlaybackPhase.paused,
          desiredPlaying: false,
        ),
      );
    });
  }

  @override
  Future<void> seek(Duration target) {
    final generation = _generation;
    final revision = ++_seekRevision;
    final pauseRevision = _pauseRevision;
    if (_snapshot.isSeeking) _player?.cancelSeek();
    return _enqueue(() async {
      final player = _player;
      if (_disposed ||
          generation != _generation ||
          revision != _seekRevision ||
          player == null ||
          _live ||
          _snapshot.phase == PlaybackPhase.failed) {
        return;
      }
      final shouldPlay = _snapshot.desiredPlaying;
      player.pause();
      _health.reset();
      _publish(
        _snapshot.copyWith(
          isSeeking: true,
          phase: shouldPlay ? PlaybackPhase.buffering : PlaybackPhase.paused,
        ),
      );
      try {
        // Superseding cancels the old native read. The adapter retires its
        // callbacks before preparing the latest target on the same texture.
        final result = await _wait(
          player.seek(target < Duration.zero ? Duration.zero : target),
          _cancelled,
          Stopwatch()..start(),
          const Duration(seconds: 15),
        );
        if (_disposed ||
            generation != _generation ||
            revision != _seekRevision ||
            _snapshot.phase == PlaybackPhase.failed) {
          return;
        }
        if (result < 0) throw StateError('MDK seek failed');
        final resume = shouldPlay && pauseRevision == _pauseRevision;
        if (resume) player.play();
        _health.reset();
        _publish(
          _snapshot.copyWith(
            position: Duration(milliseconds: result),
            isSeeking: false,
            isBuffering: false,
            desiredPlaying: resume,
            phase: resume ? PlaybackPhase.playing : PlaybackPhase.paused,
          ),
        );
        _startSampling(generation);
      } on _Cancelled {
        return;
      } on Object {
        if (!_disposed && generation == _generation) {
          _fail('fvp 跳转失败');
          // A timeout must not leave a live callback slot for another seek.
          player.interrupt();
        }
      }
    });
  }

  @override
  Future<void> setRate(double rate) => _command((player) {
    if (!rate.isFinite || rate <= 0) throw ArgumentError.value(rate);
    player.setRate(rate);
    _health.reset();
    _publish(_snapshot.copyWith(rate: rate));
  });
  @override
  Future<void> setVolume(double volume) => _command((player) {
    if (!volume.isFinite || volume < 0 || volume > 100) {
      throw ArgumentError.value(volume);
    }
    player.setVolume(volume, _gainDb);
    _publish(_snapshot.copyWith(volume: volume));
  });
  @override
  Future<void> setAudioGain(double gainDb) => _command((player) {
    if (!NativeAudioGain.valid(gainDb)) throw ArgumentError.value(gainDb);
    _gainDb = gainDb;
    player.setVolume(_snapshot.volume, gainDb);
  });
  @override
  Future<void> stop() {
    if (_disposed) return _disposal ?? Future.value();
    _invalidate();
    final generation = _generation;
    return _enqueue(() async {
      await _release();
      if (!_disposed && generation == _generation) {
        _publish(
          PlaybackSnapshot(phase: PlaybackPhase.idle, generation: generation),
        );
      }
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

final class _Cancelled implements Exception {
  const _Cancelled();
}
