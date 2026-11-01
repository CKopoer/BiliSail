import 'dart:async';

import 'package:bili_player/src/native_player_properties.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

final class _Player extends Fake implements mk.NativePlayer {
  @override
  final current = <mk.Media>[];
  @override
  final state = mk.PlayerState();
  @override
  final playingController = StreamController<bool>.broadcast();
  @override
  bool isPlayingStateChangeAllowed = false;
  @override
  bool isBufferingStateChangeAllowed = true;
  final properties = <(String, String)>[];
  final commands = <List<String>>[];
  final seeks = <Duration>[];
  var openedStop = false;
  @override
  bool disposed = false;

  @override
  void throwIfDisposed() {
    if (disposed) throw StateError('Disposed');
  }

  @override
  void setProperty(String name, String value) {
    properties.add((name, value));
    if (name == 'pause' && isPlayingStateChangeAllowed) {
      state.playing = value == 'no';
      playingController.add(state.playing);
    }
  }

  @override
  Future<void> stop({bool open = false, bool synchronized = true}) async {
    openedStop = open;
    state.playing = false;
  }

  @override
  Future<void> add(mk.Media media, {bool synchronized = true}) async {
    current.add(media);
  }

  @override
  Future<void> command(List<String> args) async => commands.add(args);

  @override
  Future<void> seek(Duration position, {bool synchronized = true}) async {
    seeks.add(position);
    state.completed = false;
  }
}

void main() {
  test('paused open preserves the media and replaces the previous playlist', () async {
    final player = _Player();
    addTearDown(player.playingController.close);
    player.current.add(const mk.Media('old'));
    const media = mk.Media(
      'https://example.test/video?k=a%2Fb',
      start: Duration(milliseconds: 1700),
    );
    // Fake's inherited open/play/pause throw: the unsafe FLAG methods must not
    // be used while exercising the real adapter.
    await player.openPausedMedia(media);
    expect(player.openedStop, isTrue);
    expect(player.current, [same(media)]);
    expect(player.properties, [('pause', 'yes')]);
    expect(player.commands, [
      ['playlist-play-index', '0'],
    ]);
    expect(player.state.playing, isFalse);
  });

  test(
    'play, pause and completed replay use string flags and retain events',
    () async {
      final player = _Player();
      addTearDown(player.playingController.close);
      final states = <bool>[];
      final subscription = player.playingController.stream.listen(states.add);
      addTearDown(subscription.cancel);
      await player.playWithStringFlag();
      expect(player.isPlayingStateChangeAllowed, isTrue);
      await player.pauseWithStringFlag();
      expect(player.isPlayingStateChangeAllowed, isTrue);
      expect(player.isBufferingStateChangeAllowed, isFalse);
      player.state.completed = true;
      await player.playWithStringFlag();
      await Future<void>.delayed(Duration.zero);
      expect(states, [true, false, true]);
      expect(player.properties, [
        ('pause', 'no'),
        ('pause', 'yes'),
        ('pause', 'no'),
      ]);
      expect(player.seeks, [Duration.zero]);
      expect(player.commands, [
        ['playlist-play-index', '0'],
      ]);
      expect(player.state.playing, isTrue);
      player.disposed = true;
      await expectLater(player.playWithStringFlag(), throwsStateError);
      await expectLater(player.pauseWithStringFlag(), throwsStateError);
    },
  );
}
