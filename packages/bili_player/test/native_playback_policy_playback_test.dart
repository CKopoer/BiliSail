import 'dart:io';

import 'package:bili_player/src/media_kit_backend.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bili_player/src/playback_backend.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['BILI_TEST_NATIVE_MPV'];
  final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
  test(
    'source reuse and rate round trips keep the same native policy',
    () async {
      mk.MediaKit.ensureInitialized(libmpv: library);
      late mk.Player player;
      final backend = MediaKitBackend(
        snapshot: () =>
            const PlaybackSnapshot(phase: PlaybackPhase.idle, generation: 0),
        createPlayer: () async {
          player = await createNativePlayer();
          await player.setPropertyAsync('ao', 'null');
          return player;
        },
      );
      final audio = MediaTrack(
        uri: File('$directory/audio.m4a').uri,
        requestPolicy: MediaRequestPolicy(),
      );
      try {
        var generation = 0;
        int? handle;
        for (final live in [false, true, false]) {
          final operation = PlaybackOperation(
            ++generation,
            const Duration(seconds: 8),
          );
          if (generation > 1) await backend.resetForNextSource(operation);
          await backend.preparePaused(
            ValidatedSource.validate(
              ProgressiveSource(audio, isAudioOnly: true, isLive: live),
              const OpenOptions(play: false, volume: 0),
              generation,
            ),
            operation,
          );
          handle ??= player.nativeHandle;
          expect(player.nativeHandle, handle);
          expect(await player.getPropertyAsync('curl-enabled'), 'no');
          expect(
            await player.getPropertyAsync('stream-lavf-o'),
            'rw_timeout=5000000',
          );
          expect(
            await player.getPropertyAsync('video-sync'),
            'display-resample',
          );
          expect(
            await player.getPropertyAsync('autosync'),
            Platform.isAndroid ? '30' : '0',
          );
          expect(await player.getPropertyAsync('audio-buffer'), '0.200000');
          expect(await player.getPropertyAsync('hr-seek'), 'default');
          expect(await player.getPropertyAsync('hr-seek-framedrop'), 'yes');
          expect(await player.getPropertyAsync('af'), isEmpty);
          // Verify effective native defaults after SDK initialization and a
          // source change, not only values accepted by the Dart policy fake.
          expect(await player.getPropertyAsync('network-timeout'), '5.000000');
          expect(await player.getPropertyAsync('cache-pause'), 'yes');
          expect(await player.getPropertyAsync('cache-pause-initial'), 'no');
          expect(await player.getPropertyAsync('cache-pause-wait'), '1.000000');
          final demuxOptions = await player.getPropertyAsync('demuxer-lavf-o');
          expect(demuxOptions, contains('seg_max_retry=5'));
          await backend.play();
          await backend.confirmAudio(operation);
          for (final rate in live ? [1.0] : [2.0, 1.0, 3.0, 1.5]) {
            await backend.setRate(rate);
            expect(double.parse(await player.getPropertyAsync('speed')), rate);
            expect(
              await player.getPropertyAsync('audio-pitch-correction'),
              'yes',
            );
            expect(await player.getPropertyAsync('af'), isEmpty);
          }
        }
      } finally {
        await backend.dispose();
      }
    },
    skip: library == null || directory == null
        ? 'Set BILI_TEST_NATIVE_MPV and BILI_TEST_MEDIA_DIR'
        : false,
  );
}
