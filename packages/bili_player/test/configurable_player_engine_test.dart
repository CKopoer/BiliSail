import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Engine extends Fake
    implements PlayerEngine, PlayerInformationSource {
  final events = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final errors = StreamController<PlayerFailure>.broadcast(sync: true);
  bool disposed = false;
  Completer<void>? release;
  bool failRelease = false;
  bool failStop = false;
  Completer<void>? playGate;
  Completer<PlayerPlaybackInformation?>? informationGate;
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async =>
      informationGate?.future ??
      const PlayerPlaybackInformation(generation: 1, backend: 'test');
  @override
  Future<void> play() async => await playGate?.future;
  @override
  Future<void> pause() async {
    final gate = playGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Stream<PlaybackSnapshot> get snapshots => events.stream;
  @override
  Stream<PlayerFailure> get failures => errors.stream;
  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    events.add(
      PlaybackSnapshot(
        phase: options.play ? PlaybackPhase.playing : PlaybackPhase.paused,
        generation: 1,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (failStop) throw StateError('stop failed');
  }

  @override
  Future<void> dispose() async {
    await release?.future;
    if (failRelease) throw StateError('release failed');
    disposed = true;
  }

  Future<void> closeStreams() async {
    await events.close();
    await errors.close();
  }
}

void main() {
  final source = ProgressiveSource(
    MediaTrack(uri: Uri.file('video.mp4'), requestPolicy: MediaRequestPolicy()),
  );
  test(
    'information uses the wrapper generation after switching backends',
    () async {
      final child = _Engine();
      final engine = ConfigurablePlayerEngine(createEngine: () async => child);
      await engine.open(source, const OpenOptions());
      await engine.stop();
      await engine.open(source, const OpenOptions());
      final info = await engine.inspectPlaybackInformation();
      expect(info?.backend, 'test');
      expect(info?.generation, engine.currentSnapshot.generation);
      expect(info?.generation, greaterThan(1));
      await engine.dispose();
      await child.closeStreams();
    },
  );
  test(
    'pending information cannot survive a backend replacement or disposal',
    () async {
      final first = _Engine()
        ..informationGate = Completer<PlayerPlaybackInformation?>();
      final second = _Engine();
      var child = first;
      final engine = ConfigurablePlayerEngine(createEngine: () async => child);
      await engine.open(source, const OpenOptions());
      final old = engine.inspectPlaybackInformation();
      child = second;
      await engine.open(source, const OpenOptions());
      first.informationGate!.complete(
        const PlayerPlaybackInformation(generation: 1, backend: 'old'),
      );
      expect(await old, isNull);
      second.informationGate = Completer<PlayerPlaybackInformation?>();
      final closing = engine.inspectPlaybackInformation();
      await engine.dispose();
      second.informationGate!.complete(
        const PlayerPlaybackInformation(generation: 1, backend: 'closed'),
      );
      expect(await closing, isNull);
      await first.closeStreams();
      await second.closeStreams();
    },
  );
  test(
    'failed stop still reaches confirmed disposal before switching',
    () async {
      final first = _Engine()..failStop = true;
      final second = _Engine();
      var selected = first;
      final engine = ConfigurablePlayerEngine(
        createEngine: () async => selected,
      );
      await engine.open(source, const OpenOptions());
      selected = second;
      await engine.open(source, const OpenOptions());
      expect(first.disposed, true);
      await engine.dispose();
      await first.closeStreams();
      await second.closeStreams();
    },
  );
  test('pause cancels a backend play wait without waiting behind it', () async {
    final selected = _Engine()..playGate = Completer<void>();
    final engine = ConfigurablePlayerEngine(createEngine: () async => selected);
    await engine.open(source, const OpenOptions());
    final playing = engine.play();
    await Future<void>.delayed(Duration.zero);
    await engine.pause().timeout(const Duration(seconds: 1));
    await playing;
    await engine.dispose();
    await selected.closeStreams();
  });
  test(
    'saved backend changes only affect the next open and wait for old release',
    () async {
      final first = _Engine();
      final second = _Engine();
      var selected = first;
      var calls = 0;
      final engine = ConfigurablePlayerEngine(
        createEngine: () async {
          calls++;
          return selected;
        },
      );
      expect(calls, 0);
      await engine.open(source, const OpenOptions(play: true));
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      final generation = engine.currentSnapshot.generation;
      selected = second;
      first.release = Completer<void>();
      final reopening = engine.open(source, const OpenOptions());
      await Future<void>.delayed(Duration.zero);
      expect(calls, 1);
      first.events.add(
        const PlaybackSnapshot(phase: PlaybackPhase.failed, generation: 99),
      );
      first.release!.complete();
      await reopening;
      expect(first.disposed, true);
      expect(calls, 2);
      expect(engine.currentSnapshot.generation, greaterThan(generation));
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await engine.dispose();
      await first.closeStreams();
      await second.closeStreams();
    },
  );

  test(
    'uncertain native disposal prevents allocating another backend',
    () async {
      final first = _Engine()..failRelease = true;
      var calls = 0;
      final engine = ConfigurablePlayerEngine(
        createEngine: () async {
          calls++;
          return first;
        },
      );
      await engine.open(source, const OpenOptions());
      await expectLater(
        engine.open(source, const OpenOptions()),
        throwsStateError,
      );
      expect(calls, 1);
      first.failRelease = false;
      await engine.dispose();
      await first.closeStreams();
    },
  );
}
