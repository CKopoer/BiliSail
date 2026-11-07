import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/fvp_native_player.dart';
import 'package:flutter_test/flutter_test.dart';

MediaTrack track(String path, {Map<String, String> headers = const {}}) =>
    MediaTrack(
      uri: Uri.parse('https://example.com/$path?token=private'),
      requestPolicy: MediaRequestPolicy(headers: headers),
    );

final class _Player extends Fake implements FvpPlayerPort {
  final events = StreamController<FvpNativeStatus>.broadcast(sync: true);
  Completer<FvpMediaInfo>? preparation;
  Completer<int>? texture;
  bool audio = true;
  Completer<bool>? audioGate;
  bool released = false;
  bool playing = false;
  int interrupts = 0;
  MediaTrack? main, sound;
  @override
  Stream<FvpNativeStatus> get statuses => events.stream;
  @override
  int get positionMilliseconds => 1000;
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
  Future<int> seek(Duration target) async => target.inMilliseconds;
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
      (source, const OpenOptions(maxBufferAhead: Duration(minutes: 6))),
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
