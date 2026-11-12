import 'dart:async';
import 'dart:math' as math;

import 'native_error_monitor.dart';
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
    this.seekCoalescingDelay = Duration.zero,
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
  final Duration seekCoalescingDelay;
  final _output = SwitchingVideoOutput();
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  late final NativeErrorMonitor _errors;
  PlaybackBackend? _backend;
  PlaybackBackend? get activeBackend => _backend;
  Future<PlaybackBackend>? _allocation;
  StreamSubscription<BackendEvent>? _subscription;
  Future<void> _lifecycle = Future.value();
  Future<void> _controls = Future.value();
  _SeekRequest? _pendingSeek;
  bool _drainingSeeks = false;
  Future<void> _seekRetirement = Future.value();
  Future<void>? _disposal;
  Future<void>? _releaseBarrier;
  Future<PlayerFailure>? _failing;
  PlaybackOperation? _openOperation, _playOperation, _seekOperation;
  PlaybackOperation? _nativeSeekOperation;
  int _generation = 0,
      _seekRevision = 0,
      _intentRevision = 0,
      _gainRevision = 0;
  bool _disposed = false, _opening = false;
  bool _waitingForPair = false, _backendBuffering = false;
  bool _requiresAudio = false, _requiresVideo = false, _audioConfirmed = false;
  bool _live = false, _preview = false;
  double _gainDb = 0;
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
      _waitingForPair ||
      _requiresAudio &&
          !_audioConfirmed &&
          _playOperation?.isCancelled == false;
  bool get _seeking =>
      _pendingSeek != null || _seekOperation?.isCancelled == false;

  // Native demuxers own buffering. All event and polling samples use the same
  // media-time endpoint; never infer cache from bytes, bitrate or old seeks.
  PlaybackSnapshot _timeline({
    Duration? position,
    Duration? duration,
    Duration? buffered,
    VideoDimensions? dimensions,
  }) {
    final length = _live ? Duration.zero : duration ?? _snapshot.duration;
    Duration clamp(Duration value) {
      if (value < Duration.zero) return Duration.zero;
      return length > Duration.zero && value > length ? length : value;
    }

    final current = clamp(position ?? _snapshot.position);
    final end = clamp(buffered ?? _snapshot.buffered);
    return _snapshot.copyWith(
      position: current,
      duration: length < Duration.zero ? Duration.zero : length,
      buffered: end < current ? current : end,
      videoDimensions: dimensions,
    );
  }

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
    PlaybackStallReason? stallReason,
    int? nativeErrorCode,
  }) => onDiagnostic?.call(
    PlayerDiagnosticEvent(
      kind: kind,
      snapshot: _snapshot,
      nativeError: nativeError,
      nativeErrorCode: nativeErrorCode,
      failureKind: failureKind,
      stallReason: stallReason,
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
    try {
      backend?.interrupt();
    } on Object {
      // Disposal remains the final barrier even if stop/interrupt is rejected.
    }
  }

  void _invalidate({
    bool retainPresentation = false,
    bool keepBackend = false,
  }) {
    ++_generation;
    ++_intentRevision;
    ++_seekRevision;
    ++_gainRevision;
    _openOperation?.cancel();
    _playOperation?.cancel();
    _seekOperation?.cancel();
    _seekRetirement = Future.value();
    _pendingSeek?.complete();
    _pendingSeek = null;
    _errors.reset();
    if (!retainPresentation) {
      _output.clearRetainedFrame();
      if (!keepBackend) _interrupt(_backend);
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
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    if (_disposed) {
      return Future.error(
        PlayerFailure(PlayerFailureKind.disposed, '播放器已关闭', _generation),
      );
    }
    final previous = _snapshot;
    final reuseCandidate =
        !_opening &&
        !_seeking &&
        _failing == null &&
        _releaseBarrier == null &&
        _backend is ReusablePlaybackBackend &&
        const {
          PlaybackPhase.ready,
          PlaybackPhase.playing,
          PlaybackPhase.paused,
          PlaybackPhase.buffering,
          PlaybackPhase.ended,
        }.contains(previous.phase);
    _invalidate(
      retainPresentation: options.retainPresentation,
      keepBackend: reuseCandidate,
    );
    final generation = _generation;
    final operation = _openOperation = PlaybackOperation(
      generation,
      options.openTimeout,
    );
    _opening = true;
    _waitingForPair = false;
    _backendBuffering = false;
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
        if (!reuseCandidate) _interrupt(_backend);
      }
      _diagnose(PlayerDiagnosticKind.openStarted);
      try {
        final plan = ValidatedSource.validate(
          source,
          options,
          generation,
          schemes: schemes,
        );
        operation.check();
        _live = plan.live;
        _preview = source is DashVideoSource;
        _audioConfirmed = false;
        await _subscription?.cancel();
        _subscription = null;
        final existing = _backend;
        final reusable = existing is ReusablePlaybackBackend
            ? existing as ReusablePlaybackBackend
            : null;
        if (reuseCandidate && reusable != null && reusable.canReuse(plan)) {
          await operation.wait(_controls);
          await operation.wait(reusable.resetForNextSource(operation));
        } else {
          await _release();
          operation.check();
          final creating = _allocation =
              Future<PlaybackBackend>.sync(createBackend).then((value) {
                _backend = value;
                return value;
              });
          await operation.wait(creating);
          _allocation = null;
        }
        final backend = _backend!;
        _output.bind(backend.videoOutput);
        _subscription = backend.events.listen(
          (event) => _event(event, generation, backend),
        );
        final tracks = await operation.wait(
          backend.preparePaused(plan, operation),
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
        _audioConfirmed = !_requiresAudio;
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
            shouldPlay: () =>
                startupIntent == _intentRevision &&
                _snapshot.desiredPlaying &&
                _pendingSeek == null,
            play: () => operation.wait(
              _control(
                generation,
                (b) => b.play(),
                allowed: () =>
                    startupIntent == _intentRevision &&
                    _snapshot.desiredPlaying &&
                    _pendingSeek == null,
              ),
            ),
            pause: () =>
                operation.wait(_control(generation, (b) => b.pauseAndWait())),
            confirmReady: () async {
              if (_snapshot.desiredPlaying &&
                  _pendingSeek == null &&
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
            applyVolume: () => operation.wait(_applyVolume(generation)),
            checkActive: operation.check,
          );
        } while (startupIntent != _intentRevision);
        operation.check();
        _opening = false;
        if (!_requiresAudio || _audioConfirmed) _output.clearRetainedFrame();
        _publish(
          _timeline(
            position: tracks.position,
            duration: _live
                ? Duration.zero
                : _snapshot.duration > Duration.zero
                ? _snapshot.duration
                : tracks.duration,
            dimensions: dimensions ?? tracks.dimensions,
          ).copyWith(
            phase: PlaybackPhase.ready,
            rate: _live ? 1 : _snapshot.rate,
          ),
        );
        if (!_current(generation, backend)) return;
        _publish(_snapshot.copyWith(phase: _phase()));
        if (!_current(generation, backend)) return;
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
      : (_backendBuffering ||
            _waitingForPair ||
            _snapshot.isSeeking ||
            _pendingSeek != null)
      ? PlaybackPhase.buffering
      : PlaybackPhase.playing;

  Future<void> _applyVolume(int generation) async {
    await _control(generation, (backend) async {
      // Read the latest user settings while both native tracks are paused.
      await backend.setGainDb(_gainDb);
      if (!_current(generation, backend)) return;
      await backend.setVolume(_preview ? 0 : _snapshot.volume);
    });
  }

  void _event(BackendEvent event, int generation, PlaybackBackend backend) {
    if (!_current(generation, backend)) return;
    if (event.kind == BackendEventKind.buffering) {
      _backendBuffering = event.value ?? false;
    }
    if (event.kind == BackendEventKind.ended &&
        (_pendingSeek != null || _snapshot.isSeeking)) {
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
      _backendBuffering = event.value ?? false;
      _publish(_snapshot.copyWith(isBuffering: _backendBuffering));
      return;
    }
    if (_terminal ||
        _opening ||
        _pendingSeek != null ||
        _snapshot.isSeeking ||
        _failing != null) {
      return;
    }
    switch (event.kind) {
      case BackendEventKind.sample:
        _publish(
          _timeline(
            position: event.position,
            duration: _live ? Duration.zero : event.duration,
            buffered: event.buffered,
            dimensions: event.dimensions,
          ),
        );
      case BackendEventKind.buffering:
        _backendBuffering = event.value ?? false;
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
            stallReason: PlaybackStallReason.videoBuffer,
          );
          if (!_current(generation, backend) || revision != _seekRevision) {
            return;
          }
          unawaited(_fail(PlayerFailureKind.videoInterrupted));
          return;
        }
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
        if (event.stallReason case final reason?) {
          _diagnose(
            PlayerDiagnosticKind.playbackStalled,
            failureKind: event.failureKind,
            stallReason: reason,
          );
        }
        unawaited(_fail(event.failureKind));
    }
  }

  Future<PlayerFailure> _fail(
    PlayerFailureKind kind, {
    bool interruptNative = false,
  }) {
    if (_failing case final failing?) return failing;
    final generation = _generation;
    final backend = _backend;
    final failure = PlayerFailure(kind, switch (kind) {
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
    _errors.reset();
    unawaited(() async {
      var released = false;
      try {
        if (backend != null) {
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
    if (_opening || _seeking) return Future.value();
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
      _seekOperation?.remaining ?? const Duration(seconds: 15),
    );
    final intent = _intentRevision;
    bool allowed() =>
        !operation.isCancelled &&
        _snapshot.desiredPlaying &&
        intent == _intentRevision &&
        !_snapshot.isSeeking;
    try {
      if (!_audioConfirmed) {
        _waitingForPair = true;
        _publish(_snapshot.copyWith(phase: _phase()));
        // preparePaused already stopped the pair and applied the user settings.
        // A first play only needs the evidence deferred by a paused open.
        if (_requiresAudio) {
          await operation.wait(backend.confirmAudio(operation));
        }
        if (_requiresVideo) {
          await operation.wait(backend.confirmPresentation(operation));
        }
      }
      await operation.wait(
        _control(generation, (b) => b.play(), allowed: allowed),
      );
      if (!_current(generation, backend) || !allowed()) return;
      _audioConfirmed = true;
      _waitingForPair = false;
      _output.clearRetainedFrame();
      _publish(
        _snapshot.copyWith(phase: _phase(), isBuffering: _backendBuffering),
      );
    } on SourceSuperseded {
      final failing = _failing;
      if (_current(generation, backend) && failing != null) throw await failing;
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
      if (_current(generation, backend) &&
          identical(operation, _playOperation)) {
        _waitingForPair = false;
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
    _waitingForPair = false;
    final generation = _generation;
    _publish(
      _snapshot.copyWith(
        desiredPlaying: false,
        isBuffering: _backendBuffering,
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
    final request = _SeekRequest(generation, ++_seekRevision, target);
    _pendingSeek?.complete();
    _pendingSeek = request;
    final pending = _seekOperation;
    if (pending != null && !pending.isCancelled) {
      pending.cancel();
      if (identical(pending, _nativeSeekOperation)) {
        _seekRetirement = () async {
          await _backend?.cancelSeek();
        }();
        unawaited(_seekRetirement.then<void>((_) {}, onError: (Object _) {}));
      }
    }
    _playOperation?.cancel();
    if (!_drainingSeeks) unawaited(_drainSeeks());
    return request.done.future;
  }

  Future<void> _drainSeeks() async {
    _drainingSeeks = true;
    try {
      while (_pendingSeek != null) {
        // Opening and gesture bursts retain one target, without allocating a
        // Future chain (or a native callback slot) for every pointer/key event.
        final lifecycle = _lifecycle;
        await lifecycle;
        if (!identical(lifecycle, _lifecycle)) continue;
        if (seekCoalescingDelay > Duration.zero) {
          await Future<void>.delayed(seekCoalescingDelay);
        }
        if (!identical(lifecycle, _lifecycle)) continue;
        final request = _pendingSeek;
        if (request == null) continue;
        _pendingSeek = null;
        try {
          await _seekTo(request);
          request.complete();
        } on Object catch (error, stack) {
          request.done.completeError(error, stack);
        }
      }
    } finally {
      _drainingSeeks = false;
    }
  }

  Future<void> _seekTo(_SeekRequest request) async {
    final generation = request.generation;
    final revision = request.revision;
    final backend = _backend;
    if (!_current(generation) ||
        revision != _seekRevision ||
        backend == null ||
        _failing != null) {
      return;
    }
    final duration = _snapshot.duration;
    final target = duration > Duration.zero && request.target > duration
        ? duration
        : request.target;
    final operation = _seekOperation = PlaybackOperation(
      generation,
      backend.seekTimeout,
      revision: revision,
    );
    _publish(
      _snapshot.copyWith(
        isSeeking: true,
        phase: _snapshot.phase == PlaybackPhase.ended
            ? PlaybackPhase.paused
            : null,
      ),
    );
    try {
      if (!_current(generation, backend) || revision != _seekRevision) return;
      await operation.wait(_seekRetirement);
      _nativeSeekOperation = operation;
      final position = await operation.wait(backend.seekTo(target, operation));
      if (identical(operation, _nativeSeekOperation)) {
        _nativeSeekOperation = null;
      }
      if (!_current(generation, backend) || revision != _seekRevision) return;
      if (!_snapshot.desiredPlaying) _output.clearRetainedFrame();
      // seekTo owns the native target barrier. Do not pause and prepare the
      // already-confirmed pair a second time when restoring playback intent.
      _audioConfirmed = true;
      _publish(
        _timeline(
          position: position,
          buffered: backend.buffered ?? position,
        ).copyWith(
          isSeeking: false,
          isBuffering: _backendBuffering,
          phase: !_snapshot.desiredPlaying
              ? PlaybackPhase.paused
              : _backendBuffering
              ? PlaybackPhase.buffering
              : PlaybackPhase.playing,
        ),
      );
      if (!_current(generation, backend) || revision != _seekRevision) return;
      if (_snapshot.desiredPlaying) {
        await _runPlay(generation);
      }
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
      if (identical(operation, _nativeSeekOperation)) {
        _nativeSeekOperation = null;
      }
      if (identical(operation, _seekOperation)) _seekOperation = null;
    }
  }

  @override
  Future<void> setRate(double rate) {
    if (!rate.isFinite || rate <= 0) throw ArgumentError.value(rate, 'rate');
    if (_disposed || _live) return Future.value();
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
      (b) => b.setVolume(_preview ? 0 : _snapshot.volume),
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

final class _SeekRequest {
  _SeekRequest(this.generation, this.revision, this.target);
  final int generation, revision;
  final Duration target;
  final done = Completer<void>();
  void complete() => done.complete();
}
