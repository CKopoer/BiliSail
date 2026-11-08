import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/playback_backend.dart';
import 'package:bili_player/src/shared_player_engine.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class _Output implements FlutterVideoOutput, VideoFrameReadiness {
  final ready = ValueNotifier(true);
  @override
  ValueListenable<bool> get frameReady => ready;
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
  Widget buildVideoSurface() => const ColoredBox(color: Color(0xFF123456));
}

final class _Backend extends Fake implements PlaybackBackend {
  final signals = StreamController<BackendEvent>.broadcast(sync: true);
  final writes = <String>[];
  final seeks = <(Duration, Completer<Duration>)>[];
  Completer<void>? video, audio, presentation, preparing, releasing, pausing;
  Completer<void>? retiring;
  bool holdSeeks = false,
      playing = false,
      released = false,
      failRelease = false;
  double volume = 0, gain = 0;
  int disposals = 0;
  int audioConfirmations = 0, presentationConfirmations = 0;
  bool failInterrupt = false;
  bool failRetirement = false;
  bool endOnPlay = false;
  bool pauseConfirmed = true;
  PreparedTracks tracks = const PreparedTracks(
    hasVideo: true,
    hasAudio: true,
    externalAudioSelected: true,
    duration: Duration(seconds: 20),
    dimensions: VideoDimensions(320, 180),
  );
  BackendHealth sample = const BackendHealth();
  ValidatedSource? preparedPlan;
  @override
  VideoOutput get videoOutput => _output;
  final _output = _Output();
  @override
  Stream<BackendEvent> get events => signals.stream;
  @override
  Duration get seekTimeout => const Duration(seconds: 1);
  @override
  Future<PreparedTracks> preparePaused(
    ValidatedSource plan,
    PlaybackOperation operation,
  ) async {
    writes.add('prepare');
    preparedPlan = plan;
    volume = plan.options.volume;
    await preparing?.future;
    return tracks;
  }

  @override
  Future<VideoDimensions?> confirmVideo(PlaybackOperation operation) async {
    await video?.future;
    return tracks.dimensions;
  }

  @override
  Future<void> confirmAudio(PlaybackOperation operation) async {
    audioConfirmations++;
    await audio?.future;
  }

  @override
  Future<void> confirmPresentation(PlaybackOperation operation) async {
    presentationConfirmations++;
    await presentation?.future;
  }

  @override
  Future<void> play() async {
    playing = true;
    writes.add('play');
    if (endOnPlay) {
      signals.add(
        BackendEvent(BackendEventKind.ended, position: tracks.duration),
      );
    }
  }

  @override
  Future<bool> pauseAndWait() async {
    if (pauseConfirmed) playing = false;
    writes.add('pause');
    await pausing?.future;
    return pauseConfirmed;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
    writes.add('volume:$volume');
  }

  @override
  Future<void> setRate(double rate) async {
    writes.add('rate:$rate');
  }

  @override
  Future<void> setGainDb(double gainDb) async {
    gain = gainDb;
    writes.add('gain:$gainDb');
  }

  @override
  Future<Duration> seekTo(Duration target, PlaybackOperation operation) async {
    await pauseAndWait();
    final done = Completer<Duration>();
    seeks.add((target, done));
    final position = holdSeeks ? await done.future : target;
    await audio?.future;
    return position;
  }

  @override
  Future<void> cancelSeek() {
    writes.add('cancelSeek');
    if (failRetirement) throw StateError('native cancellation rejected');
    return retiring?.future ?? Future.value();
  }

  @override
  void interrupt() {
    playing = false;
    writes.add('interrupt');
    if (failInterrupt) throw StateError('native stop rejected');
  }

  @override
  BackendHealth sampleHealth() => sample;
  @override
  void resetHealth() {}
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation(
    int generation,
  ) async => null;
  @override
  Future<void> dispose() async {
    disposals++;
    await releasing?.future;
    if (failRelease) throw StateError('uncertain native release');
    released = true;
    await signals.close();
  }
}

Future<void> tick() => Future<void>.delayed(Duration.zero);

