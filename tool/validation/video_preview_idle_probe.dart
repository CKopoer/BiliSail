import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:flutter/material.dart';

// Run with flutter run -d windows -t tool/validation/video_preview_idle_probe.dart.
// A production binding is essential: integration tests pump frames themselves.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(home: Scaffold(body: Text('Idle preview probe'))));
  await Future<void>.delayed(const Duration(seconds: 1));
  final results = <Map<String, Object?>>[];
  for (var attempt = 0; attempt < 2; attempt++) {
    final engine = MediaKitEngine();
    final watch = Stopwatch()..start();
    var completed = false;
    var opened = false;
    var outputAtOpen = false;
    final pending = engine
        .open(
          DashVideoSource(
            MediaTrack(
              uri: File('test/fixtures/media/video.mp4').absolute.uri,
              requestPolicy: MediaRequestPolicy(),
            ),
          ),
          const OpenOptions(
            play: true,
            volume: 0,
            openTimeout: Duration(seconds: 3),
          ),
        )
        .then<void>(
          (_) {
            completed = true;
            opened = true;
            outputAtOpen = engine.inspectDiagnostics().hasVideoOutput;
          },
          onError: (Object _, StackTrace _) {
            completed = true;
          },
        );
    // No surface, animation, mouse motion or tester.pump may supply a frame.
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!completed && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    final decoded = engine.inspectDiagnostics().hasDecodedVideo;
    final result = <String, Object?>{
      'attempt': attempt,
      'completed': completed,
      'opened': opened,
      'decoded': decoded,
      'outputAtOpen': outputAtOpen,
      'elapsedMs': watch.elapsedMilliseconds,
      'phase': engine.currentSnapshot.phase.name,
    };
    results.add(result);
    debugPrint('IDLE_PREVIEW_PROBE ${jsonEncode(result)}');
    if (!completed) {
      // Only after recording failure, unblock the old initialization so cleanup
      // can finish. This frame cannot be counted as successful idle opening.
      WidgetsBinding.instance.scheduleFrame();
    }
    await pending.timeout(const Duration(seconds: 5));
    await engine.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  final report = File(
    const String.fromEnvironment(
      'BILI_IDLE_PROBE_OUTPUT',
      defaultValue: 'build/validation/video-preview-idle.json',
    ),
  );
  await report.parent.create(recursive: true);
  await report.writeAsString(jsonEncode(results));
  exit(
    results.every(
          (result) =>
              result['opened'] == true &&
              result['decoded'] == true &&
              result['outputAtOpen'] == true,
        )
        ? 0
        : 1,
  );
}
