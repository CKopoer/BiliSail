import 'dart:async';

import 'player_contract.dart';
import 'playback_backend.dart';
import 'native_readiness.dart';
import 'player_playback_information.dart';
import 'switching_video_output.dart';
import 'video_output.dart';

/// Resolves the saved backend on each open, after the old runtime is released.
/// A settings change never replaces the runtime of an already playing source.
final class ConfigurablePlayerEngine
    implements
        PlayerEngine,
        VideoOutputSource,
        AudioGainControl,
        PlayerInformationSource {
  ConfigurablePlayerEngine({required this.createEngine});

  final Future<PlayerEngine> Function() createEngine;
  final _output = SwitchingVideoOutput();
  final _snapshots = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final _failures = StreamController<PlayerFailure>.broadcast(sync: true);
  final _subscriptions = <StreamSubscription<Object?>>[];
  Future<void> _commands = Future.value();
  PlayerEngine? _engine;
  Future<PlayerEngine>? _creating;
  PlaybackOperation? _opening;
  bool _desiredPlaying = false;
  int _playRevision = 0;
  int _generation = 0;
  int _seekRevision = 0;
  bool _disposed = false;
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
      _engine?.capabilities ??
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);

  void _publish(PlaybackSnapshot snapshot) {
    _snapshot = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async {
    final engine = _engine;
    final generation = _generation;
    final source = switch (engine) {
      PlayerInformationSource source => source,
      _ => null,
    };
    if (_disposed || source == null) return null;
    final information = await source.inspectPlaybackInformation();
    if (_disposed || generation != _generation || !identical(engine, _engine)) {
      return null;
    }
    return information?.withGeneration(generation);
  }

  Future<void> _release() async {
    _output.bind(null);
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    final creating = _creating;
    if (creating != null) {
      try {
        await creating;
      } on Object {
        // A rejected factory returned no engine to release.
      }
      _creating = null;
    }
    final old = _engine;
    // Retain a failed release so a later open cannot overlap an uncertain core.
    if (old != null) await old.dispose();
    _engine = null;
  }

  Future<void> _requestStop() async {
    try {
      await _engine?.stop();
    } on Object {
      // Disposal is the final release barrier even if stop itself failed.
    }
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final next = _commands.then((_) => operation());
    _commands = next.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return next;
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) {
    if (_disposed) {
      return Future.error(
        const PlayerFailure(PlayerFailureKind.disposed, '播放器已关闭', 0),
      );
    }
    final previous = _snapshot;
    final generation = ++_generation;
    _opening?.cancel();
    final operation = _opening = PlaybackOperation(
      generation,
      options.openTimeout,
    );
    _desiredPlaying = options.play;
    // Invalidate a pending child open before waiting for the command queue.
    if (!options.retainPresentation) _output.clearRetainedFrame();
    final stopped = options.retainPresentation
        ? () async {
            await _output.retainFrame();
            if (!_disposed && generation == _generation) await _requestStop();
          }()
        : _requestStop();
    return _enqueue(() async {
      await stopped;
      await _release();
      if (_disposed || generation != _generation) return;
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
          desiredPlaying: _desiredPlaying,
          rate: options.rate,
          volume: options.volume,
        ),
      );
      try {
        if (_disposed || generation != _generation) return;
        final creating = _creating = createEngine().then((selected) {
          _engine = selected;
          return selected;
        });
        final selected = await operation.wait(creating);
        _creating = null;
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        _subscriptions.add(
          selected.snapshots.listen((snapshot) {
            if (!_disposed &&
                generation == _generation &&
                identical(_engine, selected)) {
              var value = snapshot.copyWith(generation: generation);
              if (options.retainPresentation) {
                value = value.copyWith(
                  position: value.phase == PlaybackPhase.opening
                      ? options.startPosition
                      : null,
                  duration: value.duration <= Duration.zero
                      ? previous.duration
                      : null,
                  videoDimensions:
                      value.videoDimensions ?? previous.videoDimensions,
                );
              }
              if (value.phase == PlaybackPhase.playing &&
                  !value.isBuffering &&
                  !value.isSeeking) {
                _output.clearRetainedFrame();
              }
              _publish(value);
            }
          }),
        );
        _subscriptions.add(
          selected.failures.listen((failure) {
            if (!_disposed &&
                generation == _generation &&
                identical(_engine, selected)) {
              _failures.add(
                PlayerFailure(failure.kind, failure.message, generation),
              );
            }
          }),
        );
        if (selected case VideoOutputSource source) {
          _output.bind(source.videoOutput);
        }
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        await selected.open(
          source,
          OpenOptions(
            startPosition: options.startPosition,
            play: _desiredPlaying,
            rate: options.rate,
            volume: options.volume,
            audioGainDb: options.audioGainDb,
            videoDecoding: options.videoDecoding,
            androidVideoOutput: options.androidVideoOutput,
            openTimeout: operation.remaining,
            maxBufferAhead: options.maxBufferAhead,
            retainPresentation: options.retainPresentation,
          ),
        );
      } on SourceSuperseded {
        return;
      } on Object catch (error) {
        if (_disposed || generation != _generation) return;
        final failure = error is PlayerFailure
            ? PlayerFailure(error.kind, error.message, generation)
            : PlayerFailure(
                PlayerFailureKind.nativePlayback,
                '无法启动所选播放后端',
                generation,
              );
        _publish(_snapshot.copyWith(phase: PlaybackPhase.failed));
        throw failure;
      }
    });
  }

  Future<void> _command(Future<void> Function(PlayerEngine) operation) {
    final generation = _generation;
    final completed = Completer<void>();
    // Serialize dispatch with open/release, not the backend's readiness waits.
    // Each backend owns its command queue; it must receive a newer seek while
    // the old target is still loading so it can cancel that native read.
    unawaited(
      _enqueue(() async {
        final engine = _engine;
        if (_disposed || generation != _generation || engine == null) {
          completed.complete();
          return;
        }
        completed.complete(
          _withGeneration(
            Future<void>.sync(() => operation(engine)),
            generation,
          ),
        );
      }),
    );
    return completed.future;
  }

  Future<void> _withGeneration(Future<void> command, int generation) async {
    try {
      await command;
    } on PlayerFailure catch (failure) {
      throw PlayerFailure(failure.kind, failure.message, generation);
    }
  }

  @override
  Future<void> play() {
    _desiredPlaying = true;
    final revision = ++_playRevision;
    return _command((engine) async {
      if (revision == _playRevision && _desiredPlaying) await engine.play();
    });
  }

  @override
  Future<void> pause() {
    _desiredPlaying = false;
    ++_playRevision;
    final generation = _generation;
    final engine = _engine;
    // Revoke an in-flight play/audio-readiness wait before our queue drains.
    // Its completion must not block dispatch of a later superseding seek.
    return _withGeneration(
      Future<void>.sync(() => engine?.pause()),
      generation,
    );
  }

  @override
  Future<void> seek(Duration target) {
    final revision = ++_seekRevision;
    final generation = _generation;
    return _command((engine) async {
      if (revision != _seekRevision) return;
      await engine.seek(target < Duration.zero ? Duration.zero : target);
      if (!_disposed &&
          generation == _generation &&
          revision == _seekRevision &&
          !_desiredPlaying) {
        _output.clearRetainedFrame();
      }
    });
  }

  @override
  Future<void> setRate(double rate) =>
      _command((engine) => engine.setRate(rate));
  @override
  Future<void> setVolume(double volume) =>
      _command((engine) => engine.setVolume(volume));
  @override
  Future<void> setAudioGain(double gainDb) => _command((engine) async {
    if (engine case AudioGainControl control) {
      await control.setAudioGain(gainDb);
    }
  });

  @override
  Future<void> stop() {
    if (_disposed) return _disposal ?? Future.value();
    _output.clearRetainedFrame();
    final generation = ++_generation;
    _opening?.cancel();
    final stopped = _requestStop();
    return _enqueue(() async {
      await stopped;
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
    _output.clearRetainedFrame();
    _disposed = true;
    ++_generation;
    _opening?.cancel();
    final stopped = _requestStop();
    return _disposal = _enqueue(() async {
      await stopped;
      await _release();
      _output.dispose();
      await _snapshots.close();
      await _failures.close();
    });
  }
}
