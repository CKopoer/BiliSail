import 'dart:io';

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  for (final online in [false, true]) {
    testWidgets(
      'media_kit silent video opens, advances and seeks online=$online',
      (tester) async {
        initializePlayerBackend();
        final PlayerEngine engine = MediaKitEngine();
        final requests = ApiRequests();
        final api = BiliApiClient(sessionProvider: requests);
        final session = PlaybackSession(
          engine: engine,
          repository: online
              ? ApiPlaybackRepository(api, requests)
              : _Repository(
                  File(
                    '${Platform.environment['BILI_TEST_MEDIA_DIR']}/video.mp4',
                  ).uri,
                ),
          progress: _Progress(),
          accountScope: () => 'guest',
        );
        session.configureSettings(
          AppSettings(
            autoPlay: true,
            resumePlayback: false,
            danmakuEnabled: false,
            subtitlesEnabled: false,
          ),
        );
        try {
          await tester.pumpWidget(
            MaterialApp(home: VideoSurface(engine: engine)),
          );
          await _withFrames(tester, session.open(_detail, _part, volume: 3));
          expect(session.error, isNull);
          expect(session.media?.isIntentionallySilent, isTrue);
          expect(session.media?.audio, isNull);
          expect(session.canListen, isFalse);
          final initial = engine.currentSnapshot.position;
          await tester.pump(const Duration(milliseconds: 750));
          expect(engine.currentSnapshot.position, greaterThan(initial));
          final information = await (engine as PlayerInformationSource)
              .inspectPlaybackInformation();
          expect(information?.diagnostics?.hasDecodedVideo, isTrue);
          expect(information?.diagnostics?.hasDecodedAudio, isFalse);
          expect(information?.diagnostics?.hasVideoOutput, isTrue);
          await _withFrames(tester, session.pause());
          await _withFrames(tester, session.seek(const Duration(seconds: 2)));
          expect(session.error, isNull);
          expect(engine.currentSnapshot.desiredPlaying, isFalse);
          expect(
            (engine.currentSnapshot.position - const Duration(seconds: 2))
                .abs(),
            lessThan(const Duration(milliseconds: 400)),
          );
          await _withFrames(tester, session.play());
          await tester.pump(const Duration(milliseconds: 500));
          expect(
            engine.currentSnapshot.position,
            greaterThan(const Duration(seconds: 2)),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await _withFrames(tester, session.close());
          api.close();
        }
      },
      skip: online && !const bool.fromEnvironment('BILI_ONLINE_SMOKE'),
    );
  }
}

const _part = VideoPart(
  cid: '43074848375',
  page: 1,
  title: 'Silent video',
  duration: Duration(seconds: 231),
);
const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1fTnZ6LEvr'),
    title: 'Silent video',
    coverUrl: '',
    author: 'fixture',
    duration: Duration(seconds: 231),
  ),
  description: '',
  parts: [_part],
);

class _Repository extends Fake implements PlaybackRepository {
  _Repository(this.uri);
  final Uri uri;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(urls: [uri], codec: 'avc1', bandwidth: 1000),
    audio: null,
    isIntentionallySilent: true,
    quality: 80,
    qualities: const [80],
    duration: const Duration(seconds: 6),
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

Future<void> _withFrames(WidgetTester tester, Future<void> operation) async {
  var done = false;
  Object? failure;
  final completion = operation.then<void>(
    (_) => done = true,
    onError: (Object error, StackTrace stack) {
      failure = error;
      done = true;
    },
  );
  final watch = Stopwatch()..start();
  while (!done && watch.elapsed < const Duration(seconds: 50)) {
    await tester.pump(const Duration(milliseconds: 16));
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done, isTrue, reason: 'Native operation timed out');
  await completion;
  if (failure case final error?) throw error;
}
