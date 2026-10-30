import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('native EOF can replay the same DASH source from zero', (
    tester,
  ) async {
    initializePlayerBackend();
    final fixtures = Platform.environment['BILI_TEST_MEDIA_DIR'];
    expect(fixtures, isNotNull, reason: 'Use tool/test-windows-media.ps1');
    final engine = MediaKitEngine();
    final session = PlaybackSession(
      engine: engine,
      repository: _Repository(fixtures!),
      progress: _Progress(),
      accountScope: () => 'guest',
    );
    session.configureSettings(AppSettings(resumePlayback: false));
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: VideoSurface(engine: engine)),
        ),
      );
      await session.open(_detail, _part, volume: 0);
      await _until(
        tester,
        () => engine.currentSnapshot.phase == PlaybackPhase.ended,
      );
      final generation = engine.currentSnapshot.generation;
      await session.togglePlaying();
      expect(session.error, isNull);
      await _until(
        tester,
        () =>
            engine.currentSnapshot.phase == PlaybackPhase.playing &&
            engine.currentSnapshot.position >
                const Duration(milliseconds: 250) &&
            engine.currentSnapshot.position < const Duration(seconds: 3),
      );
      expect(engine.currentSnapshot.generation, generation);
      expect(engine.inspectDiagnostics().hasDecodedVideo, isTrue);
      expect(engine.inspectDiagnostics().hasDecodedAudio, isTrue);
      await session.pause();
      final paused = engine.currentSnapshot.position;
      await session.togglePlaying();
      await _until(tester, () => engine.currentSnapshot.position > paused);
      expect(engine.currentSnapshot.generation, generation);
      expect(session.error, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await session.close();
    }
  });
}

const _part = VideoPart(
  cid: 'replay',
  page: 1,
  title: 'Replay fixture',
  duration: Duration(seconds: 12),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: 'Replay fixture',
    coverUrl: '',
    author: 'fixture',
    duration: Duration(seconds: 12),
  ),
  description: '',
  parts: [_part],
);

class _Repository extends Fake implements PlaybackRepository {
  _Repository(this.fixtures);
  final String fixtures;

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [File('$fixtures/video.mp4').uri],
      codec: 'avc1',
      bandwidth: 1000000,
    ),
    audio: PlaybackTrack(
      urls: [File('$fixtures/audio.m4a').uri],
      codec: 'mp4a',
      bandwidth: 64000,
    ),
    quality: 80,
    qualities: const [80],
    duration: const Duration(seconds: 12),
    headers: const {},
  );

  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [];

  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
}

class _Progress extends Fake implements PlaybackProgressStore {
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

Future<void> _until(WidgetTester tester, bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 20));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    condition(),
    isTrue,
    reason: 'Native replay did not reach the expected state',
  );
}
