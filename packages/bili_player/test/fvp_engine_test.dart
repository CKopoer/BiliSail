import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
import 'package:flutter_test/flutter_test.dart';

MediaTrack track(String path, {Map<String, String> headers = const {}}) =>
    MediaTrack(
      uri: Uri.parse('https://example.com/$path?token=private'),
      requestPolicy: MediaRequestPolicy(headers: headers),
    );

final class _Player extends Fake implements FvpPlayerPort, FvpInformationPort {
  final events = StreamController<FvpNativeStatus>.broadcast(sync: true);
  Completer<FvpMediaInfo>? preparation;
  Completer<int>? texture;
  bool audio = true;
  Completer<bool>? audioGate;
  bool released = false;
  bool playing = false;
  int interrupts = 0;
  int position = 1000;
  final seeks = <(Duration, Completer<int>)>[];
  bool holdSeek = false;
  Completer<PlayerPlaybackInformation?>? informationGate;
  @override
  Future<PlayerPlaybackInformation?> inspectPlaybackInformation({
    required int generation,
    required double audioGainDb,
  }) async =>
      informationGate?.future ??
      PlayerPlaybackInformation(
        generation: generation,
        backend: 'fvp / MDK',
        sourceFps: 30,
        audioGainDb: audioGainDb,
      );
  MediaTrack? main, sound;
  @override
  Stream<FvpNativeStatus> get statuses => events.stream;
  @override
  int get positionMilliseconds => position;
  @override
  int get bufferedMilliseconds => 2000;
  @override
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    MediaTrack? audioProbe,
    bool isLive = false,
  }) async {
    main = media;
    sound = audio;
    return await preparation?.future ??
        FvpMediaInfo(
          duration: const Duration(seconds: 12),
          dimensions: const VideoDimensions(320, 180),
          hasAudio: this.audio,
        );
  }

  @override
  Future<int> createTexture() async => await texture?.future ?? 1;
  @override
  Future<bool> confirmVideoFrame() async => true;
  @override
  Future<bool> confirmAudio() async => await audioGate?.future ?? audio;
  @override
  void play() => playing = true;
  @override
  void pause() => playing = false;
  @override
  void interrupt() {
    interrupts++;
    playing = false;
  }

  @override
  Future<int> seek(Duration target) async {
    final ready = Completer<int>();
    seeks.add((target, ready));
    // MDK exposes the requested position before the frame has decoded.
    position = target.inMilliseconds;
    return holdSeek ? ready.future : position;
  }

  @override
  void cancelSeek() {
    if (seeks.isNotEmpty && !seeks.last.$2.isCompleted) {
      seeks.last.$2.complete(-2);
    }
  }

  @override
  void setRate(double rate) {}
  @override
  void setVolume(double volume, double gainDb) {}
  @override
  Future<void> dispose() async {
    released = true;
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = DashPairSource(video: track('video'), audio: track('audio'));
  test(
    'information samples the native port and rejects retired source replies',
    () async {
      final first = _Player();
      final second = _Player();
      var player = first;
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      expect(await engine.inspectPlaybackInformation(), isNull);
      await engine.open(source, const OpenOptions(audioGainDb: -4));
      final info = await engine.inspectPlaybackInformation();
      expect(info?.sourceFps, 30);
      expect(info?.audioGainDb, -4);
      expect(info?.generation, engine.currentSnapshot.generation);
      first.informationGate = Completer<PlayerPlaybackInformation?>();
      final pending = engine.inspectPlaybackInformation();
      player = second;
      await engine.open(source, const OpenOptions());
      first.informationGate!.complete(info);
      expect(await pending, isNull);
      second.informationGate = Completer<PlayerPlaybackInformation?>();
      final closing = engine.inspectPlaybackInformation();
      await engine.dispose();
      second.informationGate!.complete(info);
      expect(await closing, isNull);
      expect(await engine.inspectPlaybackInformation(), isNull);
    },
  );
  test(
    'failed or timed out optional statistics do not change playback',
    () async {
      final player = _Player();
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await engine.open(source, const OpenOptions(play: true));
      player.informationGate = Completer<PlayerPlaybackInformation?>();
      final failed = engine.inspectPlaybackInformation();
      player.informationGate!.completeError(StateError('native closing'));
      expect(await failed, isNull);
      player.informationGate = Completer<PlayerPlaybackInformation?>();
      expect(await engine.inspectPlaybackInformation(), isNull);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      expect(player.released, false);
    },
  );
  test(
    'EOF survives trailing buffering events and pause until seeking',
    () async {
      final player = _Player();
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await engine.open(source, const OpenOptions(play: true));
      player.events.add(FvpNativeStatus.ended);
      player.events.add(FvpNativeStatus.buffering);
      player.events.add(FvpNativeStatus.buffered);
      expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
      expect(engine.currentSnapshot.isBuffering, false);
      await engine.pause();
      expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
      await engine.seek(Duration.zero);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    },
  );

  test('replay restarts position sampling after each EOF', () async {
    final player = _Player();
    final engine = FvpEngine(createPlayer: () async => player);
    addTearDown(engine.dispose);
    await engine.open(source, const OpenOptions(play: true));
    for (var replay = 0; replay < 2; replay++) {
      player.events.add(FvpNativeStatus.ended);
      await engine.seek(Duration.zero);
      await engine.play();
      player.position = 1000;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.currentSnapshot.position, const Duration(seconds: 1));
    }
  });

  test(
    'seek pauses both tracks until the target video frame is decoded',
    () async {
      final player = _Player()..holdSeek = true;
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await engine.open(source, const OpenOptions(play: true));
      final seeking = engine.seek(const Duration(milliseconds: 9375));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(player.playing, false);
      expect(engine.currentSnapshot.isSeeking, true);
      expect(engine.currentSnapshot.position, Duration.zero);
      player.events.add(FvpNativeStatus.buffered);
      expect(engine.currentSnapshot.phase, PlaybackPhase.buffering);
      player.seeks.single.$2.complete(9375);
      await seeking;
      expect(player.playing, true);
      expect(engine.currentSnapshot.position.inMilliseconds, 9375);
      expect(engine.currentSnapshot.isSeeking, false);
    },
  );

  for (final immediate in [false, true]) {
    test(
      'seek preserves a ${immediate ? 'same-turn' : 'pending'} manual pause',
      () async {
        final player = _Player()..holdSeek = true;
        final engine = FvpEngine(createPlayer: () async => player);
        addTearDown(engine.dispose);
        await engine.open(source, const OpenOptions(play: true));
        final seeking = engine.seek(const Duration(seconds: 9));
        if (!immediate) await Future<void>.delayed(Duration.zero);
        final pausing = engine.pause();
        await Future<void>.delayed(Duration.zero);
        player.seeks.single.$2.complete(9000);
        await Future.wait([seeking, pausing]);
        expect(player.playing, false);
        expect(engine.currentSnapshot.desiredPlaying, false);
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        expect(engine.currentSnapshot.isSeeking, false);
      },
    );
  }

  test(
    'rapid seeks cancel old preparation and only resume the latest target',
    () async {
      final player = _Player()..holdSeek = true;
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await engine.open(source, const OpenOptions(play: true));
      final first = engine.seek(const Duration(seconds: 9));
      await Future<void>.delayed(Duration.zero);
      final obsolete = engine.seek(const Duration(seconds: 5));
      final latest = engine.seek(const Duration(seconds: 2));
      await Future<void>.delayed(Duration.zero);
      await first.timeout(const Duration(milliseconds: 500));
      expect(player.seeks.first.$2.isCompleted, true);
      expect(player.seeks.map((seek) => seek.$1.inSeconds), [9, 2]);
      expect(player.playing, false);
      expect(engine.currentSnapshot.position, Duration.zero);
      expect(engine.currentSnapshot.isSeeking, true);
      player.seeks.last.$2.complete(2000);
      await Future.wait([first, obsolete, latest]);
      expect(player.playing, true);
      expect(engine.currentSnapshot.position.inSeconds, 2);
    },
  );

  test('stop cancels a blocked seek and ignores its late completion', () async {
    final player = _Player()..holdSeek = true;
    final engine = FvpEngine(createPlayer: () async => player);
    addTearDown(engine.dispose);
    await engine.open(source, const OpenOptions(play: true));
    final seeking = engine.seek(const Duration(seconds: 9));
    await Future<void>.delayed(Duration.zero);
    await engine.stop().timeout(const Duration(seconds: 1));
    await seeking;
    player.seeks.single.$2.complete(9000);
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, false);
    expect(player.released, true);
    expect(engine.currentSnapshot.phase, PlaybackPhase.idle);
    expect(engine.currentSnapshot.isSeeking, false);
  });

  test(
    'failed seeks interrupt the pending native slot and cannot resume playback',
    () async {
      final player = _Player()..holdSeek = true;
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await engine.open(source, const OpenOptions(play: true));
      final seeking = engine.seek(const Duration(seconds: 9));
      await Future<void>.delayed(Duration.zero);
      player.seeks.single.$2.complete(-1);
      await seeking;
      await engine.pause();
      await engine.play();
      await engine.seek(const Duration(seconds: 2));
      expect(player.seeks, hasLength(1));
      expect(player.interrupts, greaterThan(0));
      expect(player.playing, false);
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      expect(engine.currentSnapshot.isSeeking, false);
      expect(engine.currentSnapshot.desiredPlaying, false);
    },
  );
  test('seek deadline interrupts native work without resuming sound', () async {
    final player = _Player()..holdSeek = true;
    final engine = FvpEngine(createPlayer: () async => player);
    addTearDown(engine.dispose);
    await engine.open(source, const OpenOptions(play: true));
    final seeking = engine.seek(const Duration(seconds: 9));
    await seeking.timeout(const Duration(seconds: 17));
    expect(player.interrupts, greaterThan(0));
    expect(player.playing, false);
    expect(engine.currentSnapshot.isSeeking, false);
    expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
    player.seeks.single.$2.complete(9000);
    await Future<void>.delayed(Duration.zero);
    expect(player.playing, false);
    await engine.dispose();
  });

  test('reopening cancels an old seek and ignores its late target', () async {
    final first = _Player()..holdSeek = true;
    final second = _Player();
    var creations = 0;
    final engine = FvpEngine(
      createPlayer: () async => creations++ == 0 ? first : second,
    );
    addTearDown(engine.dispose);
    await engine.open(source, const OpenOptions(play: true));
    final oldGeneration = engine.currentSnapshot.generation;
    final seeking = engine.seek(const Duration(seconds: 9));
    await Future<void>.delayed(Duration.zero);
    await engine.open(source, const OpenOptions());
    await seeking;
    first.seeks.single.$2.complete(9000);
    await Future<void>.delayed(Duration.zero);
    expect(first.released, true);
    expect(second.playing, false);
    expect(engine.currentSnapshot.generation, greaterThan(oldGeneration));
    expect(engine.currentSnapshot.position, Duration.zero);
    expect(engine.currentSnapshot.isSeeking, false);
  });

  test(
    'pause cancels first-play audio readiness and ignores its late success',
    () async {
      final player = _Player()..audioGate = Completer<bool>();
      final engine = FvpEngine(createPlayer: () async => player);
      await engine.open(source, const OpenOptions());
      final playing = engine.play();
      await Future<void>.delayed(Duration.zero);
      await engine.pause().timeout(const Duration(seconds: 1));
      await playing;
      player.audioGate!.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, false);
      expect(engine.currentSnapshot.desiredPlaying, false);
      expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
      await engine.dispose();
    },
  );
  test('validates missing audio, unequal headers and invalid options before native allocation', () async {
    var creations = 0;
    final engine = FvpEngine(
      createPlayer: () async {
        creations++;
        return _Player();
      },
    );
    addTearDown(engine.dispose);
    for (final (source, options) in [
      (DashPairSource(video: track('video'), audio: null), const OpenOptions()),
      (DashVideoSource(track('video')), const OpenOptions(volume: 1)),
      (
        DashPairSource(
          video: track('video'),
          audio: track('audio', headers: {'Referer': 'other'}),
        ),
        const OpenOptions(),
      ),
      (source, const OpenOptions(openTimeout: Duration.zero)),
      (
        source,
        const OpenOptions(
          maxBufferAhead: Duration(minutes: 2, microseconds: 1),
        ),
      ),
      (
        DashVideoSource(track('video', headers: {'Referer': 'bad\r\nvalue'})),
        const OpenOptions(volume: 0),
      ),
    ]) {
      await expectLater(
        engine.open(source, options),
        throwsA(isA<PlayerFailure>()),
      );
    }
    expect(creations, 0);
  });

  test('uses one runtime for both tracks and preserves pause during buffering and seek', () async {
    final player = _Player();
    final engine = FvpEngine(createPlayer: () async => player);
    addTearDown(engine.dispose);
    await engine.open(source, const OpenOptions());
    expect(player.main, source.video);
    expect(player.sound, source.audio);
    expect(player.playing, false);
    player.events.add(FvpNativeStatus.buffering);
    expect(engine.currentSnapshot.desiredPlaying, false);
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    await engine.seek(const Duration(seconds: 3));
    expect(engine.currentSnapshot.position, const Duration(seconds: 3));
    expect(engine.currentSnapshot.desiredPlaying, false);
    await engine.play();
    expect(player.playing, true);
    await engine.pause();
    player.events.add(FvpNativeStatus.buffered);
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
  });

  test('stop cancels an indefinitely pending prepare and releases before next open', () async {
    final first = _Player()..preparation = Completer<FvpMediaInfo>();
    final second = _Player();
    var calls = 0;
    final engine = FvpEngine(
      createPlayer: () async => calls++ == 0 ? first : second,
    );
    final opening = engine.open(source, const OpenOptions());
    await Future<void>.delayed(Duration.zero);
    await engine.stop().timeout(const Duration(seconds: 1));
    await opening;
    expect(first.released, true);
    await engine.open(source, const OpenOptions());
    first.preparation!.complete(
      const FvpMediaInfo(duration: Duration.zero, hasAudio: true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
    await engine.dispose();
  });

  test(
    'late factory completion after disposal is released without publishing',
    () async {
      final factory = Completer<FvpPlayerPort>();
      final player = _Player();
      final engine = FvpEngine(createPlayer: () => factory.future);
      final opening = engine.open(source, const OpenOptions());
      await Future<void>.delayed(Duration.zero);
      final closing = engine.dispose();
      factory.complete(player);
      await Future.wait([opening, closing]);
      expect(player.released, true);
      expect(player.main, isNull);
    },
  );

  test('missing decoded external audio and open deadlines fail safely without URL leaks', () async {
    for (final stalled in [false, true]) {
      final player = _Player()..audio = false;
      if (stalled) player.preparation = Completer<FvpMediaInfo>();
      final engine = FvpEngine(createPlayer: () async => player);
      await expectLater(
        engine.open(
          source,
          const OpenOptions(
            play: true,
            openTimeout: Duration(milliseconds: 30),
          ),
        ),
        throwsA(
          isA<PlayerFailure>().having(
            (error) => error.message,
            'safe message',
            isNot(contains('private')),
          ),
        ),
      );
      expect(player.released, true);
      await engine.dispose();
    }
  });
}
