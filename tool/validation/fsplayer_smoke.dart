import 'dart:async';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/macos_application_window.dart';
import 'package:bilisail/core/presentation/bili_widgets_binding.dart';
import 'package:flutter/material.dart';

/// Native Apple smoke; fixed public fixtures, no account or product settings.
Future<void> main() async {
  stdout.writeln('FSPLAYER_SMOKE_STAGE=entry');
  await stdout.flush();
  BiliWidgetsBinding.ensureInitialized();
  stdout.writeln('FSPLAYER_SMOKE_STAGE=window');
  final engine = FsPlayerEngine();
  var result = 1;
  var stage = 'window';
  try {
    final window = await MacOSApplicationWindow.create();
    if (window != null) await window.prepare();
    final app = MaterialApp(
      home: Scaffold(body: VideoSurface(engine: engine)),
    );
    if (window == null) {
      runApp(app);
    } else {
      window.present(app);
      await window.service.activate();
    }
    stage = 'dash';
    stdout.writeln('FSPLAYER_SMOKE_STAGE=$stage');
    await stdout.flush();
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
    stage = 'clock';
    await engine.play();
    await Future<void>.delayed(const Duration(seconds: 2));
    if (engine.currentSnapshot.position < const Duration(seconds: 1)) {
      throw StateError('Clock stalled');
    }
    stage = 'seek';
    await engine.setRate(2);
    await engine.seek(const Duration(seconds: 5));
    await engine.pause();
    await engine.seek(const Duration(seconds: 2));
    if (engine.currentSnapshot.desiredPlaying ||
        engine.currentSnapshot.isSeeking) {
      throw StateError('Paused seek');
    }
    stage = 'audio';
    await engine.stop();
    await engine.open(
      ProgressiveSource(track('audio.m4a'), isAudioOnly: true),
      const OpenOptions(play: true, volume: 0),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    result = 0;
  } on Object catch (error) {
    stdout.writeln('FSPLAYER_SMOKE_FAILED $stage ${error.runtimeType}');
  } finally {
    await engine.dispose();
  }
  stdout.writeln('FSPLAYER_SMOKE_RESULT=$result');
  await stdout.flush();
  exit(result);
}
