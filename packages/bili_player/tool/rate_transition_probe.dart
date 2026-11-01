import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart' as mk;

import 'package:bili_player/bili_player.dart';
import 'package:bili_player/src/media_kit_video_output.dart';
import 'package:bili_player/src/native_media_options.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bili_player/src/native_rate_audio.dart';
import 'package:bili_player/src/video_dimensions.dart';

// Run from the app root with flutter run --profile -d windows -t this file.
// Local fixtures only. Compare the old 200 ms queue with production's 50 ms
// queue in ABBA order through the same Flutter video output and locked libmpv.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  initializePlayerBackend();
  final root = Directory(
    Platform.environment['BILI_RATE_MEDIA_DIR'] ?? 'test/fixtures/media',
  ).absolute;
  final video = File('${root.path}/video.mp4');
  final audio = File('${root.path}/audio.m4a');
  if (!await video.exists() || !await audio.exists()) {
    throw StateError('Local video.mp4 and audio.m4a fixtures are required.');
  }
  final label = Platform.environment['BILI_RATE_LABEL'] ?? 'local';
  if (!RegExp(r'^[\w-]+$').hasMatch(label)) {
    throw StateError('Invalid probe label.');
  }
  final report = File('build/validation/hold-rate-flutter-$label.json');
  if (await report.exists()) throw StateError('Use a fresh probe label.');
  await report.parent.create(recursive: true);
  final results = <Map<String, Object?>>[];

  for (final bufferSeconds in [0.2, 0.05, 0.05, 0.2]) {
    final player = await mk.Player.create(
      configuration: const mk.PlayerConfiguration(
        logLevel: mk.MPVLogLevel.warn,
      ),
    );
    final output = MediaKitVideoOutput();
    final dimensions = player.stream.videoParams.listen((value) {
      output.updateVideoDimensions(videoDisplayDimensions(value));
    });
    try {
      runApp(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 640,
                height: 360,
                child: VideoSurface.output(output: output),
              ),
            ),
          ),
        ),
      );
      await output.bindPlayer(
        player,
        generation: 1,
        decoding: VideoDecodingMode.automatic,
      );
      await configureNativeRateAudio(
        write: player.setPropertyAsync,
        read: player.getPropertyAsync,
        isCurrent: () => true,
        timeout: const Duration(seconds: 5),
      );
      if (bufferSeconds == 0.2) {
        // The sole baseline override; production configuration is untouched.
        player.setProperty('audio-buffer', '0.2');
      }
      player.setProperty(
        'audio-files',
        mpvPathListEntry(audio.uri, windows: Platform.isWindows),
      );
      await player.openPausedMedia(mk.Media(video.uri.toString()));
      await player.setVolume(0);
      await player.playWithStringFlag();
      await output.firstFrameRendered.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 1));
      final run = <String, Object?>{
        'requestedBufferSeconds': bufferSeconds,
        'appliedBufferSeconds': player.getProperty('audio-buffer'),
        'tempoFilter': player.getProperty('af'),
        'mpvVersion': player.getProperty('mpv-version'),
        'hardwareDecoder': player.getProperty('hwdec-current'),
        'videoSync': player.getProperty('video-sync'),
      };
      final transitions = <Map<String, Object?>>[];
      for (final rate in [2.0, 1.0, 2.0, 1.0, 2.0, 1.0]) {
        final clock = Stopwatch()..start();
        await player.setRate(rate);
        final commandUs = clock.elapsedMicroseconds;
        final points = <Map<String, Object?>>[];
        String? previousPosition;
        var lastChangeUs = 0;
        var maxGapUs = 0;
        var maxAvsync = 0.0;
        while (clock.elapsed < const Duration(milliseconds: 750)) {
          final position = player.getProperty('time-pos');
          final avsync = double.tryParse(player.getProperty('avsync')) ?? 0;
          final nowUs = clock.elapsedMicroseconds;
          if (position != previousPosition) {
            final gap = nowUs - lastChangeUs;
            if (gap > maxGapUs) maxGapUs = gap;
            lastChangeUs = nowUs;
            previousPosition = position;
          }
          if (avsync.abs() > maxAvsync) maxAvsync = avsync.abs();
          points.add({'atUs': nowUs, 'position': position, 'avsync': avsync});
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        transitions.add({
          'rate': rate,
          'commandUs': commandUs,
          'maxPositionGapUs': maxGapUs,
          'maxAbsAvsyncSeconds': maxAvsync,
          'frameDrops': player.getProperty('frame-drop-count'),
          'decoderDrops': player.getProperty('decoder-frame-drop-count'),
          'points': points,
        });
      }
      run['transitions'] = transitions;
      results.add(run);
      await report.writeAsString(jsonEncode(results));
      debugPrint(
        'RATE_PROBE ${jsonEncode({
          ...run,
          'transitions': [for (final value in transitions) Map.of(value)..remove('points')],
        })}',
      );
    } finally {
      runApp(const SizedBox());
      await WidgetsBinding.instance.endOfFrame;
      output.clearPlayer();
      await dimensions.cancel();
      await player.dispose();
      output.dispose();
    }
  }
  exit(0);
}
