import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

// Use a production binding and Profile build: native texture updates are not
// represented by Flutter FrameTiming or the backend's playback position alone.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await _probe();
    exit(0);
  } on Object catch (failure) {
    debugPrint('PREVIEW_CONTENTION_FAILED ${failure.runtimeType}');
    exit(1);
  }
}

Future<void> _probe() async {
  final mainEngine = MediaKitEngine();
  runApp(
    MaterialApp(
      home: Scaffold(
        body: Row(
          children: [
            Expanded(child: VideoSurface(engine: mainEngine)),
            const SizedBox(width: 160, child: Text('Preview contention probe')),
          ],
        ),
      ),
    ),
  );
  try {
    final mediaDirectory = Platform.environment['BILI_TEST_MEDIA_DIR'];
    if (mediaDirectory == null) {
      throw StateError('BILI_TEST_MEDIA_DIR is required');
    }
    MediaTrack track(String name) => MediaTrack(
      uri: File('$mediaDirectory/$name').absolute.uri,
      requestPolicy: MediaRequestPolicy(),
    );
    await Future<void>.delayed(const Duration(seconds: 1));
    await mainEngine.open(
      ProgressiveSource(track('main.mp4')),
      const OpenOptions(play: true),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    final results = <Map<String, Object?>>[];
    for (var attempt = 0; attempt < 4; ++attempt) {
      debugPrint(
        'PREVIEW_STAGE start=$attempt atMs=${DateTime.now().millisecondsSinceEpoch}',
      );
      final preview = MediaKitEngine();
      try {
        final watch = Stopwatch()..start();
        final mainBefore = mainEngine.currentSnapshot.position;
        await preview.open(
          DashVideoSource(track('preview.mp4')),
          const OpenOptions(
            play: true,
            volume: 0,
            openTimeout: Duration(seconds: 3),
            maxBufferAhead: Duration(seconds: 5),
          ),
        );
        final outputAtOpen = preview.inspectDiagnostics().hasVideoOutput;
        final openMs = watch.elapsedMilliseconds;
        await Future<void>.delayed(const Duration(seconds: 1));
        final snapshot = mainEngine.currentSnapshot;
        results.add({
          'attempt': attempt,
          'openMs': openMs,
          'previewOutput': outputAtOpen,
          'previewDecodedAudio': preview.inspectDiagnostics().hasDecodedAudio,
          'mainAdvanceMs': (snapshot.position - mainBefore).inMilliseconds,
          'mainPlaying': snapshot.phase == PlaybackPhase.playing,
          'mainBuffering': snapshot.isBuffering,
          'mainDecodedAudio': mainEngine.inspectDiagnostics().hasDecodedAudio,
        });
        debugPrint(
          'PREVIEW_STAGE dispose=$attempt atMs=${DateTime.now().millisecondsSinceEpoch}',
        );
      } finally {
        await preview.dispose();
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final report = File('build/validation/video-preview-contention.json');
    await report.parent.create(recursive: true);
    await report.writeAsString(jsonEncode(results));
    debugPrint('PREVIEW_CONTENTION ${jsonEncode(results)}');
  } finally {
    await mainEngine.dispose();
  }
}
