import 'dart:async';
import 'dart:math' as math;

import 'dash_track_buffer.dart';
import 'native_error_monitor.dart';
import 'native_playback_health.dart';
import 'native_readiness.dart';
import 'playback_backend.dart';
import 'playback_startup.dart';
import 'player_contract.dart';
import 'player_diagnostics.dart';
import 'player_playback_information.dart';
import 'switching_video_output.dart';
import 'validated_source.dart';
import 'video_output.dart';

/// The only writer of playback state, independent of native SDK and platform.
class SharedPlayerEngine
    implements
        PlayerEngine,
        VideoOutputSource,
        AudioGainControl,
        PlayerInformationSource {
  SharedPlayerEngine({
    required this.createBackend,
    this.schemes = const {'http', 'https', 'file'},
    this.onDiagnostic,
    this.monotonicNow,
    this.bufferDashTracks = false,
    VideoOutput? initialVideoOutput,
  }) {
    _output.bind(initialVideoOutput);
    _errors = NativeErrorMonitor(
      onStalled: (_) => unawaited(_fail(PlayerFailureKind.nativePlayback)),
      onRecovered: (_) => _diagnose(PlayerDiagnosticKind.recovered),
    );
  }

  final FutureOr<PlaybackBackend> Function() createBackend;
  final Set<String> schemes;
  final void Function(PlayerDiagnosticEvent)? onDiagnostic;
  final Duration Function()? monotonicNow;
  final bool bufferDashTracks;
  DashTrackBuffer? _dashBuffer;
  final _clock = Stopwatch()..start();
  final _output = SwitchingVideoOutput();
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  final _health = NativePlaybackHealth();
  late final NativeErrorMonitor _errors;
  PlaybackBackend? _backend;
  PlaybackBackend? get activeBackend => _backend;
  Future<PlaybackBackend>? _allocation;
  StreamSubscription<BackendEvent>? _subscription;
  Future<void> _lifecycle = Future.value();
  Future<void> _controls = Future.value();
  Future<void> _seeks = Future.value();
  Future<void>? _disposal;
  Future<void>? _releaseBarrier;
  Future<PlayerFailure>? _failing;
  PlaybackOperation? _openOperation, _playOperation, _seekOperation;
  Timer? _timer;
  int _generation = 0,
      _seekRevision = 0,
      _intentRevision = 0,
      _gainRevision = 0;
  bool _disposed = false, _opening = false, _muted = true;
  bool _requiresAudio = false, _requiresVideo = false, _audioConfirmed = false;
  bool _live = false, _preview = false;
  double _gainDb = 0;
  Duration _audioBudget = Duration.zero;
  bool _publishing = false;
  final _pendingSnapshots = <PlaybackSnapshot>[];
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

  bool _current(int generation, [PlaybackBackend? backend]) =>
      !_disposed &&
      generation == _generation &&
      (backend == null || identical(backend, _backend));
  bool get _terminal => const {
    PlaybackPhase.idle,
    PlaybackPhase.failed,
    PlaybackPhase.ended,
    PlaybackPhase.disposed,
  }.contains(_snapshot.phase);
  bool get _confirmingAudio =>
      _requiresAudio &&
      !_audioConfirmed &&
      _playOperation?.isCancelled == false;

  void _publish(PlaybackSnapshot value) {
    if (_disposed || value.generation != _generation || value == _snapshot) {
      return;
    }
    _snapshot = value;
    _errors.update(value);
    _pendingSnapshots.add(value);
    if (_publishing) return;
    _publishing = true;
    try {
      while (_pendingSnapshots.isNotEmpty) {
        final next = _pendingSnapshots.removeAt(0);
        if (!_disposed && next.generation == _generation) _snapshots.add(next);
      }
    } finally {
      _publishing = false;
    }
  }

  void _diagnose(
    PlayerDiagnosticKind kind, {
    NativeErrorSummary? nativeError,
    PlayerFailureKind? failureKind,
    NativePlaybackInterruption? interruption,
  }) => onDiagnostic?.call(
    PlayerDiagnosticEvent(
      kind: kind,
      snapshot: _snapshot,
      nativeError: nativeError,
      failureKind: failureKind,
      stallReason: interruption?.reason,
      stalledFor: interruption?.stalledFor,
      audioPosition: interruption?.audioPosition,
    ),
  );

  Future<void> _serial(Future<void> Function() work) {
    final next = _lifecycle.then((_) => work());
    _lifecycle = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  /// Only short native command dispatch is serialized, never readiness waits.
  Future<void> _control(
    int generation,
    Future<void> Function(PlaybackBackend) work, {
    bool Function()? allowed,
  }) {
    final source = _openOperation;
    final next = _controls.then((_) async {
      final backend = _backend;
      if (!_current(generation) ||
          backend == null ||
          (allowed != null && !allowed())) {
        return;
      }
      try {
        final command = work(backend);
        if (source == null) {
          await command.timeout(const Duration(seconds: 2));
        } else {
          await source.wait(command, timeout: const Duration(seconds: 2));
        }
      } on SourceSuperseded {
        return;
      } on Object catch (error) {
        if (!_current(generation, backend)) return;
        if (_opening) rethrow;
        throw await _fail(
          error is PlayerFailure
              ? error.kind
              : PlayerFailureKind.nativePlayback,
          interruptNative: true,
        );
      }
    });
    _controls = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  void _interrupt(PlaybackBackend? backend) {
    unawaited(_dashBuffer?.close());
    try {
      backend?.interrupt();
    } on Object {
      // Disposal remains the final barrier even if stop/interrupt is rejected.
    }
  }

  void _invalidate({bool retainPresentation = false}) {
    ++_generation;
    ++_intentRevision;
    ++_seekRevision;
    ++_gainRevision;
    _openOperation?.cancel();
    _playOperation?.cancel();
    _seekOperation?.cancel();
    _timer?.cancel();
    _timer = null;
    _errors.reset();
    _health.reset();
    if (!retainPresentation) {
      _output.clearRetainedFrame();
      _interrupt(_backend);
      _output.bind(null);
    }
  }

  Future<void> _release() {
    if (_releaseBarrier case final barrier?) return barrier;
    final releasing = _releaseResources();
    _releaseBarrier = releasing;
    unawaited(
      releasing.then<void>(
        (_) {
          if (identical(releasing, _releaseBarrier)) _releaseBarrier = null;
        },
        onError: (Object _, StackTrace _) {
          // An uncertain release remains a barrier for all later allocations.
        },
      ),
    );
    return releasing;
  }

  Future<void> _releaseResources() async {
    _output.bind(null);
    await _subscription?.cancel();
    _subscription = null;
    await _dashBuffer?.close();
    _dashBuffer = null;
    // A late factory remains owned. No replacement allocates over an unknown
    // release, including a factory which returned after its open timed out.
    final allocation = _allocation;
    if (allocation != null) {
      try {
        await allocation;
      } on Object {
        /* No resource was allocated. */
      }
      _allocation = null;
    }
    final old = _backend;
    if (old != null) {
      await old.dispose();
      if (identical(old, _backend)) _backend = null;
    }
    _health.reset();
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    if (_disposed) {
      return Future.error(
        PlayerFailure(PlayerFailureKind.disposed, '播放器已关闭', _generation),
      );
    }
    final previous = _snapshot;
    _invalidate(retainPresentation: options.retainPresentation);
    final generation = _generation;
    final operation = _openOperation = PlaybackOperation(
      generation,
      options.openTimeout,
    );
    _opening = true;
    _muted = true;
    _live = switch (source) {
      ProgressiveSource(:final isLive) ||
      ManifestSource(:final isLive) => isLive,
      _ => false,
    };
    _failing = null;
    _gainDb = options.audioGainDb;
    _publish(
      PlaybackSnapshot(
        phase: PlaybackPhase.opening,
        generation: generation,
        position: options.startPosition,
        duration: options.retainPresentation
            ? previous.duration
            : Duration.zero,
        buffered: options.retainPresentation
            ? previous.buffered
            : Duration.zero,
        videoDimensions: options.retainPresentation
            ? previous.videoDimensions
            : null,
        rate: options.rate,
        volume: options.volume,
        desiredPlaying: options.play,
      ),
    );
    return _serial(() async {
      // An opening snapshot can synchronously replace this request before it
      // reaches the lifecycle queue. Never release that replacement's backend.
      if (!_current(generation)) return;
      if (options.retainPresentation) {
        // A session deadline can request replacement before the failure stream
        // arrives. Capture before interrupting that still-visible output too.
        await _output.retainFrame();
        if (!_current(generation)) return;
        _interrupt(_backend);
      }
      await _release();
      if (!_current(generation)) return;
      _diagnose(PlayerDiagnosticKind.openStarted);
      try {
        var plan = ValidatedSource.validate(
          source,
          options,
          generation,
          schemes: schemes,
        );
        operation.check();
        _live = plan.live;
        _preview = source is DashVideoSource;
        _audioConfirmed = false;
        if (bufferDashTracks && DashTrackBuffer.supports(plan)) {
          final buffer = await DashTrackBuffer.create(
            plan,
            onFailure: (error) {
              if (_current(generation)) {
                _diagnose(PlayerDiagnosticKind.nativeError, nativeError: error);
              }
            },
          );
          if (!_current(generation)) {
            await buffer.close();
            return;
          }
          _dashBuffer = buffer;
          operation.check();
          plan = buffer.prepare(plan);
        }
        final creating = _allocation =
            Future<PlaybackBackend>.sync(createBackend).then((value) {
              _backend = value;
              return value;
            });
        final backend = await operation.wait(creating);
        _allocation = null;
        _output.bind(backend.videoOutput);
        _subscription = backend.events.listen(
          (event) => _event(event, generation, backend),
        );
        final tracks = await operation.wait(
          backend.prepareMuted(plan, operation),
        );
        if ((plan.requiresVideo && !tracks.hasVideo) ||
            (!tracks.hasVideo && !tracks.hasAudio) ||
            (plan.audioOnly && (!tracks.hasAudio || tracks.hasVideo)) ||
            (plan.audio != null &&
                (!tracks.hasAudio || !tracks.externalAudioSelected))) {
          throw PlayerFailure(
            PlayerFailureKind.invalidSource,
            '媒体轨道与请求不符',
            generation,
          );
        }
        _requiresVideo = tracks.hasVideo;
        _requiresAudio = !plan.silent && tracks.hasAudio;
        final dimensions = _requiresVideo
            ? await operation.wait(backend.confirmVideo(operation))
            : null;
        operation.check();
        await _control(
          generation,
          (b) => b.setRate(_live ? 1 : _snapshot.rate),
        );
        var startupIntent = _intentRevision;
        do {
          startupIntent = _intentRevision;
          await finishSynchronizedStartup(
            shouldPlay: () => _snapshot.desiredPlaying,
            play: () => operation.wait(
              _control(
                generation,
                (b) => b.play(),
                allowed: () => _snapshot.desiredPlaying,
              ),
            ),
            pause: () =>
                operation.wait(_control(generation, (b) => b.pauseAndWait())),
            confirmReady: () async {
              if (_snapshot.desiredPlaying &&
                  _requiresAudio &&
                  !_audioConfirmed) {
                final intent = _intentRevision;
                final playOperation = _playOperation = PlaybackOperation(
                  generation,
                  operation.remaining,
                );
                try {
                  await playOperation.wait(backend.confirmAudio(playOperation));
                  if (intent == _intentRevision) _audioConfirmed = true;
                } on SourceSuperseded {
                  operation.check();
                }
              }
              if (_requiresVideo) {
                await operation.wait(backend.confirmPresentation(operation));
              }
            },
            restoreVolume: () async {},
            checkActive: operation.check,
          );
        } while (startupIntent != _intentRevision);
        await operation.wait(_restoreVolume(generation));
        operation.check();
        _opening = false;
        _audioBudget = operation.remaining;
        if (!_requiresAudio || _audioConfirmed) _output.clearRetainedFrame();
        _publish(
          _snapshot.copyWith(
            phase: PlaybackPhase.ready,
            position: tracks.position,
            duration: _live
                ? Duration.zero
                : _snapshot.duration > Duration.zero
                ? _snapshot.duration
                : tracks.duration,
            videoDimensions: dimensions ?? tracks.dimensions,
            rate: _live ? 1 : _snapshot.rate,
          ),
        );
        if (!_current(generation, backend)) return;
        _publish(_snapshot.copyWith(phase: _phase()));
        if (!_current(generation, backend)) return;
        _startSampling(generation);
        _diagnose(PlayerDiagnosticKind.openReady);
      } on SourceSuperseded {
        // The queued lifecycle operation owns release; don't dispose a newer source.
      } on Object catch (error) {
        if (!_current(generation)) return;
        operation.cancel();
        final failure = await _fail(
          error is PlayerFailure
              ? error.kind
              : PlayerFailureKind.nativePlayback,
          interruptNative: true,
        );
        final releasing = _release();
        // Disposal is still required after a failed prepare. Retain a rejected
        // release barrier instead of silently allocating a replacement.
        final remaining = operation.budget - operation.elapsed;
        if (remaining > Duration.zero) {
          try {
            await releasing.timeout(remaining);
          } on TimeoutException {
            // The release stays owned after the open deadline expires.
          }
        }
        throw failure;
      } finally {
        if (_current(generation)) _opening = false;
      }
    });
  }

  PlaybackPhase _phase() => !_snapshot.desiredPlaying
      ? PlaybackPhase.paused
      : (_snapshot.isBuffering || _snapshot.isSeeking)
      ? PlaybackPhase.buffering
      : PlaybackPhase.playing;

  Future<void> _restoreVolume(int generation) async {
    await _control(generation, (backend) async {
      // Read the latest user setting at dispatch, after all earlier mute writes.
      await backend.setGainDb(_gainDb);
      if (!_current(generation, backend)) return;
      await backend.setVolume(_preview ? 0 : _snapshot.volume);
      if (_current(generation, backend)) _muted = false;
    });
  }

  void _event(BackendEvent event, int generation, PlaybackBackend backend) {
    if (!_current(generation, backend)) return;
    if (event.kind == BackendEventKind.failure &&
        event.failureKind == PlayerFailureKind.nativeProcessExited) {
      if (_failing != null) return;
      _diagnose(
        PlayerDiagnosticKind.nativeProcessExited,
        failureKind: event.failureKind,
      );
      unawaited(_fail(event.failureKind));
      return;
    }
    if ((_opening || _confirmingAudio) &&
        event.kind == BackendEventKind.sample) {
      _publish(
        _snapshot.copyWith(
          duration: _live
              ? Duration.zero
              : (event.duration ?? Duration.zero) > Duration.zero
              ? event.duration
              : null,
          videoDimensions: event.dimensions,
        ),
      );
      return;
    }
    if ((_opening || _confirmingAudio) &&
        event.kind == BackendEventKind.buffering) {
      _publish(_snapshot.copyWith(isBuffering: event.value ?? false));
      return;
    }
    if (_terminal || _opening || _snapshot.isSeeking || _failing != null) {
      return;
    }
    switch (event.kind) {
      case BackendEventKind.sample:
        _publish(
          _snapshot.copyWith(
            position: event.position,
            duration: _live ? Duration.zero : event.duration,
            buffered: _buffered(event.position, event.buffered),
            videoDimensions: event.dimensions,
          ),
        );
      case BackendEventKind.buffering:
        _publish(
          _snapshot.copyWith(
            isBuffering: event.value ?? false,
            phase: !_snapshot.desiredPlaying
                ? PlaybackPhase.paused
                : (event.value ?? false)
                ? PlaybackPhase.buffering
                : PlaybackPhase.playing,
          ),
        );
      case BackendEventKind.playing:
        // Native state is evidence, never a new user intent. A delayed play
        // callback cannot revoke pause or resurrect a terminal source.
        if (!_snapshot.desiredPlaying && event.value == true) {
          unawaited(_control(generation, (b) => b.pauseAndWait()));
        }
      case BackendEventKind.ended:
        final position = event.position ?? _snapshot.position;
        if (!_live &&
            _snapshot.desiredPlaying &&
            _snapshot.duration > Duration.zero &&
            _snapshot.duration - position > const Duration(milliseconds: 500)) {
          final revision = _seekRevision;
          _diagnose(
            PlayerDiagnosticKind.playbackStalled,
            failureKind: PlayerFailureKind.videoInterrupted,
            interruption: NativePlaybackInterruption(
              kind: PlayerFailureKind.videoInterrupted,
              position: position,
              reason: PlaybackStallReason.videoBuffer,
              stalledFor: Duration.zero,
            ),
          );
          if (!_current(generation, backend) || revision != _seekRevision) {
            return;
          }
          unawaited(_fail(PlayerFailureKind.videoInterrupted));
          return;
        }
        _timer?.cancel();
        _timer = null;
        _health.reset();
        _publish(
          _snapshot.copyWith(
            phase: PlaybackPhase.ended,
            position: position,
            desiredPlaying: false,
            isBuffering: false,
            isSeeking: false,
          ),
        );
      case BackendEventKind.warning:
        _errors.report(_snapshot);
      case BackendEventKind.failure:
        unawaited(_fail(event.failureKind));
    }
  }

  void _startSampling(int generation) {
    if (!_current(generation) || _terminal || _timer != null) return;
    _timer = Timer.periodic(NativePlaybackHealth.sampleInterval, (_) {
      final backend = _backend;
      if (!_current(generation) ||
          backend == null ||
          _opening ||
          _confirmingAudio ||
          _snapshot.isSeeking ||
          _terminal ||
          _failing != null) {
        return;
      }
      final sample = backend.sampleHealth();
      _publish(
        _snapshot.copyWith(
          position: sample.position,
          buffered: _buffered(sample.position, sample.buffered),
        ),
      );
      if (!_current(generation, backend) || _terminal || _snapshot.isSeeking) {
        return;
      }
      final interruption = _health.update(
        // Transport cache describes both tracks. The existing video underrun
        // check must keep using the native video endpoint, not the smaller
        // audio endpoint displayed by the timeline.
        _dashBuffer == null
            ? _snapshot
            : _snapshot.copyWith(buffered: sample.buffered),
        monotonicNow?.call() ?? _clock.elapsed,
        paired: sample.comparePairedClocks,
        audioPosition: sample.audioPosition,
        audioFrames: sample.audioFrames,
        videoFrames: sample.videoFrames,
        videoStarved: sample.videoStarved,
        requiresAudio: _requiresAudio,
        requiresVideo: _requiresVideo,
      );
      if (interruption != null) {
        _diagnose(
          PlayerDiagnosticKind.playbackStalled,
          failureKind: interruption.kind,
          interruption: interruption,
        );
        unawaited(_fail(interruption.kind));
      }
    });
  }

  Duration? _buffered(Duration? position, Duration? nativeEnd) {
    final buffer = _dashBuffer;
    if (buffer == null) return nativeEnd;
    return buffer.commonBuffered(
      position ?? _snapshot.position,
      nativeEnd ?? _snapshot.buffered,
    );
  }

  void _resetHealth() {
    _health.reset();
    _backend?.resetHealth();
  }

  Future<PlayerFailure> _fail(
    PlayerFailureKind kind, {
    bool interruptNative = false,
  }) {
    if (_failing case final failing?) return failing;
    final generation = _generation;
    final backend = _backend;
    final failure = PlayerFailure(kind, switch (kind) {
      PlayerFailureKind.nativeProcessExited => '播放器异常退出，请退出播放页后重新打开',
      PlayerFailureKind.unsupportedVideoColor => '当前播放后端无法正确显示此视频色彩',
      PlayerFailureKind.videoInterrupted => '视频加载中断，已暂停播放',
      PlayerFailureKind.invalidSource => '无效的媒体源或播放参数',
      PlayerFailureKind.unsupportedHeaders => '不支持的媒体请求头',
      _ => '音视频播放失败，请重新加载或切换线路',
    }, generation);
    final result = Completer<PlayerFailure>();
    _failing = result.future;
    if (kind == PlayerFailureKind.videoInterrupted) {
      _diagnose(PlayerDiagnosticKind.videoInterrupted, failureKind: kind);
    }
    _playOperation?.cancel();
    _seekOperation?.cancel();
    _timer?.cancel();
    _timer = null;
    _errors.reset();
    _resetHealth();
    unawaited(() async {
      var released = false;
      try {
        if (backend != null && kind != PlayerFailureKind.nativeProcessExited) {
          var paused = false;
          try {
            paused = await backend.pauseAndWait().timeout(
              const Duration(seconds: 2),
            );
          } on Object {
            // No complete native pause was acknowledged.
          }
          if (_current(generation, backend)) await _output.retainFrame();
          if (!_current(generation, backend)) return;
          // Failed commands must still retire pending native I/O. Capture the
          // visible frame first so interrupting that slot cannot blank it.
          if (paused && interruptNative) _interrupt(backend);
          if (!paused) {
            _interrupt(backend);
            try {
              await _release();
            } on Object {
              // Retain the rejected release barrier; never allocate over it.
            }
            released = _backend == null;
          }
        }
        if (_current(generation, released ? null : backend)) {
          _publish(
            _snapshot.copyWith(
              phase: PlaybackPhase.failed,
              desiredPlaying: false,
              isBuffering: false,
              isSeeking: false,
            ),
          );
          if (_current(generation, released ? null : backend)) {
            _failures.add(failure);
            _diagnose(PlayerDiagnosticKind.failed, failureKind: kind);
          }
        }
      } finally {
        result.complete(failure);
      }
    }());
    return result.future;
  }

  @override
  Future<void> play() {
    if (_disposed ||
        _failing != null ||
        _snapshot.phase == PlaybackPhase.idle) {
      return Future.value();
    }
    ++_intentRevision;
    _publish(_snapshot.copyWith(desiredPlaying: true));
    if (_opening || _snapshot.isSeeking) return Future.value();
    return _runPlay(_generation);
  }

  Future<void> _runPlay(int generation) async {
    final backend = _backend;
    if (!_current(generation) || backend == null || !_snapshot.desiredPlaying) {
      return;
    }
    _playOperation?.cancel();
    final operation = _playOperation = PlaybackOperation(
      generation,
      !_audioConfirmed && _requiresAudio
          ? _audioBudget
          : const Duration(seconds: 15),
    );
    final intent = _intentRevision;
    bool allowed() =>
        !operation.isCancelled &&
        _snapshot.desiredPlaying &&
        intent == _intentRevision &&
        !_snapshot.isSeeking;
    try {
      if (!_audioConfirmed && _requiresAudio) {
        _muted = true;
        await operation.wait(
          _control(generation, (b) => b.setVolume(0), allowed: allowed),
        );
        await finishSynchronizedStartup(
          shouldPlay: allowed,
          play: () => operation.wait(
            _control(generation, (b) => b.play(), allowed: allowed),
          ),
          pause: () =>
              operation.wait(_control(generation, (b) => b.pauseAndWait())),
          confirmReady: () => operation.wait(backend.confirmAudio(operation)),
          restoreVolume: () => operation.wait(_restoreVolume(generation)),
          checkActive: operation.check,
        );
        _audioConfirmed = true;
      } else {
        if (_muted) await operation.wait(_restoreVolume(generation));
        await operation.wait(
          _control(generation, (b) => b.play(), allowed: allowed),
        );
        operation.check();
      }
      if (!_current(generation, backend) || !allowed()) return;
      _output.clearRetainedFrame();
      _resetHealth();
      _publish(_snapshot.copyWith(phase: _phase()));
      _startSampling(generation);
    } on SourceSuperseded {
      final failing = _failing;
      if (_current(generation, backend) && failing != null) throw await failing;
      return;
    } on Object catch (error) {
      if (_current(generation, backend) && !operation.isCancelled) {
        throw await _fail(
          error is PlayerFailure
              ? error.kind
              : PlayerFailureKind.nativePlayback,
          interruptNative: true,
        );
      }
    } finally {
      if (_current(generation, backend) && !_audioConfirmed && _requiresAudio) {
        _audioBudget -= operation.elapsed;
      }
    }
  }

  @override
  Future<void> pause() {
    if (_disposed || _snapshot.phase == PlaybackPhase.idle) {
      return Future.value();
    }
    ++_intentRevision;
    _playOperation?.cancel();
    final generation = _generation;
    _resetHealth();
    _publish(
      _snapshot.copyWith(
        desiredPlaying: false,
        phase: _terminal || _opening ? _snapshot.phase : PlaybackPhase.paused,
      ),
    );
    return _control(generation, (b) => b.pauseAndWait());
  }

  @override
  Future<void> seek(Duration target) {
    if (target < Duration.zero) throw ArgumentError.value(target, 'target');
    if (_disposed ||
        _live ||
        _failing != null ||
        _snapshot.phase == PlaybackPhase.idle) {
      return Future.value();
    }
    final generation = _generation;
    final revision = ++_seekRevision;
    final pending = _seekOperation;
    pending?.cancel();
    if (pending != null) _backend?.cancelSeek();
    _playOperation?.cancel();
    final next = _seeks.then((_) async {
      // Opening seeks coalesce but cannot hold up open/stop/pause dispatch.
      await _lifecycle;
      final backend = _backend;
      if (!_current(generation) ||
          revision != _seekRevision ||
          backend == null ||
          _failing != null) {
        return;
      }
      final operation = _seekOperation = PlaybackOperation(
        generation,
        backend.seekTimeout,
        revision: revision,
      );
      _muted = true;
      _resetHealth();
      _publish(
        _snapshot.copyWith(
          isSeeking: true,
          phase: _snapshot.desiredPlaying
              ? PlaybackPhase.buffering
              : PlaybackPhase.paused,
        ),
      );
      if (!_current(generation, backend) || revision != _seekRevision) return;
      try {
        await operation.wait(_control(generation, (b) => b.setVolume(0)));
        await operation.wait(_control(generation, (b) => b.pauseAndWait()));
        final position = await operation.wait(
          backend.seekTo(target, operation),
        );
        if (!_current(generation, backend) || revision != _seekRevision) return;
        if (!_snapshot.desiredPlaying) _output.clearRetainedFrame();
        _resetHealth();
        _publish(
          _snapshot.copyWith(
            position: position,
            isSeeking: false,
            isBuffering: false,
            phase: PlaybackPhase.paused,
          ),
        );
        if (!_current(generation, backend) || revision != _seekRevision) return;
        if (_snapshot.desiredPlaying) {
          await _runPlay(generation);
        } else {
          await operation.wait(_restoreVolume(generation));
        }
        _startSampling(generation);
      } on SourceSuperseded {
        final failing = _failing;
        if (_current(generation, backend) && failing != null) {
          throw await failing;
        }
        return;
      } on Object catch (error) {
        if (_current(generation, backend) &&
            revision == _seekRevision &&
            !operation.isCancelled) {
          throw await _fail(
            error is PlayerFailure
                ? error.kind
                : PlayerFailureKind.nativePlayback,
            interruptNative: true,
          );
        }
      } finally {
        if (identical(operation, _seekOperation)) _seekOperation = null;
      }
    });
    _seeks = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<void> setRate(double rate) {
    if (!rate.isFinite || rate <= 0) throw ArgumentError.value(rate, 'rate');
    if (_disposed || _live) return Future.value();
    _resetHealth();
    _publish(_snapshot.copyWith(rate: rate));
    if (_opening) return Future.value();
    return _control(_generation, (b) => b.setRate(_snapshot.rate));
  }

  @override
  Future<void> setVolume(double volume) {
    if (!volume.isFinite || volume < 0 || volume > 100) {
      throw ArgumentError.value(volume, 'volume');
    }
    if (_disposed) return Future.value();
    _publish(_snapshot.copyWith(volume: volume));
    if (_opening) return Future.value();
    return _control(
      _generation,
      (b) => b.setVolume(_muted || _preview ? 0 : _snapshot.volume),
    );
  }

  @override
  Future<void> setAudioGain(double gainDb) async {
    if (!ValidatedSource.validGain(gainDb)) {
      throw ArgumentError.value(gainDb, 'gainDb');
    }
    final generation = _generation;
    final revision = ++_gainRevision;
    if (_opening) {
      _gainDb = gainDb;
      return;
    }
    final start = _gainDb;
    final from = math.pow(10, start / 20).toDouble();
    final to = math.pow(10, gainDb / 20).toDouble();
    for (var step = 1; step <= 9; step++) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (!_current(generation) || revision != _gainRevision) return;
      final amplitude = to + (from - to) * math.exp(-step * 10 / 15);
      _gainDb = step == 9 ? gainDb : 20 * math.log(amplitude) / math.ln10;
      await _control(
        generation,
        (b) => b.setGainDb(_gainDb),
        allowed: () => revision == _gainRevision,
      );
    }
  }

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async {
    final generation = _generation;
    final backend = _backend;
    if (_disposed || _opening || backend == null) return null;
    try {
      final info = await backend
          .inspectPlaybackInformation(generation)
          .timeout(const Duration(seconds: 1));
      return _current(generation, backend)
          ? info?.withGeneration(generation)
          : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> stop() {
    if (_disposed) return _disposal ?? Future.value();
    _invalidate();
    final generation = _generation;
    _opening = false;
    return _serial(() async {
      if (!_current(generation)) return;
      await _release();
      if (_current(generation)) {
        _publish(
          PlaybackSnapshot(phase: PlaybackPhase.idle, generation: generation),
        );
      }
    });
  }

  @override
  Future<void> dispose() {
    if (_disposal case final disposal?) return disposal;
    final completed = Completer<void>();
    _disposal = completed.future;
    _disposed = true;
    _invalidate();
    final releasing = _serial(() async {
      await _release();
      _output.dispose();
      _clock.stop();
      await _snapshots.close();
      await _failures.close();
    });
    unawaited(
      releasing.then<void>(
        (_) => completed.complete(),
        onError: (Object error, StackTrace stack) =>
            completed.completeError(error, stack),
      ),
    );
    return completed.future;
  }
}
