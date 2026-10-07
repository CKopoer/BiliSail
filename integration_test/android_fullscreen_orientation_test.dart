import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/support/input_test_app.dart';
import '../test/support/video_card_fake_engine.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Android video and live fullscreen rotate with display dimensions',
    (tester) async {
      if (!Platform.isAndroid) return;
      final engine = _Engine();
      final window = WindowService();
      final session = PlaybackSession(
        engine: engine,
        repository: _Repository(),
        contentRepository: _ContentRepository(),
        progress: _Progress(),
        accountScope: () => 'guest',
      );
      addTearDown(session.close);
      addTearDown(() => window.setFullScreen(false));
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
      ]);
      for (final live in [false, true]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [playbackSessionProvider.overrideWithValue(session)],
            child: InputTestApp(
              home: Scaffold(
                body: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: PlaybackPanel(
                    detail: live ? null : _detail,
                    part: live ? null : _detail.parts.first,
                    target: live ? const LivePlaybackTarget('12') : null,
                    settings: const AppSettings.defaults(),
                    onToggleComments: () {},
                    window: window,
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        expect(session.isLive, live);
        final opens = engine.opens;
        final generation = engine.currentSnapshot.generation;
        engine.publish(
          engine.currentSnapshot.copyWith(
            videoDimensions: const VideoDimensions(1920, 1080),
          ),
        );
        await tester.tap(find.byTooltip('全屏（F）'));
        await _until(tester, () => window.isFullScreen && _isLandscape(tester));
        expect(find.byTooltip('退出全屏（Esc）'), findsOneWidget);
        engine.publish(
          engine.currentSnapshot.copyWith(
            videoDimensions: const VideoDimensions(1080, 1920),
          ),
        );
        await _until(tester, () => !_isLandscape(tester));
        await tester.tap(find.byTooltip('退出全屏（Esc）'));
        await _until(tester, () => !window.isFullScreen);
        // A portrait source also enters fullscreen without changing to landscape.
        await tester.tap(find.byTooltip('全屏（F）'));
        await _until(tester, () => window.isFullScreen);
        expect(_isLandscape(tester), isFalse);
        await tester.tap(find.byTooltip('退出全屏（Esc）'));
        await _until(tester, () => !window.isFullScreen);
        expect(engine.opens, opens);
        expect(engine.currentSnapshot.generation, generation);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 100));
      }
    },
  );
}

bool _isLandscape(WidgetTester tester) =>
    tester.view.physicalSize.width > tester.view.physicalSize.height;

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final watch = Stopwatch()..start();
  while (!ready() && watch.elapsed < const Duration(seconds: 15)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(ready(), isTrue);
  await tester.pump(const Duration(milliseconds: 100));
}

class _Engine extends CardFakeEngine {
  @override
  PlayerCapabilities get capabilities =>
      const PlayerCapabilities(externalAudio: true, externalAudioHeaders: true);
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
  @override
  Future<void> setRate(double rate) async =>
      publish(snapshot.copyWith(rate: rate));
  @override
  Future<void> setVolume(double volume) async =>
      publish(snapshot.copyWith(volume: volume));
}

class _Repository extends Fake implements PlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => [];
}

class _ContentRepository implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
}

class _Progress implements PlaybackProgressStore {
  @override
  Future<Duration> read(String scope, VideoId video, String cid) async =>
      Duration.zero;
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

const _detail = VideoDetail(
  summary: VideoSummary(
    id: VideoId('BV1abc123456'),
    title: '全屏方向测试',
    coverUrl: '',
    author: 'fixture',
    duration: Duration(seconds: 20),
  ),
  description: '',
  parts: [
    VideoPart(
      cid: '123',
      page: 1,
      title: 'fixture',
      duration: Duration(seconds: 20),
    ),
  ],
);