MediaTrack track(String name) => MediaTrack(
  uri: Uri.parse('https://example.com/$name'),
  requestPolicy: MediaRequestPolicy(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final pair = DashPairSource(video: track('v'), audio: track('a'));

  test(
    'native preparation receives the original tracks, headers and window',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      const options = OpenOptions(maxBufferAhead: Duration(seconds: 5));
      final policy = MediaRequestPolicy(
        headers: {'Referer': 'https://example.com/'},
      );
      final source = DashPairSource(
        video: MediaTrack(
          uri: Uri.parse('https://example.com/video?sign=v'),
          requestPolicy: policy,
        ),
        audio: MediaTrack(
          uri: Uri.parse('https://example.com/audio?sign=a'),
          requestPolicy: policy,
        ),
      );
      await engine.open(source, options);
      expect(backend.preparedPlan!.media, same(source.video));
      expect(backend.preparedPlan!.audio, same(source.audio));
      expect(backend.preparedPlan!.options, same(options));
      expect(backend.preparedPlan!.media.requestPolicy, same(policy));
    },
  );

  test('events and polling accept a shrinking native cache without moving progress', () async {
    final backend = _Backend();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    await engine.open(pair, const OpenOptions());
    backend.signals.add(
      const BackendEvent(
        BackendEventKind.sample,
        position: Duration(seconds: 4),
        buffered: Duration(seconds: 18),
      ),
    );
    backend.signals.add(
      const BackendEvent(
        BackendEventKind.sample,
        buffered: Duration(seconds: 8),
      ),
    );
    expect(engine.currentSnapshot.position, const Duration(seconds: 4));
    expect(engine.currentSnapshot.buffered, const Duration(seconds: 8));
    backend.sample = const BackendHealth(buffered: Duration(seconds: 6));
    await Future<void>.delayed(const Duration(milliseconds: 280));
    expect(engine.currentSnapshot.position, const Duration(seconds: 4));
    expect(engine.currentSnapshot.buffered, const Duration(seconds: 6));
    expect(backend.seeks, isEmpty);
    expect(backend.writes.where((w) => w == 'prepare'), hasLength(1));
  });

  test(
    'native timeline endpoints stay within confirmed duration and position',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions());
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: 3),
          buffered: Duration(seconds: 40),
        ),
      );
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 20));
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          buffered: Duration(seconds: -1),
        ),
      );
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 3));
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: -1),
          buffered: Duration(seconds: -2),
        ),
      );
      expect(engine.currentSnapshot.position, Duration.zero);
      expect(engine.currentSnapshot.buffered, Duration.zero);
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: 22),
          buffered: Duration(seconds: 40),
        ),
      );
      expect(engine.currentSnapshot.position, const Duration(seconds: 20));
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 20));
    },
  );

  test(
    'backward seek resets old cache until the new native endpoint arrives',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions());
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: 15),
          buffered: Duration(seconds: 20),
        ),
      );
      await engine.seek(const Duration(seconds: 2));
      expect(engine.currentSnapshot.position, const Duration(seconds: 2));
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 2));
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          buffered: Duration(seconds: 7),
        ),
      );
      expect(engine.currentSnapshot.position, const Duration(seconds: 2));
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 7));
    },
  );

  test(
    'opening target clamps once the native duration becomes known',
    () async {
      final backend = _Backend()..preparing = Completer<void>();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      final opening = engine.open(pair, const OpenOptions());
      final seeking = engine.seek(const Duration(seconds: 90));
      backend.preparing!.complete();
      await Future.wait([opening, seeking]);
      expect(backend.seeks.single.$1, const Duration(seconds: 20));
      expect(engine.currentSnapshot.position, const Duration(seconds: 20));
      expect(engine.currentSnapshot.desiredPlaying, false);
    },
  );

  test(
    'a large seek burst retires once and releases superseded pending callers',
    () async {
      final backend = _Backend()
        ..holdSeeks = true
        ..retiring = Completer<void>();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions());
      final first = engine.seek(const Duration(seconds: 19));
      await tick();
      final discarded = <Future<void>>[];
      for (var i = 0; i < 1000; i++) {
        discarded.add(engine.seek(Duration(milliseconds: i)));
      }
      final latest = engine.seek(const Duration(seconds: 3));
      await Future.wait([first, ...discarded])
          .timeout(const Duration(seconds: 1));
      expect(backend.seeks, hasLength(1));
      expect(backend.writes.where((w) => w == 'cancelSeek'), hasLength(1));
      backend.retiring!.complete();
      await tick();
      expect(backend.seeks.map((s) => s.$1), [
        const Duration(seconds: 19),
        const Duration(seconds: 3),
      ]);
      backend.seeks.last.$2.complete(const Duration(seconds: 3));
      await latest;
      backend.seeks.first.$2.complete(const Duration(seconds: 19));
      await tick();
      expect(engine.currentSnapshot.position, const Duration(seconds: 3));
    },
  );

  test(
    'queued gestures ignore old progress and stop releases the pending caller',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(
        createBackend: () => backend,
        seekCoalescingDelay: const Duration(milliseconds: 40),
      );
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true));
      final seeking = engine.seek(const Duration(seconds: 2));
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: 19),
          buffered: Duration(seconds: 20),
        ),
      );
      expect(engine.currentSnapshot.position, Duration.zero);
      await engine.stop();
      await seeking;
      expect(backend.seeks, isEmpty);
      expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
    },
  );

  test(
    'source replacement during gesture delay waits for the new preparation',
    () async {
      var backend = _Backend();
      final first = backend;
      final engine = SharedPlayerEngine(
        createBackend: () => backend,
        seekCoalescingDelay: const Duration(milliseconds: 40),
      );
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions());
      final old = engine.seek(const Duration(seconds: 9));
      await tick();
      backend = _Backend()..preparing = Completer<void>();
      final opening = engine.open(pair, const OpenOptions());
      final current = engine.seek(const Duration(seconds: 2));
      await Future<void>.delayed(const Duration(milliseconds: 70));
      expect(backend.seeks, isEmpty);
      backend.preparing!.complete();
      await Future.wait([old, opening, current]);
      expect(first.seeks, isEmpty);
      expect(backend.seeks.single.$1, const Duration(seconds: 2));
      expect(engine.currentSnapshot.position, const Duration(seconds: 2));
    },
  );

  test(
    'rejected retirement fails the latest request without stranding callers',
    () async {
      final backend = _Backend()
        ..holdSeeks = true
        ..failRetirement = true;
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true));
      final first = engine.seek(const Duration(seconds: 9));
      await tick();
      final latest = engine.seek(const Duration(seconds: 2));
      await expectLater(latest, throwsA(isA<PlayerFailure>()));
      await first;
      expect(backend.playing, false);
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      expect(backend.seeks, hasLength(1));
      backend.seeks.first.$2.complete(const Duration(seconds: 9));
    },
  );

  test(
    'natural EOF after the confirmed seek target is not discarded',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true));
      backend.endOnPlay = true;
      var endings = 0;
      engine.snapshots.listen((s) {
        if (s.phase == PlaybackPhase.ended) endings++;
      });
      await engine.seek(const Duration(seconds: 20));
      expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
      expect(engine.currentSnapshot.desiredPlaying, false);
      expect(endings, 1);
    },
  );

  test(
    'opening seek plays only after the latest target is confirmed',
    () async {
      final backend = _Backend()..preparing = Completer<void>();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      final positions = <Duration>[];
      engine.snapshots.listen((s) {
        if (s.phase == PlaybackPhase.playing) positions.add(s.position);
      });
      final opening = engine.open(pair, const OpenOptions(play: true));
      final seeking = engine.seek(const Duration(seconds: 2));
      backend.preparing!.complete();
      await Future.wait([opening, seeking]);
      expect(backend.writes.where((w) => w == 'play'), hasLength(1));
      expect(positions, [const Duration(seconds: 2)]);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    },
  );

  test(
    'recovery keeps the timeline through release and paused preparation',
    () async {
      final first = _Backend();
      final replacement = _Backend()
        ..preparing = Completer<void>()
        ..audio = Completer<void>()
        ..tracks = const PreparedTracks(
          hasVideo: true,
          hasAudio: true,
          externalAudioSelected: true,
          position: Duration(seconds: 7),
          duration: Duration(seconds: 20),
          dimensions: VideoDimensions(320, 180),
        );
      var allocations = 0;
      final engine = SharedPlayerEngine(
        createBackend: () {
          if (allocations++ == 0) return first;
          expect(first.released, true);
          return replacement;
        },
      );
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true));
      first.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: 7),
          buffered: Duration(seconds: 15),
        ),
      );
      first.signals.add(const BackendEvent(BackendEventKind.failure));
      await tick();
      expect(first.playing, false);
      final snapshots = <PlaybackSnapshot>[];
      engine.snapshots.listen(snapshots.add);
      first.releasing = Completer<void>();
      final reopening = engine.open(
        pair,
        const OpenOptions(
          startPosition: Duration(seconds: 7),
          retainPresentation: true,
        ),
      );
      await tick();
      expect(allocations, 1);
      expect(engine.currentSnapshot.duration, const Duration(seconds: 20));
      expect(engine.currentSnapshot.position, const Duration(seconds: 7));
      first.releasing!.complete();
      await tick();
      expect(allocations, 2);
      expect(engine.currentSnapshot.duration, const Duration(seconds: 20));
      replacement.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration.zero,
          duration: Duration.zero,
        ),
      );
      expect(engine.currentSnapshot.position, const Duration(seconds: 7));
      expect(engine.currentSnapshot.duration, const Duration(seconds: 20));
      replacement.preparing!.complete();
      await reopening;
      final playing = engine.play();
      await tick();
      expect(replacement.volume, 100);
      replacement.signals.add(
        const BackendEvent(
          BackendEventKind.sample,
          position: Duration(seconds: 8),
        ),
      );
      replacement.signals.add(
        const BackendEvent(BackendEventKind.buffering, value: false),
      );
      expect(engine.currentSnapshot.position, const Duration(seconds: 7));
      expect(engine.currentSnapshot.phase, PlaybackPhase.buffering);
      replacement.audio!.complete();
      await playing;
      expect(
        snapshots.every(
          (s) =>
              s.position == const Duration(seconds: 7) &&
              s.duration == const Duration(seconds: 20),
        ),
        true,
      );
      await engine.stop();
      expect(engine.currentSnapshot.position, Duration.zero);
      expect(engine.currentSnapshot.duration, Duration.zero);
    },
  );

  test('autoplay waits for decoded tracks and presentation, using the latest volume', () async {
    final backend = _Backend()
      ..video = Completer<void>()
      ..audio = Completer<void>()
      ..presentation = Completer<void>();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    final phases = <PlaybackPhase>[];
    engine.snapshots.listen((s) => phases.add(s.phase));
    final opening = engine.open(
      pair,
      const OpenOptions(play: true, volume: 37),
    );
    await tick();
    expect(backend.playing, false);
    await engine.setVolume(63);
    backend.video!.complete();
    await tick();
    expect(backend.playing, false);
    expect(backend.volume, 37);
    backend.audio!.complete();
    await tick();
    expect(backend.volume, 37);
    backend.presentation!.complete();
    await opening;
    expect(backend.volume, 63);
    expect(phases.where((p) => p == PlaybackPhase.ready), hasLength(1));
    expect(phases.last, PlaybackPhase.playing);
  });

  test('paused open also gates first play and pause cancels a blocked audio confirmation', () async {
    final backend = _Backend()..audio = Completer<void>();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    await engine.open(pair, const OpenOptions(volume: 37));
    final playing = engine.play();
    await tick();
    expect(backend.playing, false);
    expect(backend.volume, 37);
    await engine.setVolume(24);
    expect(backend.volume, 24);
    await engine.pause();
    await playing;
    backend.audio!.complete();
    await tick();
    expect(backend.playing, false);
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    await engine.play();
    expect(backend.volume, 24);
  });

  test('play arriving during paused presentation stays paused until audio is ready', () async {
    final backend = _Backend()
      ..presentation = Completer<void>()
      ..audio = Completer<void>();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    final opening = engine.open(pair, const OpenOptions(volume: 37));
    await tick();
    await engine.play();
    backend.presentation!.complete();
    await tick();
    expect(backend.playing, false);
    expect(backend.volume, 37);
    backend.audio!.complete();
    await opening;
    expect(backend.volume, 37);
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
  });

  test(
    'resuming a ready source dispatches play without preparing or muting again',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true, volume: 37));
      await engine.pause();
      backend.audio = Completer<void>();
      final before = backend.writes.length;
      await engine.play();
      expect(backend.playing, true);
      expect(backend.volume, 37);
      expect(engine.currentSnapshot.isBuffering, false);
      expect(backend.writes.skip(before), ['play']);
    },
  );

  test('new seek retires old completion, EOF, sample and failure; latest play intent wins', () async {
    final backend = _Backend()..holdSeeks = true;
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    await engine.open(pair, const OpenOptions(play: true));
    final old = engine.seek(const Duration(seconds: 19));
    await tick();
    final latest = engine.seek(const Duration(seconds: 2));
    await tick();
    await old;
    backend.signals.add(
      const BackendEvent(
        BackendEventKind.ended,
        position: Duration(seconds: 20),
      ),
    );
    backend.signals.add(const BackendEvent(BackendEventKind.failure));
    backend.signals.add(
      const BackendEvent(
        BackendEventKind.sample,
        position: Duration(seconds: 19),
      ),
    );
    expect(engine.currentSnapshot.position, Duration.zero);
    expect(engine.currentSnapshot.isSeeking, true);
    await engine.pause();
    await engine.play();
    backend.seeks.first.$2.completeError(StateError('retired seek'));
    backend.seeks.last.$2.complete(const Duration(seconds: 2));
    await latest;
    expect(engine.currentSnapshot.position, const Duration(seconds: 2));
    expect(backend.playing, true);
  });

  test('seek waits for backend target readiness before resuming', () async {
    final backend = _Backend();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    await engine.open(pair, const OpenOptions(play: true));
    backend.audio = Completer<void>();
    var done = false;
    final seeking = engine
        .seek(const Duration(seconds: 5))
        .then((_) => done = true);
    await tick();
    expect(done, false);
    expect(backend.playing, false);
    expect(backend.volume, 100);
    backend.audio!.complete();
    await seeking;
    expect(backend.volume, 100);
    expect(engine.currentSnapshot.position, const Duration(seconds: 5));
    expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
  });

  for (final playing in [false, true]) {
    test(
      'confirmed native seek reuses readiness and cache, playing=$playing',
      () async {
        final backend = _Backend()
          ..sample = const BackendHealth(buffered: Duration(seconds: 18));
        final engine = SharedPlayerEngine(createBackend: () => backend);
        addTearDown(engine.dispose);
        await engine.open(pair, OpenOptions(play: playing));
        final audio = backend.audioConfirmations;
        final video = backend.presentationConfirmations;
        final before = backend.writes.length;
        final states = <PlaybackSnapshot>[];
        engine.snapshots.listen(states.add);
        await engine.seek(const Duration(seconds: 5));
        expect(backend.audioConfirmations, audio);
        expect(backend.presentationConfirmations, video);
        expect(
          backend.writes.skip(before),
          playing ? ['pause', 'play'] : ['pause'],
        );
        expect(states.any((s) => s.isBuffering), false);
        expect(engine.currentSnapshot.buffered, const Duration(seconds: 18));
        expect(
          engine.currentSnapshot.phase,
          playing ? PlaybackPhase.playing : PlaybackPhase.paused,
        );
        if (!playing) {
          final afterSeek = backend.writes.length;
          await engine.play();
          expect(backend.writes.skip(afterSeek), ['play']);
          expect(backend.audioConfirmations, audio);
        }
      },
    );
  }

  test('replacement seeks wait for native retirement and coalesce to the latest target', () async {
    final backend = _Backend()
      ..holdSeeks = true
      ..retiring = Completer<void>();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    await engine.open(pair, const OpenOptions());
    final old = engine.seek(const Duration(seconds: 9));
    await tick();
    final intermediate = engine.seek(const Duration(seconds: 7));
    await tick();
    final latest = engine.seek(const Duration(seconds: 2));
    await tick();
    expect(backend.seeks.length, 1);
    backend.retiring!.complete();
    await tick();
    expect(backend.seeks.map((s) => s.$1), [
      const Duration(seconds: 9),
      const Duration(seconds: 2),
    ]);
    backend.seeks.last.$2.complete(const Duration(seconds: 2));
    await Future.wait([old, intermediate, latest]);
    expect(engine.currentSnapshot.position, const Duration(seconds: 2));
    expect(engine.currentSnapshot.desiredPlaying, false);
  });

  test('rapid input merges before dispatching a native seek', () async {
    final backend = _Backend();
    final engine = SharedPlayerEngine(
      createBackend: () => backend,
      seekCoalescingDelay: const Duration(milliseconds: 40),
    );
    addTearDown(engine.dispose);
    await engine.open(pair, const OpenOptions());
    final first = engine.seek(const Duration(seconds: 9));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final second = engine.seek(const Duration(seconds: 7));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final latest = engine.seek(const Duration(seconds: 2));
    expect(backend.seeks, isEmpty);
    await Future.wait([first, second, latest]);
    expect(backend.seeks.map((s) => s.$1), [const Duration(seconds: 2)]);
    expect(engine.currentSnapshot.position, const Duration(seconds: 2));
  });

  test(
    'EOF during input coalescing cannot revoke the requested seek play intent',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(
        createBackend: () => backend,
        seekCoalescingDelay: const Duration(milliseconds: 40),
      );
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true));
      final seeking = engine.seek(const Duration(seconds: 2));
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.ended,
          position: Duration(seconds: 20),
        ),
      );
      expect(engine.currentSnapshot.desiredPlaying, true);
      await seeking;
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(engine.currentSnapshot.position, const Duration(seconds: 2));
    },
  );

  test('opening seeks coalesce and preserve a manual pause', () async {
    final backend = _Backend()..preparing = Completer<void>();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    final opening = engine.open(pair, const OpenOptions(play: true));
    final old = engine.seek(const Duration(seconds: 9));
    final latest = engine.seek(const Duration(seconds: 2));
    await engine.pause();
    backend.preparing!.complete();
    await Future.wait([opening, old, latest]);
    expect(backend.seeks.map((s) => s.$1), [const Duration(seconds: 2)]);
    expect(backend.playing, false);
  });

  test('natural EOF emits once, ignores trailing events, and replay resumes sampling', () async {
    final backend = _Backend();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    var ended = 0;
    engine.snapshots.listen((s) {
      if (s.phase == PlaybackPhase.ended) ended++;
    });
    await engine.open(pair, const OpenOptions(play: true));
    for (var replay = 0; replay < 2; replay++) {
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.ended,
          position: Duration(seconds: 20),
        ),
      );
      backend.signals.add(
        const BackendEvent(
          BackendEventKind.ended,
          position: Duration(seconds: 20),
        ),
      );
      backend.signals.add(
        const BackendEvent(BackendEventKind.buffering, value: true),
      );
      backend.signals.add(
        const BackendEvent(BackendEventKind.playing, value: true),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
      expect(engine.currentSnapshot.isBuffering, false);
      await engine.seek(Duration.zero);
      await engine.play();
      backend.sample = const BackendHealth(position: Duration(seconds: 1));
      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(engine.currentSnapshot.position, const Duration(seconds: 1));
    }
    expect(ended, 2);
  });

  test(
    'pause stays paused through native buffering and delayed playing',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(play: true));
      await engine.pause();
      backend.signals.add(
        const BackendEvent(BackendEventKind.buffering, value: true),
      );
      backend.signals.add(
        const BackendEvent(BackendEventKind.playing, value: true),
      );
      await tick();
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      expect(backend.playing, false);
    },
  );

  test('failure stream and command share one failure after native pause acknowledgement', () async {
    final backend = _Backend()..holdSeeks = true;
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    final failures = <PlayerFailure>[];
    engine.failures.listen(failures.add);
    await engine.open(pair, const OpenOptions(play: true));
    final seeking = engine.seek(const Duration(seconds: 4));
    Object? commandFailure;
    final completed = seeking.catchError((Object error) {
      commandFailure = error;
    });
    await tick();
    backend.seeks.single.$2.completeError(StateError('I/O failure'));
    await completed;
    backend.signals.add(const BackendEvent(BackendEventKind.failure));
    await tick();
    expect(failures, hasLength(1));
    expect(identical(commandFailure, failures.single), true);
    expect(backend.playing, false);
  });

  test('reentrant ready listener can stop without publishing stale playing or sound', () async {
    final backend = _Backend();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    Future<void>? stopping;
    engine.snapshots.listen((s) {
      if (s.phase == PlaybackPhase.ready) stopping = engine.stop();
    });
    await engine.open(pair, const OpenOptions(play: true));
    await stopping;
    expect(backend.released, true);
    expect(backend.playing, false);
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
  });

  test(
    'cancelled factory stays owned and a replacement waits for its release',
    () async {
      final first = _Backend()..releasing = Completer<void>();
      final second = _Backend();
      final factory = Completer<PlaybackBackend>();
      var creates = 0;
      final engine = SharedPlayerEngine(
        createBackend: () => creates++ == 0 ? factory.future : second,
      );
      addTearDown(engine.dispose);
      final opening = engine.open(pair, const OpenOptions());
      await tick();
      final replacement = engine.open(pair, const OpenOptions());
      await opening;
      factory.complete(first);
      await tick();
      expect(creates, 1);
      first.releasing!.complete();
      await replacement;
      expect(creates, 2);
      expect(first.released, true);
    },
  );

  test('duplicate dispose shares the release future; uncertain release blocks allocation', () async {
    final backend = _Backend()..releasing = Completer<void>();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    await engine.open(pair, const OpenOptions());
    final first = engine.dispose(), second = engine.dispose();
    expect(identical(first, second), true);
    await tick();
    expect(backend.disposals, 1);
    backend.releasing!.complete();
    await first;

    final broken = _Backend()..failRelease = true;
    var creates = 0;
    final blocked = SharedPlayerEngine(
      createBackend: () {
        creates++;
        return broken;
      },
    );
    await blocked.open(pair, const OpenOptions());
    await expectLater(blocked.stop(), throwsStateError);
    await expectLater(
      blocked.open(pair, const OpenOptions()),
      throwsStateError,
    );
    expect(creates, 1);
    await expectLater(blocked.dispose(), throwsStateError);
    await broken.signals.close();
  });

  for (final tracks in [
    const PreparedTracks(hasVideo: false, hasAudio: true),
    const PreparedTracks(hasVideo: true, hasAudio: true),
    const PreparedTracks(hasVideo: false, hasAudio: false),
  ]) {
    test(
      'progressive track discovery: video=${tracks.hasVideo}, audio=${tracks.hasAudio}',
      () async {
        final backend = _Backend()..tracks = tracks;
        final engine = SharedPlayerEngine(createBackend: () => backend);
        addTearDown(engine.dispose);
        final opening = engine.open(
          ProgressiveSource(track('mixed')),
          const OpenOptions(),
        );
        if (!tracks.hasVideo && !tracks.hasAudio) {
          await expectLater(opening, throwsA(isA<PlayerFailure>()));
        } else {
          await opening;
          expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        }
      },
    );
  }

  test('live stays at 1x and bypasses seek; preview stays muted after volume changes', () async {
    var backend = _Backend();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    await engine.open(
      ManifestSource(track('live'), isLive: true),
      const OpenOptions(rate: 2),
    );
    await engine.setRate(3);
    await engine.seek(const Duration(seconds: 2));
    expect(engine.currentSnapshot.rate, 1);
    expect(engine.currentSnapshot.duration, Duration.zero);
    backend.signals.add(
      const BackendEvent(
        BackendEventKind.sample,
        duration: Duration(seconds: 20),
      ),
    );
    expect(engine.currentSnapshot.duration, Duration.zero);
    expect(backend.seeks, isEmpty);
    backend = _Backend();
    await engine.open(
      DashVideoSource(track('preview')),
      const OpenOptions(volume: 0),
    );
    await engine.setVolume(90);
    expect(backend.volume, 0);
  });

  test(
    'gain target replacement cancels the old ramp without changing base volume',
    () async {
      final backend = _Backend();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      await engine.open(pair, const OpenOptions(volume: 37));
      final old = engine.setAudioGain(-8);
      await Future<void>.delayed(const Duration(milliseconds: 25));
      await engine.setAudioGain(4);
      await old;
      expect(backend.gain, 4);
      expect(backend.volume, 37);
      expect(engine.currentSnapshot.volume, 37);
    },
  );

  test(
    'an opening listener can replace the source before lifecycle dispatch',
    () async {
      final backend = _Backend();
      var creates = 0;
      final engine = SharedPlayerEngine(
        createBackend: () {
          creates++;
          return backend;
        },
      );
      Future<void>? replacement;
      engine.snapshots.listen((snapshot) {
        if (snapshot.generation == 1 &&
            snapshot.phase == PlaybackPhase.opening) {
          replacement = engine.open(pair, const OpenOptions());
        }
      });
      await engine.open(pair, const OpenOptions(play: true));
      await replacement;
      expect(creates, 1);
      expect(backend.released, false);
      expect(engine.currentSnapshot.generation, 2);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await engine.dispose();
    },
  );

  test(
    'buffering observed during prepare survives the ready transition',
    () async {
      final backend = _Backend()..video = Completer<void>();
      final engine = SharedPlayerEngine(createBackend: () => backend);
      addTearDown(engine.dispose);
      final opening = engine.open(pair, const OpenOptions(play: true));
      await tick();
      backend.signals.add(
        const BackendEvent(BackendEventKind.buffering, value: true),
      );
      backend.video!.complete();
      await opening;
      expect(engine.currentSnapshot.phase, PlaybackPhase.buffering);
      expect(engine.currentSnapshot.isBuffering, true);
      backend.signals.add(
        const BackendEvent(BackendEventKind.buffering, value: false),
      );
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
    },
  );

  test(
    'an unconfirmed native pause releases the whole pipeline before failure',
    () async {
      final backend = _Backend()..pauseConfirmed = false;
      final engine = SharedPlayerEngine(createBackend: () => backend);
      await engine.open(pair, const OpenOptions(play: true));
      final failure = engine.failures.first;
      backend.signals.add(const BackendEvent(BackendEventKind.failure));
      await failure;
      expect(backend.released, true);
      expect(backend.playing, false);
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      await engine.dispose();
    },
  );

  test('a rejected native stop still reaches confirmed disposal', () async {
    final backend = _Backend()..failInterrupt = true;
    final engine = SharedPlayerEngine(createBackend: () => backend);
    await engine.open(pair, const OpenOptions());
    await engine.stop();
    expect(backend.released, true);
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
    await engine.dispose();
  });

  test('factory timeout returns within budget while late release blocks replacement', () async {
    final factory = Completer<PlaybackBackend>();
    final late = _Backend();
    final next = _Backend();
    var calls = 0;
    final engine = SharedPlayerEngine(
      createBackend: () => calls++ == 0 ? factory.future : next,
    );
    addTearDown(engine.dispose);
    await expectLater(
      engine
          .open(
            pair,
            const OpenOptions(openTimeout: Duration(milliseconds: 60)),
          )
          .timeout(const Duration(milliseconds: 500)),
      throwsA(isA<PlayerFailure>()),
    );
    final replacement = engine.open(pair, const OpenOptions());
    await tick();
    expect(calls, 1);
    factory.complete(late);
    await replacement;
    expect(late.released, true);
    expect(calls, 2);
  });

  test('native underrun evidence survives timeline display clamping', () async {
    final backend = _Backend();
    final engine = SharedPlayerEngine(createBackend: () => backend);
    addTearDown(engine.dispose);
    final failures = <PlayerFailure>[];
    engine.failures.listen(failures.add);
    await engine.open(pair, const OpenOptions(play: true));
    for (final seconds in [5, 6]) {
      backend.sample = BackendHealth(
        position: Duration(seconds: seconds),
        buffered: const Duration(seconds: 2),
        audioPosition: Duration(seconds: seconds),
        comparePairedClocks: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    expect(failures, hasLength(1));
    expect(failures.single.kind, PlayerFailureKind.videoInterrupted);
    expect(backend.playing, false);
    expect(engine.currentSnapshot.buffered, engine.currentSnapshot.position);
  });

  test('health sampling detects lost audio activity while video position continues', () async {
    final backend = _Backend();
    var now = Duration.zero;
    final engine = SharedPlayerEngine(
      createBackend: () => backend,
      monotonicNow: () => now,
    );
    addTearDown(engine.dispose);
    final failures = <PlayerFailure>[];
    engine.failures.listen(failures.add);
    await engine.open(pair, const OpenOptions(play: true));
    for (final seconds in [0, 1, 4]) {
      now = Duration(seconds: seconds);
      backend.sample = BackendHealth(
        position: Duration(seconds: seconds + 1),
        audioFrames: 10,
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
    }
    expect(failures, hasLength(1));
    expect(backend.playing, false);
    expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
  });

  test(
    'synchronized buffering uses the shared thirty second deadline',
    () async {
      final backend = _Backend();
      var now = Duration.zero;
      final engine = SharedPlayerEngine(
        createBackend: () => backend,
        monotonicNow: () => now,
      );
      addTearDown(engine.dispose);
      final failures = <PlayerFailure>[];
      engine.failures.listen(failures.add);
      await engine.open(pair, const OpenOptions(play: true));
      backend.signals.add(
        const BackendEvent(BackendEventKind.buffering, value: true),
      );
      await Future<void>.delayed(const Duration(milliseconds: 280));
      now = const Duration(seconds: 29);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(failures, isEmpty);
      now = const Duration(seconds: 31);
      await Future<void>.delayed(const Duration(milliseconds: 280));
      expect(failures, hasLength(1));
      expect(backend.playing, false);
    },
  );
}
