import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/audio_quality.dart';
import 'package:bilisail/features/playback/data/dash_media_selection.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  testWidgets('native DASH audio follows AAC, FLAC and Dolby preferences', (
    tester,
  ) async {
    initializePlayerBackend();
    final directory = Platform.environment['BILI_CONTENT_MEDIA_DIR'];
    expect(directory, isNotNull, reason: 'Use tool/test-windows-content.ps1');
    ApiMediaTrack track(int id, String codec, String name) => ApiMediaTrack(
      id: id,
      url: File('$directory/$name').uri,
      backupUrls: const [],
      bandwidth: 192000,
      mimeType: id == 80 ? 'video/mp4' : 'audio/mp4',
      codecs: codec,
    );
    final info = ApiPlayInfo(
      duration: const Duration(seconds: 12),
      dashVideo: [track(80, 'avc1.640028', 'video.mp4')],
      dashAudio: [
        track(30280, 'mp4a.40.2', 'audio.m4a'),
        track(30251, 'fLaC', 'audio-flac.m4a'),
        track(30250, 'ec-3', 'audio-dolby.m4a'),
      ],
      acceptQuality: const [80],
    );
    final engine = MediaKitEngine();
    final failures = <PlayerFailure>[];
    final subscription = engine.failures.listen(failures.add);
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      for (final preference in [
        AudioQualityPreference.aac192,
        AudioQualityPreference.lossless,
        AudioQualityPreference.dolby,
      ]) {
        final media = selectDashMedia(
          info,
          quality: 80,
          preferredCodec: VideoCodecPreference.h264,
          audioQuality: preference,
          headers: const {},
        );
        final policy = MediaRequestPolicy();
        final audio = media.audio;
        if (audio == null) {
          fail('The selected DASH source needs companion audio');
        }
        await engine.open(
          DashPairSource(
            video: MediaTrack(
              uri: media.video.urls.first,
              requestPolicy: policy,
              codec: media.video.codec,
            ),
            audio: MediaTrack(
              uri: audio.urls.first,
              requestPolicy: policy,
              codec: audio.codec,
            ),
          ),
          const OpenOptions(play: true, volume: 0),
        );
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (DateTime.now().isBefore(deadline)) {
          final diagnostics = engine.inspectDiagnostics();
          if (diagnostics.hasDecodedAudio &&
              diagnostics.hasDecodedVideo &&
              engine.currentSnapshot.position >
                  const Duration(milliseconds: 200)) {
            break;
          }
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(
          engine.inspectDiagnostics().hasDecodedAudio,
          isTrue,
          reason: preference.name,
        );
        expect(
          engine.inspectDiagnostics().hasDecodedVideo,
          isTrue,
          reason: preference.name,
        );
        // The video fixture has no audio; decoded audio must come from this
        // selected external track. The backend may omit its codec label.
        expect(audio.urls.first.pathSegments.last, switch (preference) {
          AudioQualityPreference.lossless => 'audio-flac.m4a',
          AudioQualityPreference.dolby => 'audio-dolby.m4a',
          _ => 'audio.m4a',
        });
        expect(
          engine.currentSnapshot.position,
          greaterThan(const Duration(milliseconds: 200)),
        );
        expect(failures, isEmpty);
        await engine.stop();
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      await subscription.cancel();
      await engine.dispose();
    }
  });
}
