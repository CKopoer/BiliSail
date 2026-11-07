import 'dart:async';

import 'player_contract.dart';
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
  int _generation = 0;
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
    final generation = ++_generation;
    // Invalidate a pending child open before waiting for the command queue.
    final stopped = _requestStop();
    return _enqueue(() async {
      await stopped;
      await _release();
      if (_disposed || generation != _generation) return;
      _publish(
        PlaybackSnapshot(phase: PlaybackPhase.opening, generation: generation),
      );
      try {
        final selected = await createEngine();
        _engine = selected;
        if (_disposed || generation != _generation) {
          await _release();
          return;
        }
        _subscriptions.add(
          selected.snapshots.listen((snapshot) {
            if (!_disposed &&
                generation == _generation &&
                identical(_engine, selected)) {
              _publish(snapshot.copyWith(generation: generation));
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
        await selected.open(source, options);
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
    return _enqueue(() async {
      if (_disposed || generation != _generation) return;
      if (_engine case final engine?) await operation(engine);
    });
  }

  @override
  Future<void> play() => _command((engine) => engine.play());
  @override
  Future<void> pause() {
    // Revoke an in-flight play/audio-readiness wait before our queue drains.
    final paused = _engine?.pause() ?? Future<void>.value();
    return _enqueue(() => paused);
  }

  @override
  Future<void> seek(Duration target) =>
      _command((engine) => engine.seek(target));
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
    final generation = ++_generation;
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
    _disposed = true;
    ++_generation;
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
