import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';

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
  double volume = 0;
  Completer<bool>? videoGate;
  Completer<void>? pauseGate;
  int interrupts = 0;
  int position = 1000;
  int buffered = 2000;
  Duration duration = const Duration(seconds: 12);
  final seeks = <(Duration, Completer<int>)>[];
  bool holdSeek = false;
  Object? seekCancellationError;
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
  int get bufferedMilliseconds => buffered;
  @override
  Future<FvpMediaInfo> prepare(
    MediaTrack media,
    MediaTrack? audio,
    OpenOptions options, {
    required bool silent,
    bool isLive = false,
  }) async {
    main = media;
    sound = audio;
    return await preparation?.future ??
        FvpMediaInfo(
          duration: duration,
          dimensions: const VideoDimensions(320, 180),
          hasAudio: this.audio,
        );
  }

  @override
  Future<int> createTexture() async => await texture?.future ?? 1;
  @override
  Future<bool> confirmVideoFrame() async => await videoGate?.future ?? true;
  @override
  Future<bool> confirmAudio() async => await audioGate?.future ?? audio;
  @override
  void play() => playing = true;
  @override
  void pause() => playing = false;
  @override
  Future<void> pauseAndWait() async {
    pause();
    await pauseGate?.future;
  }

  @override
  void interrupt() {
    interrupts++;
    playing = false;
  }

  @override
  Future<int> seek(Duration target) async {
    pause();
    final ready = Completer<int>();
    seeks.add((target, ready));
    // MDK exposes the requested position before the frame has decoded.
    position = target.inMilliseconds;
    final result = holdSeek ? await ready.future : position;
    if (result >= 0) {
      final gate = audioGate;
      if (gate != null && !await gate.future) return -1;
    }
    return result;
  }

  @override
  Future<void> cancelSeek() async {
    if (seeks.isNotEmpty && !seeks.last.$2.isCompleted) {
      if (seekCancellationError case final error?) {
        seeks.last.$2.completeError(error);
      } else {
        seeks.last.$2.complete(-2);
      }
    }
  }

  @override
  void setRate(double rate) {}
  @override
  void setVolume(double volume, double gainDb) => this.volume = volume;
  @override
  Future<void> dispose() async {
    released = true;
    await events.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = DashPairSource(video: track('video'), audio: track('audio'));
  testWidgets(
    'buffer display correction preserves raw health and resets on seek',
    (tester) async {
      final player = _Player()
        ..duration = const Duration(seconds: 120)
        ..position = 10000
        ..buffered = 10000;
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await engine.open(source, const OpenOptions());
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 20));

      player
        ..position = 10250
        ..buffered = 9670;
      await tester.pump(const Duration(milliseconds: 250));
      expect(engine.currentSnapshot.buffered, const Duration(seconds: 20));
      expect(
        engine.activeBackend!.sampleHealth().buffered,
        const Duration(milliseconds: 19920),
      );

      player.events.add(FvpNativeStatus.buffering);
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        engine.currentSnapshot.buffered,
        const Duration(milliseconds: 19920),
      );
      player.events.add(FvpNativeStatus.buffered);

      player.buffered = 10000;
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        engine.currentSnapshot.buffered,
        const Duration(milliseconds: 20250),
      );
      player.buffered = 9200;
      await engine.seek(const Duration(seconds: 11));
      expect(
        engine.currentSnapshot.buffered,
        const Duration(milliseconds: 20200),
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(
        engine.currentSnapshot.buffered,
        const Duration(milliseconds: 20200),
      );
      await tester.runAsync(engine.dispose);
    },
  );
  testWidgets(
    'autoplay stays paused until native A/V and revealed Flutter frame',
    (tester) async {
      final player = _Player()
        ..videoGate = Completer<bool>()
        ..audioGate = Completer<bool>();
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: VideoSurface(engine: engine),
        ),
      );
      final opening = engine.open(
        source,
        const OpenOptions(play: true, volume: 37),
      );
      await tester.pump();
      expect(player.volume, 37);
      expect(player.playing, false);
      player.videoGate!.complete(true);
      await tester.pumpAndSettle();
      expect(player.playing, false);
      expect(player.volume, 37);
      expect(engine.currentSnapshot.phase, PlaybackPhase.opening);
      player.audioGate!.complete(true);
      await tester.pump();
      expect(player.playing, false, reason: 'Presentation has not confirmed');
      await tester.pumpAndSettle();
      await opening;
      expect(player.volume, 37);
      expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
      await tester.runAsync(engine.dispose);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  for (final action in ['stop', 'pause', 'timeout']) {
    test(
      'startup $action never releases audio before video readiness',
      () async {
        final player = _Player()..videoGate = Completer<bool>();
        final engine = FvpEngine(createPlayer: () async => player);
        addTearDown(engine.dispose);
        final opening = engine.open(
          source,
          OpenOptions(
            play: true,
            volume: 37,
            openTimeout: const Duration(milliseconds: 100),
          ),
        );
        final result = action == 'timeout'
            ? expectLater(opening, throwsA(isA<PlayerFailure>()))
            : opening;
        await Future<void>.delayed(Duration.zero);
        if (action == 'stop') await engine.stop();
        if (action == 'pause') {
          final pausing = engine.pause();
          player.videoGate!.complete(true);
          await pausing;
        }
        await result;
        expect(player.playing, false);
        expect(player.volume, 37);
        if (action != 'pause') player.videoGate!.complete(true);
        await Future<void>.delayed(Duration.zero);
        expect(player.playing, false);
      },
    );
  }
  test(
    'pause acknowledgement keeps startup paused after a user pause',
    () async {
      final player = _Player()
        ..audioGate = Completer<bool>()
        ..pauseGate = Completer<void>();
      final engine = FvpEngine(createPlayer: () async => player);
      addTearDown(engine.dispose);
      final opening = engine.open(
        source,
        const OpenOptions(play: true, volume: 37),
      );
      await Future<void>.delayed(Duration.zero);
      expect(player.playing, false);
      final pausing = engine.pause();
      player.audioGate!.complete(true);
      await Future<void>.delayed(Duration.zero);
      expect(player.volume, 37);
      player.pauseGate!.complete();
      await Future.wait([opening, pausing]);
      expect(player.playing, false);
      expect(engine.currentSnapshot.desiredPlaying, false);
      expect(player.volume, 37);
    },
  );
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
      player.position = 12000;
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
      player.position = 12000;
      player.events.add(FvpNativeStatus.ended);
      await engine.seek(Duration.zero);
      await engine.play();
      player.position = 1000;
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(engine.currentSnapshot.position, const Duration(seconds: 1));
    }
  });

  test(
    'premature main-video EOF pauses the surviving external audio',
    () async {
      final player = _Player();
      final diagnostics = <PlayerDiagnosticEvent>[];
      final engine = FvpEngine(
        createPlayer: () async => player,
        onDiagnostic: diagnostics.add,
      );
      addTearDown(engine.dispose);
      final failures = <PlayerFailure>[];
      final subscription = engine.failures.listen(failures.add);
      addTearDown(subscription.cancel);
      await engine.open(source, const OpenOptions(play: true));
      player.position = 4000;
      player.events.add(FvpNativeStatus.ended);
      expect(player.playing, isFalse);
      // Terminal failure follows the actual native pause acknowledgement.
      await Future<void>.delayed(Duration.zero);
      expect(engine.currentSnapshot.phase, PlaybackPhase.failed);
      expect(failures.single.kind, PlayerFailureKind.videoInterrupted);
      expect(
        diagnostics
            .singleWhere((e) => e.kind == PlayerDiagnosticKind.playbackStalled)
            .stallReason,
        PlaybackStallReason.videoBuffer,
      );
    },
  );

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
      expect(engine.currentSnapshot.isBuffering, false);
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

  for (final pauseAfterVideo in [false, true]) {
    test(
      'seek ${pauseAfterVideo ? 'pause' : 'resume'} waits for audio after the video target',
      () async {
        final player = _Player()
          ..holdSeek = true
          ..duration = const Duration(minutes: 2);
        final engine = FvpEngine(createPlayer: () async => player);
        addTearDown(engine.dispose);
        await engine.open(source, const OpenOptions(play: true));
        player.audioGate = Completer<bool>();
        final seeking = engine.seek(const Duration(milliseconds: 71133));
        await Future<void>.delayed(Duration.zero);
        player.seeks.single.$2.complete(71133);
        await Future<void>.delayed(Duration.zero);
        expect(player.playing, false);
        expect(engine.currentSnapshot.isSeeking, true);
        expect(engine.currentSnapshot.isBuffering, false);
        expect(engine.currentSnapshot.position, Duration.zero);
        if (pauseAfterVideo) await engine.pause();
        player.audioGate!.complete(true);
        await seeking;
        expect(player.playing, !pauseAfterVideo);
        expect(engine.currentSnapshot.desiredPlaying, !pauseAfterVideo);
        expect(engine.currentSnapshot.isSeeking, false);
        expect(
          engine.currentSnapshot.phase,
          pauseAfterVideo ? PlaybackPhase.paused : PlaybackPhase.playing,
        );
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

  for (final retiredEvent in ['EOF', 'error']) {
    test(
      'retired seek $retiredEvent cannot fail or release the latest target',
      () async {
        final player = _Player()..holdSeek = true;
        if (retiredEvent == 'error') {
          player.seekCancellationError = StateError('retired native seek');
        }
        final engine = FvpEngine(createPlayer: () async => player);
        addTearDown(engine.dispose);
        await engine.open(source, const OpenOptions(play: true));
        final old = engine.seek(const Duration(seconds: 11));
        await Future<void>.delayed(Duration.zero);
        if (retiredEvent == 'EOF') {
          player.events.add(FvpNativeStatus.ended);
          expect(engine.currentSnapshot.isSeeking, true);
          expect(engine.currentSnapshot.desiredPlaying, true);
        }
        final latest = engine.seek(const Duration(seconds: 2));
        await old.timeout(const Duration(milliseconds: 500));
        await Future<void>.delayed(Duration.zero);
        expect(player.seeks, hasLength(2));
        expect(engine.currentSnapshot.isBuffering, false);
        expect(engine.currentSnapshot.isSeeking, true);
        player.seeks.last.$2.complete(2000);
        await latest;
        expect(engine.currentSnapshot.phase, PlaybackPhase.playing);
        expect(engine.currentSnapshot.position.inSeconds, 2);
        expect(player.interrupts, 0);
      },
    );
  }

  for (final output in AndroidVideoOutputMode.values) {
    for (final intent in ['playing', 'paused', 'pauseDuringSeek']) {
      test(
        'configured fvp replaces pending seeks: ${output.name}, $intent',
        () async {
          final player = _Player()..holdSeek = true;
          final engine = ConfigurablePlayerEngine(
            createEngine: () async =>
                FvpEngine(createPlayer: () async => player),
          );
          addTearDown(engine.dispose);
          await engine.open(
            source,
            OpenOptions(play: intent != 'paused', androidVideoOutput: output),
          );
          final first = engine.seek(const Duration(seconds: 9));
          await Future<void>.delayed(Duration.zero);
          // An ordinary control queued behind the first seek must not prevent
          // the next target from reaching the backend's cancellation path.
          final volume = engine.setVolume(30);
          final rate = engine.setRate(1.5);
          final pausing = intent == 'pauseDuringSeek' ? engine.pause() : null;
          final obsolete = engine.seek(const Duration(seconds: 5));
          final latest = engine.seek(const Duration(seconds: 2));
          await Future<void>.delayed(Duration.zero);
          expect(player.seeks.map((seek) => seek.$1.inSeconds), [9, 2]);
          await first.timeout(const Duration(milliseconds: 500));
          expect(player.playing, false);
          expect(engine.currentSnapshot.isSeeking, true);
          player.seeks.last.$2.complete(2000);
          await Future.wait([first, volume, rate, ?pausing, obsolete, latest]);
          expect(player.playing, intent == 'playing');
          expect(engine.currentSnapshot.position.inSeconds, 2);
          expect(engine.currentSnapshot.isSeeking, false);
          expect(engine.currentSnapshot.rate, 1.5);
          expect(engine.currentSnapshot.volume, 30);
        },
      );
    }
  }

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
      final failed = expectLater(seeking, throwsA(isA<PlayerFailure>()));
      await Future<void>.delayed(Duration.zero);
      player.seeks.single.$2.complete(-1);
      await failed;
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
    await expectLater(
      seeking.timeout(const Duration(seconds: 17)),
      throwsA(isA<PlayerFailure>()),
    );
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
      await engine.dispose();
      expect(player.released, true);
    }
  });
}
