import 'dart:io';

import 'package:bili_player/src/media_kit_backend.dart';
import 'package:bili_player/src/native_media_options.dart';
import 'package:bili_player/src/native_player_properties.dart';
import 'package:bili_player/src/native_rate_audio.dart';
import 'package:bili_player/src/playback_backend.dart';
import 'package:bili_player/src/player_contract.dart';
import 'package:bili_player/src/validated_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart' as mk;

// Opt-in real SDK/libmpv regression. Null outputs exercise decoding and native
// rate/filter state; they cannot establish real-device frame pacing or audio.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final library = Platform.environment['BILI_TEST_NATIVE_MPV'];
  final directory = Platform.environment['BILI_TEST_MEDIA_DIR'];
  final skip = library == null || directory == null
      ? 'Set BILI_TEST_NATIVE_MPV and BILI_TEST_MEDIA_DIR for native rate validation'
      : false;
  test(
    'production backend applies and restores rate policy across source reuse',
    () async {
      mk.MediaKit.ensureInitialized(libmpv: library);
      late mk.Player player;
      var allocations = 0;
      final defaults = <String, String>{};
      final backend = MediaKitBackend(
        snapshot: () =>
            const PlaybackSnapshot(phase: PlaybackPhase.idle, generation: 0),
        createPlayer: () async {
          allocations++;
          player = await createNativePlayer();
          await player.setPropertyAsync('ao', 'null');
          for (final key in ['audio-buffer', 'af', 'autosync', 'video-sync']) {
            defaults[key] = await player.getPropertyAsync(key);
          }
          return player;
        },
      );
      final audio = MediaTrack(
        uri: File('$directory/audio.m4a').uri,
        requestPolicy: MediaRequestPolicy(),
      );
      try {
        var generation = 0;
        for (final live in [false, false, true, false]) {
          final operation = PlaybackOperation(
            ++generation,
            const Duration(seconds: 8),
          );
          final plan = ValidatedSource.validate(
            ProgressiveSource(audio, isAudioOnly: true, isLive: live),
            const OpenOptions(play: false, volume: 0),
            generation,
          );
          if (generation > 1) {
            expect(backend.canReuse(plan), true);
            await backend.resetForNextSource(operation);
          }
          final tracks = await backend.preparePaused(plan, operation);
          expect(tracks.hasAudio, true);
          expect(tracks.hasVideo, false);
          expect(allocations, 1);
          expect(await player.getPropertyAsync('pause'), 'yes');
          if (live) {
            for (final entry in defaults.entries) {
              expect(await player.getPropertyAsync(entry.key), entry.value);
            }
          } else {
            expect(
              double.parse(await player.getPropertyAsync('audio-buffer')),
              0.05,
            );
            expect(await player.getPropertyAsync('af'), 'scaletempo2');
            expect(await player.getPropertyAsync('autosync'), '30');
            expect(await player.getPropertyAsync('video-sync'), 'audio');
          }
          await backend.play();
          await backend.confirmAudio(operation);
          for (final rate in live ? [1.0] : [2.0, 1.0, 3.0, 1.5]) {
            await backend.setRate(rate);
            expect(double.parse(await player.getPropertyAsync('speed')), rate);
          }
          expect(await player.getPropertyAsync('pause'), 'no');
        }
      } finally {
        await backend.dispose();
      }
    },
    skip: skip,
  );
  test('EDL rate round trips keep filters and restore policy across player reuse', () async {
    mk.MediaKit.ensureInitialized(libmpv: library);
    final player = await createNativePlayer();
    final policy = NativeRateAudio(
      write: player.setPropertyAsync,
      read: player.getPropertyAsync,
    );
    final defaults = <String, String>{};
    for (final key in ['audio-buffer', 'af', 'autosync', 'video-sync']) {
      defaults[key] = await player.getPropertyAsync(key);
    }
    Future<void> configure(bool enabled) => policy.configure(
      enabled: enabled,
      isCurrent: () => true,
      timeout: const Duration(seconds: 3),
    );
    Future<void> waitFor(bool Function() ready) async {
      final watch = Stopwatch()..start();
      while (!ready()) {
        if (watch.elapsed > const Duration(seconds: 8)) {
          fail('Native audio/video playback did not become ready.');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }

    try {
      await player.setPropertyAsync('vo', 'null');
      await player.setPropertyAsync('ao', 'null');
      // The SDK disables video until a video controller selects an output.
      await player.setPropertyAsync('vid', 'auto');
      await player.setVolume(0);
      final handle = player.nativeHandle;
      final uri = nativeMediaUri(
        File('$directory/video.mp4').uri,
        File('$directory/audio.m4a').uri,
      );
      // VOD -> VOD -> live/silent policy -> VOD, using the same native player.
      for (final responsive in [true, true, false, true]) {
        await configure(responsive);
        expect(player.nativeHandle, handle);
        if (!responsive) {
          for (final entry in defaults.entries) {
            expect(await player.getPropertyAsync(entry.key), entry.value);
          }
        } else {
          expect(
            double.parse(await player.getPropertyAsync('audio-buffer')),
            0.05,
          );
          expect(await player.getPropertyAsync('af'), 'scaletempo2');
          expect(await player.getPropertyAsync('autosync'), '30');
          expect(await player.getPropertyAsync('video-sync'), 'audio');
        }
        await player.open(mk.Media(uri), play: false);
        await waitFor(
          () => player.state.tracks.audio.any(
            (track) => track.id != 'no' && track.id != 'auto',
          ),
        );
        await player.play();
        await waitFor(
          () => player.state.position > const Duration(milliseconds: 100),
        );
        final generationStart = player.state.position;
        for (final rate in [2.0, 1.0, 3.0, 1.5, 1.0]) {
          await player.setRate(rate);
          expect(double.parse(await player.getPropertyAsync('speed')), rate);
          if (responsive) {
            expect(await player.getPropertyAsync('af'), 'scaletempo2');
            expect(await player.getPropertyAsync('autosync'), '30');
          }
          expect(await player.getPropertyAsync('pause'), 'no');
          expect(
            await player.getPropertyAsync('audio-pitch-correction'),
            'yes',
          );
          expect(player.nativeHandle, handle);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        await waitFor(() => player.state.position > generationStart);
        expect(player.state.audioParams.channelCount, greaterThan(0));
        expect(player.state.videoParams.w, greaterThan(0));
        expect(player.state.volume, 0);
        await player.stop();
      }
    } finally {
      await player.dispose();
    }
  }, skip: skip);
}
