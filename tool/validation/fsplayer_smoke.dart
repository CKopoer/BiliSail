import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

/// Native Apple smoke; fixed public fixtures, no account or product settings.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final engine = FsPlayerEngine();
  runApp(
    MaterialApp(
      home: Scaffold(body: VideoSurface(engine: engine)),
    ),
  );
  var result = 1;
  try {
    const root = String.fromEnvironment('FSPLAYER_FIXTURE_ROOT');
    if (root.isEmpty) throw StateError('Fixture root is required');
    MediaTrack track(String name) => MediaTrack(
      uri: File('$root/$name').uri,
      requestPolicy: MediaRequestPolicy(),
    );
    await engine.open(
      DashPairSource(
        video: track('video.mp4'),
        audio: track('audio.m4a'),
        duration: const Duration(seconds: 12),
      ),
      const OpenOptions(play: false, volume: 0),
    );
    if (engine.currentSnapshot.desiredPlaying) throw StateError('Paused open');
    final info = await engine.inspectPlaybackInformation();
    if (info?.diagnostics?.hasDecodedVideo != true ||
        info?.diagnostics?.hasDecodedAudio != true) {
      throw StateError('Missing decoded tracks');
    }
    await engine.play();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (engine.currentSnapshot.position < const Duration(seconds: 1)) {
      throw StateError('Clock stalled');
    }
    await engine.setRate(2);
    await engine.seek(const Duration(seconds: 5));
    await engine.pause();
    await engine.seek(const Duration(seconds: 2));
    if (engine.currentSnapshot.desiredPlaying ||
        engine.currentSnapshot.isSeeking) {
      throw StateError('Paused seek');
    }
    await engine.stop();
    await engine.open(
      ProgressiveSource(track('audio.m4a'), isAudioOnly: true),
      const OpenOptions(play: true, volume: 0),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    result = 0;
  } on Object catch (error) {
    stdout.writeln('FSPLAYER_SMOKE_FAILED ${error.runtimeType}');
  } finally {
    await engine.dispose();
  }
  stdout.writeln('FSPLAYER_SMOKE_RESULT=$result');
  exit(result);
}
