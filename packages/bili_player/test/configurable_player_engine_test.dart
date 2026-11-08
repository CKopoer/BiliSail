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
  Completer<void>? openGate;
  Future<void> Function(Duration)? onSeek;
  final seekTargets = <Duration>[];
  OpenOptions? openedOptions;
  int playCalls = 0;
  Completer<PlayerPlaybackInformation?>? informationGate;
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation() async =>
      informationGate?.future ??
      const PlayerPlaybackInformation(generation: 1, backend: 'test');
  @override
  Future<void> play() async {
    playCalls++;
    await playGate?.future;
  }

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
    openedOptions = options;
    await openGate?.future;
    events.add(
      PlaybackSnapshot(
        phase: options.play ? PlaybackPhase.playing : PlaybackPhase.paused,
        generation: 1,
        position: options.startPosition,
        rate: options.rate,
        volume: options.volume,
      ),
    );
  }

  @override
  Future<void> seek(Duration target) {
    seekTargets.add(target);
    return onSeek?.call(target) ?? Future<void>.value();
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
  test('same-content recovery preserves the timeline across child selection and readiness', () async {
    final first = _Engine();
    final second = _Engine()..openGate = Completer<void>();
    var calls = 0;
    final engine = ConfigurablePlayerEngine(
      createEngine: () async {
        calls++;
        return calls == 1 ? first : second;
      },
    );
    await engine.open(source, const OpenOptions(play: true));
    first.events.add(
      const PlaybackSnapshot(
        phase: PlaybackPhase.failed,
        generation: 1,
        position: Duration(seconds: 7),
        duration: Duration(seconds: 20),
      ),
    );
    final values = <PlaybackSnapshot>[];
    engine.snapshots.listen(values.add);
    first.release = Completer<void>();
    final opening = engine.open(
      source,
      const OpenOptions(
        retainPresentation: true,
        startPosition: Duration(seconds: 7),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    first.release!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(first.disposed, true);
    expect(second.openedOptions?.retainPresentation, true);
    second.events.add(
      const PlaybackSnapshot(phase: PlaybackPhase.opening, generation: 1),
    );
    second.openGate!.complete();
    await opening;
    expect(values, isNotEmpty);
    expect(
      values.every(
        (s) =>
            s.position == const Duration(seconds: 7) &&
            s.duration == const Duration(seconds: 20),
      ),
      true,
    );
    await engine.stop();
    expect(engine.currentSnapshot.duration, Duration.zero);
    await engine.dispose();
    await first.closeStreams();
    await second.closeStreams();
  });
  test('pause before backend factory returns overrides autoplay', () async {
    final child = _Engine();
    final factory = Completer<PlayerEngine>();
    final engine = ConfigurablePlayerEngine(createEngine: () => factory.future);
    final opening = engine.open(source, const OpenOptions(play: true));
    await Future<void>.delayed(Duration.zero);
    final queuedPlay = engine.play();
    await engine.pause();
    factory.complete(child);
    await Future.wait([opening, queuedPlay]);
    expect(child.openedOptions?.play, false);
    expect(child.playCalls, 0);
    await engine.seek(const Duration(seconds: -1));
    expect(child.seekTargets, [Duration.zero]);
    await engine.dispose();
    await child.closeStreams();
  });
  test(
    'seeks during open wait for readiness and discard obsolete targets',
    () async {
      final child = _Engine()..openGate = Completer<void>();
      final engine = ConfigurablePlayerEngine(createEngine: () async => child);
      final opening = engine.open(source, const OpenOptions());
      await Future<void>.delayed(Duration.zero);
      final old = engine.seek(const Duration(seconds: 9));
      final latest = engine.seek(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      expect(child.seekTargets, isEmpty);
      child.openGate!.complete();
      await Future.wait([opening, old, latest]);
      expect(child.seekTargets, [const Duration(seconds: 2)]);
      await engine.dispose();
      await child.closeStreams();
    },
  );

  test(
    'command failures and stream failures use the external source generation',
    () async {
      final first = _Engine(), second = _Engine();
      var selected = first;
      final engine = ConfigurablePlayerEngine(
        createEngine: () async => selected,
      );
      await engine.open(source, const OpenOptions());
      selected = second;
      await engine.open(source, const OpenOptions());
      final failures = <PlayerFailure>[];
      final subscription = engine.failures.listen(failures.add);
      second.onSeek = (_) {
        const failure = PlayerFailure(
          PlayerFailureKind.nativePlayback,
          'safe',
          1,
        );
        second.errors.add(failure);
        return Future.error(failure);
      };
      await expectLater(
        engine.seek(const Duration(seconds: 2)),
        throwsA(
          isA<PlayerFailure>().having(
            (e) => e.generation,
            'generation',
            engine.currentSnapshot.generation,
          ),
        ),
      );
      expect(failures.single.generation, engine.currentSnapshot.generation);
      await subscription.cancel();
      await engine.dispose();
      await first.closeStreams();
      await second.closeStreams();
    },
  );

  test('queued seek cannot cross a source replacement', () async {
    final first = _Engine()..openGate = Completer<void>();
    final second = _Engine();
    var child = first;
    final engine = ConfigurablePlayerEngine(createEngine: () async => child);
    final opening = engine.open(source, const OpenOptions());
    await Future<void>.delayed(Duration.zero);
    final old = engine.seek(const Duration(seconds: 9));
    child = second;
    final replacement = engine.open(source, const OpenOptions());
    first.openGate!.complete();
    await Future.wait([opening, old, replacement]);
    expect(first.seekTargets, isEmpty);
    expect(second.seekTargets, isEmpty);
    expect(first.disposed, true);
    await engine.seek(const Duration(seconds: 2));
    expect(second.seekTargets, [const Duration(seconds: 2)]);
    await engine.dispose();
    await first.closeStreams();
    await second.closeStreams();
  });

  for (final synchronous in [false, true]) {
    test(
      'command failures propagate and allow later dispatch: sync=$synchronous',
      () async {
        final child = _Engine()
          ..onSeek = (_) {
            if (synchronous) throw StateError('seek failed');
            return Future<void>.error(StateError('seek failed'));
          };
        final engine = ConfigurablePlayerEngine(
          createEngine: () async => child,
        );
        await engine.open(source, const OpenOptions());
        await expectLater(
          engine.seek(const Duration(seconds: 9)),
          throwsStateError,
        );
        child.onSeek = null;
        await engine.seek(const Duration(seconds: 2));
        expect(child.seekTargets, [
          const Duration(seconds: 9),
          const Duration(seconds: 2),
        ]);
        await engine.dispose();
        await child.closeStreams();
      },
    );
  }
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
