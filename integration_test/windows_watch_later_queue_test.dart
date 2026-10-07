import 'dart:io';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/theme.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_extras_repository.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized().framePolicy =
      LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets(
    'Windows watch-later queue preserves one native engine and intent',
    (tester) async {
      initializePlayerBackend();
      final mediaDirectory = Platform.environment['BILI_TEST_MEDIA_DIR'];
      expect(
        mediaDirectory,
        isNotNull,
        reason: 'Set BILI_TEST_MEDIA_DIR to the local media fixtures',
      );
      final engine = MediaKitEngine();
      final session = PlaybackSession(
        engine: engine,
        repository: _LocalPlaybackRepository(mediaDirectory ?? ''),
        progress: _ProgressStore(),
        accountScope: () => 'user:1',
      );
      final settings = AppSettings(
        autoPlay: false,
        resumePlayback: false,
        defaultVolume: 0,
      );
      final queue = WatchLaterQueue(
        id: 'native-fixture',
        scope: 'user:1',
        sessionEpoch: 0,
        items: [
          for (final detail in _details)
            WatchLaterQueueItem(video: detail.summary),
        ],
      );
      var selectedId = _details.first.summary.id;
      String? selectedCid;
      final visible = ValueNotifier(true);
      try {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              playbackSessionProvider.overrideWithValue(session),
              authControllerProvider.overrideWith(_FixtureAuth.new),
              videoRepositoryProvider.overrideWithValue(_VideoRepository()),
              videoExtrasRepositoryProvider.overrideWithValue(
                _ExtrasRepository(),
              ),
            ],
            child: MaterialApp(
              theme: BiliTheme.dark(),
              home: Scaffold(
                body: ValueListenableBuilder<bool>(
                  valueListenable: visible,
                  builder: (context, active, _) => Offstage(
                    offstage: !active,
                    child: WorkspaceActivity(
                      active: active,
                      child: StatefulBuilder(
                        builder: (context, update) => VideoScreen(
                          id: selectedId,
                          initialCid: selectedCid,
                          queue: queue,
                          onOpenQueueVideo: (id) => update(() {
                            selectedId = id;
                            selectedCid = null;
                          }),
                          onPartChanged: (part) =>
                              update(() => selectedCid = part.cid),
                          playerBuilder: (_, detail, part) => PlaybackPanel(
                            detail: detail,
                            part: part,
                            settings: settings,
                            onToggleComments: () {},
                            window: _FixtureWindow(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await _until(
          tester,
          () =>
              session.media != null &&
              engine.currentSnapshot.phase == PlaybackPhase.paused,
        );
        if (find.text('稍后再看').hitTestable().evaluate().isEmpty) {
          await tester.tap(find.byTooltip('展开视频信息'));
          await tester.pump();
        }
        await tester.tap(find.text(_details.last.summary.title).hitTestable());
        await _until(
          tester,
          () =>
              session.detail?.summary.id == _details.last.summary.id &&
              session.media != null &&
              engine.currentSnapshot.phase == PlaybackPhase.paused,
        );
        expect(session.engine, same(engine));
        final generation = session.sourceGeneration;
        await tester.tap(find.text('稍后再看'));
        await tester.pump();
        await tester.tap(find.text('稍后再看'));
        await tester.pump();
        expect(session.sourceGeneration, generation);
        expect(engine.currentSnapshot.phase, PlaybackPhase.paused);
        await tester.tap(find.text(_details.first.summary.title).hitTestable());
        await _until(
          tester,
          () =>
              session.detail?.summary.id == _details.first.summary.id &&
              session.part?.cid == 'native-a1' &&
              session.media != null &&
              engine.currentSnapshot.phase == PlaybackPhase.paused,
        );
        await session.togglePlaying();
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        await session.seek(const Duration(milliseconds: 11400));
        visible.value = false;
        await tester.pump();
        await _until(
          tester,
          () =>
              session.part?.cid == 'native-a2' &&
              session.media != null &&
              engine.currentSnapshot.phase == PlaybackPhase.playing,
          diagnostics: () =>
              'cid=${session.part?.cid}, phase=${engine.currentSnapshot.phase}, '
              'position=${engine.currentSnapshot.position}, '
              'duration=${engine.currentSnapshot.duration}, '
              'intent=${engine.currentSnapshot.desiredPlaying}, '
              'generation=${session.sourceGeneration}, error=${session.error}',
        );
        await session.seek(const Duration(milliseconds: 11400));
        await _until(
          tester,
          () =>
              session.detail?.summary.id == _details.last.summary.id &&
              session.media != null &&
              engine.currentSnapshot.phase == PlaybackPhase.playing,
        );
        expect(session.engine, same(engine));
        visible.value = true;
        await tester.pump();
        await session.seek(const Duration(milliseconds: 11400));
        await _until(
          tester,
          () => engine.currentSnapshot.phase == PlaybackPhase.ended,
        );
        expect(engine.currentSnapshot.isBuffering, isFalse);
        expect(engine.currentSnapshot.isSeeking, isFalse);
        expect(find.text('正在准备音视频…'), findsNothing);
        // Late native playing/buffering notifications must not hide EOF.
        await tester.pump(const Duration(seconds: 1));
        expect(engine.currentSnapshot.phase, PlaybackPhase.ended);
        expect(engine.currentSnapshot.isBuffering, isFalse);
        expect(engine.currentSnapshot.isSeeking, isFalse);
        expect(find.text('正在准备音视频…'), findsNothing);
        expect(session.detail?.summary.id, _details.last.summary.id);
        final lastGeneration = session.sourceGeneration;
        await session.togglePlaying();
        await _until(
          tester,
          () =>
              engine.currentSnapshot.phase == PlaybackPhase.playing &&
              engine.currentSnapshot.position < const Duration(seconds: 2),
        );
        expect(session.sourceGeneration, lastGeneration);
        expect(engine.currentSnapshot.isBuffering, isFalse);
        expect(engine.currentSnapshot.isSeeking, isFalse);
        expect(find.text('正在准备音视频…'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        visible.dispose();
        await session.close();
      }
    },
  );
}

final _details = [
  for (final (id, title, cids) in [
    ('BV1abc123456', '本地队列视频 A', ['native-a1', 'native-a2']),
    ('BV2abc123456', '本地队列视频 B', ['native-b1']),
  ])
    VideoDetail(
      summary: VideoSummary(
        id: VideoId(id),
        title: title,
        coverUrl: '',
        author: '本地测试',
        duration: const Duration(seconds: 12),
      ),
      description: '',
      parts: [
        for (var index = 0; index < cids.length; index++)
          VideoPart(
            cid: cids[index],
            page: index + 1,
            title: '第 ${index + 1} P',
            duration: const Duration(seconds: 12),
          ),
      ],
    ),
];

class _FixtureAuth extends AuthController {
  @override
  AuthState build() => const AuthState(status: AuthStatus.signedIn, mid: '1');
}

class _FixtureWindow extends WindowService {
  @override
  bool get hasCustomTitleBar => false;
}

class _VideoRepository implements VideoRepository {
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    // Exercise the real route's detail-loading gap between native owners.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    return _details.firstWhere((detail) => detail.summary.id == id);
  }
}

class _ExtrasRepository implements VideoExtrasRepository {
  @override
  Future<List<String>> loadTags(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<List<VideoSummary>> loadRelated(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<VideoCommentsPage> loadComments(
    VideoId id, {
    required int page,
    required RequestCancellation cancellation,
  }) async => const VideoCommentsPage(comments: [], hasMore: false);
}

class _LocalPlaybackRepository implements PlaybackRepository {
  const _LocalPlaybackRepository(this.directory);
  final String directory;
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => PlaybackMedia(
    video: PlaybackTrack(
      urls: [File('$directory/video.mp4').uri],
      codec: 'avc1',
      bandwidth: 1000000,
    ),
    audio: PlaybackTrack(
      urls: [File('$directory/audio.m4a').uri],
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
  }) async => const [];
  @override
  Future<List<SubtitleTrack>> subtitles(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) async => const [];
  @override
  Future<List<SubtitleCue>> subtitleCues(
    SubtitleTrack track, {
    required RequestCancellation cancellation,
  }) async => const [];
}

class _ProgressStore implements PlaybackProgressStore {
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

Future<void> _until(
  WidgetTester tester,
  bool Function() condition, {
  String Function()? diagnostics,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 25));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    condition(),
    isTrue,
    reason:
        'The watch-later native playback transition did not complete. '
        '${diagnostics?.call() ?? ''}',
  );
}
