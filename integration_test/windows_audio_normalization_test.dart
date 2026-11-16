import 'dart:io';

import 'package:bilisail/domain/audio_normalization.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bili_player/bili_player.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  for (final pgc in [false, true]) {
    testWidgets('native normalization preserves DASH playback: PGC=$pgc', (
      tester,
    ) async {
      final path = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(
        path,
        isNotNull,
        reason: 'Set BILI_TEST_MEDIA_DIR to test/fixtures/media.',
      );
      final engine = MediaKitEngine();
      final fixture = _Fixture(path ?? '');
      final session = PlaybackSession(
        engine: engine,
        repository: _Video(fixture),
        contentRepository: _Content(fixture),
        progress: _Progress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      var settings = AppSettings(
        audioNormalization: AudioNormalizationMode.standard,
        autoPlay: false,
      );
      session.configureSettings(settings);
      Future<void> open(String id) => pgc
          ? session.open(
              null,
              null,
              target: PgcPlaybackTarget(id),
              desiredPlaying: false,
            )
          : session.open(
              VideoDetail(
                summary: const VideoSummary(
                  id: VideoId('BV1GJ411x7h7'),
                  title: 'fixture',
                  coverUrl: '',
                  author: 'fixture',
                  duration: Duration(seconds: 12),
                ),
                description: '',
                parts: [
                  VideoPart(
                    cid: id,
                    page: 1,
                    title: 'fixture',
                    duration: const Duration(seconds: 12),
                  ),
                ],
              ),
              VideoPart(
                cid: id,
                page: 1,
                title: 'fixture',
                duration: const Duration(seconds: 12),
              ),
              desiredPlaying: false,
            );
      await open('1');
      expect(session.error, isNull);
      expect(engine.appliedAudioGainDb, closeTo(2.7, .00001));
      await session.setVolume(35);
      await session.setRate(1.25);
      await session.togglePlaying();
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      while (!engine.inspectDiagnostics().hasDecodedAudio &&
          DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
      expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
      await session.pause();
      await session.seek(const Duration(seconds: 3));
      final generation = engine.currentSnapshot.generation;
      for (final mode in [
        AudioNormalizationMode.highDynamic,
        AudioNormalizationMode.off,
        AudioNormalizationMode.standard,
      ]) {
        settings = settings.copyWith(audioNormalization: mode);
        session.configureSettings(settings);
        final expected = fixture.loudness?.gainDb(mode) ?? 0;
        final until = DateTime.now().add(const Duration(seconds: 3));
        while ((engine.appliedAudioGainDb - expected).abs() > .00001 &&
            DateTime.now().isBefore(until)) {
          await tester.pump(const Duration(milliseconds: 20));
        }
        expect(engine.appliedAudioGainDb, closeTo(expected, .00001));
        expect(session.error, isNull);
        expect(engine.currentSnapshot.generation, generation);
        expect(engine.currentSnapshot.volume, 35);
        expect(engine.currentSnapshot.rate, 1.25);
        expect(engine.currentSnapshot.desiredPlaying, isFalse);
        expect(
          (engine.currentSnapshot.position.inMilliseconds - 3000).abs(),
          lessThan(300),
        );
      }
      await session.changeQuality(64);
      expect(engine.appliedAudioGainDb, closeTo(2.7, .00001));
      expect(engine.currentSnapshot.volume, 35);
      fixture.loudness = null;
      await open('2');
      expect(engine.appliedAudioGainDb, 0);
      expect(session.error, isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}

class _Fixture {
  _Fixture(this.path);
  final String path;
  AudioLoudness? loudness = const AudioLoudness(
    measuredI: -16.7,
    normalTargetI: -14,
    highDynamicTargetI: -24,
    undersizedTargetI: -28,
  );
  PlaybackMedia media(int quality) => PlaybackMedia(
    video: PlaybackTrack(
      urls: [File('$path/video.mp4').uri],
      codec: 'avc1',
      bandwidth: 1000,
    ),
    audio: PlaybackTrack(
      urls: [File('$path/audio.m4a').uri],
      codec: 'mp4a.40.2',
      bandwidth: 128,
    ),
    quality: quality,
    qualities: const [80, 64],
    duration: const Duration(seconds: 12),
    headers: const {},
    loudness: loudness,
  );
}

class _Video implements PlaybackRepository {
  _Video(this.fixture);
  final _Fixture fixture;
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => fixture.media(quality);
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => const [];
}

class _Content implements ContentPlaybackRepository {
  _Content(this.fixture);
  final _Fixture fixture;
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => fixture.media(quality);
}

class _Progress implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async => null;
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) async {}
}
