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
// Local fixtures only. Each experiment changes one setting in ABBA order through
// the same Flutter video output and locked libmpv. Larger AO buffers simulate
// queued audio, not any particular Android device or audio driver.
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

  final experiment = Platform.environment['BILI_RATE_EXPERIMENT'] ?? 'buffer';
  final cases = switch (experiment) {
    'buffer' => [
      for (final buffer in [0.2, 0.05, 0.05, 0.2])
        (buffer: buffer, search: 40, autosync: 0),
    ],
    'search' => [
      for (final search in [40, 20, 20, 40])
        (buffer: 0.05, search: search, autosync: 0),
    ],
    'autosync' => [
      for (final buffer in [0.05, 0.15])
        for (final sync in [0, 30, 30, 0])
          (buffer: buffer, search: 40, autosync: sync),
    ],
    _ => throw StateError('Unknown rate experiment.'),
  };
  for (final config in cases) {
    final bufferSeconds = config.buffer;
    final player = await createNativePlayer();
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
      await player.setPropertyAsync(
        'af',
        'scaletempo2=search-interval=${config.search}',
      );
      await player.setPropertyAsync('audio-buffer', '$bufferSeconds');
      await player.setPropertyAsync('autosync', '${config.autosync}');
      player.setProperty(
        'audio-files',
        mpvPathListEntry(audio.uri, windows: Platform.isWindows),
      );
      await player.open(mk.Media(video.uri.toString()), play: false);
      await player.setVolume(0);
      await player.play();
      await output.firstFrameRendered.timeout(const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(seconds: 1));
      final run = <String, Object?>{
        'requestedBufferSeconds': bufferSeconds,
        'appliedBufferSeconds': player.getProperty('audio-buffer'),
        'tempoFilter': player.getProperty('af'),
        'searchIntervalMs': config.search,
        'autosync': player.getProperty('autosync'),
        'experiment': experiment,
        'audioOutput': player.getProperty('current-ao'),
        'pitchCorrection': player.getProperty('audio-pitch-correction'),
        'mpvVersion': player.getProperty('mpv-version'),
        'hardwareDecoder': player.getProperty('hwdec-current'),
        'videoSync': player.getProperty('video-sync'),
        'frameDropsBefore': player.getProperty('frame-drop-count'),
        'decoderDropsBefore': player.getProperty('decoder-frame-drop-count'),
      };
      final transitions = <Map<String, Object?>>[];
      for (final rate in [2.0, 1.0, 2.0, 1.0, 2.0, 1.0]) {
        // Count before the command: a native event may already drop frames
        // while the asynchronous setter is completing.
        final dropsBefore = int.parse(player.getProperty('frame-drop-count'));
        final clock = Stopwatch()..start();
        await player.setRate(rate);
        final commandUs = clock.elapsedMicroseconds;
        final points = <Map<String, Object?>>[];
        String? previousPosition;
        var lastChangeUs = 0;
        var maxGapUs = 0;
        var maxAvsync = 0.0;
        double? previousAudioPts;
        var minAudioStep = 0.0;
        var maxAudioStep = 0.0;
        var lastAvsync = 0.0;
        var lastLargeAvsyncUs = 0;
        while (clock.elapsed < const Duration(milliseconds: 750)) {
          final position = player.getProperty('time-pos');
          final avsync = double.tryParse(player.getProperty('avsync')) ?? 0;
          lastAvsync = avsync;
          if (avsync.abs() > 0.04) {
            lastLargeAvsyncUs = clock.elapsedMicroseconds;
          }
          final audioPts = double.tryParse(player.getProperty('audio-pts'));
          if (audioPts != null && previousAudioPts != null) {
            final step = audioPts - previousAudioPts;
            if (step < minAudioStep) minAudioStep = step;
            if (step > maxAudioStep) maxAudioStep = step;
          }
          previousAudioPts = audioPts;
          final nowUs = clock.elapsedMicroseconds;
          if (position != previousPosition) {
            final gap = nowUs - lastChangeUs;
            if (gap > maxGapUs) maxGapUs = gap;
            lastChangeUs = nowUs;
            previousPosition = position;
          }
          if (avsync.abs() > maxAvsync) maxAvsync = avsync.abs();
          points.add({
            'atUs': nowUs,
            'position': position,
            'audioPts': audioPts,
            'nativeRate': player.getProperty('speed'),
            'avsync': avsync,
          });
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        final tailGapUs = clock.elapsedMicroseconds - lastChangeUs;
        if (tailGapUs > maxGapUs) maxGapUs = tailGapUs;
        transitions.add({
          'rate': rate,
          'commandUs': commandUs,
          'maxPositionGapUs': maxGapUs,
          'maxAbsAvsyncSeconds': maxAvsync,
          'lastAvsyncSeconds': lastAvsync,
          'lastLargeAvsyncUs': lastLargeAvsyncUs,
          'minAudioStepSeconds': minAudioStep,
          'maxAudioStepSeconds': maxAudioStep,
          'frameDropsDelta':
              int.parse(player.getProperty('frame-drop-count')) - dropsBefore,
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
