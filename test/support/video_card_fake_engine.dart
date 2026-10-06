import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

PlaybackMedia cardPreviewMedia({bool backups = false}) => PlaybackMedia(
  video: PlaybackTrack(
    urls: [
      Uri.parse('https://example.com/video'),
      if (backups) Uri.parse('https://backup.example.com/video'),
    ],
    codec: 'avc1',
    bandwidth: 1000,
  ),
  audio: PlaybackTrack(
    urls: [
      Uri.parse('https://example.com/audio'),
      if (backups) Uri.parse('https://backup.example.com/audio'),
    ],
    codec: 'mp4a',
    bandwidth: 100,
  ),
  quality: 16,
  qualities: const [16],
  duration: const Duration(seconds: 20),
  headers: const {'Referer': 'https://www.bilibili.com/'},
);

class CardFakeEngine extends Fake implements PlayerEngine, VideoSurfaceSource {
  final events = StreamController<PlaybackSnapshot>.broadcast(sync: true);
  final errors = StreamController<PlayerFailure>.broadcast(sync: true);
  PlaybackSnapshot snapshot = const PlaybackSnapshot(
    phase: PlaybackPhase.idle,
    generation: 0,
  );
  ResolvedMediaSource? source;
  OpenOptions? options;
  Completer<void>? opening, releasing;
  PlayerFailure? stopFailure, disposeFailure;
  int opens = 0, stops = 0, disposals = 0, seeks = 0;
  @override
  PlaybackSnapshot get currentSnapshot => snapshot;
  @override
  Stream<PlaybackSnapshot> get snapshots => events.stream;
  @override
  Stream<PlayerFailure> get failures => errors.stream;
  void advance(Duration position) =>
      publish(snapshot.copyWith(position: position));
  void publish(PlaybackSnapshot next) {
    snapshot = next;
    if (!events.isClosed) events.add(next);
  }

  @override
  Future<void> open(ResolvedMediaSource source, OpenOptions options) async {
    opens++;
    this.source = source;
    this.options = options;
    final generation = snapshot.generation + 1;
    publish(
      PlaybackSnapshot(
        phase: PlaybackPhase.opening,
        generation: generation,
        desiredPlaying: options.play,
        volume: options.volume,
      ),
    );
    await opening?.future;
    if (generation != snapshot.generation) return;
    publish(
      snapshot.copyWith(
        phase: options.play ? PlaybackPhase.playing : PlaybackPhase.paused,
        duration: const Duration(seconds: 20),
      ),
    );
  }

  @override
  Future<void> stop() async {
    stops++;
    publish(
      PlaybackSnapshot(
        phase: PlaybackPhase.idle,
        generation: snapshot.generation + 1,
      ),
    );
    await releasing?.future;
    if (stopFailure case final failure?) throw failure;
  }

  @override
  Future<void> dispose() async {
    disposals++;
    publish(snapshot.copyWith(phase: PlaybackPhase.disposed));
    await events.close();
    await errors.close();
    if (disposeFailure case final failure?) throw failure;
  }

  @override
  Future<void> seek(Duration target) async {
    seeks++;
    advance(target);
  }

  @override
  Widget buildVideoSurface() => const ColoredBox(
    key: ValueKey('fake-card-video-surface'),
    color: Color(0xff336487),
    child: Center(
      child: Icon(IconData(0xe039, fontFamily: 'MaterialIcons'), size: 48),
    ),
  );
}
