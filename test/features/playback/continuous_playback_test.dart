import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_playback_sequence.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_screen.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/domain/video_playback_sequence.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/features/video/presentation/video_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/video_card_fake_engine.dart';

const _a = VideoId('BV1234567890'), _b = VideoId('BV1234567891');
const _parts = [
  VideoPart(cid: '101', page: 1, title: 'P1', duration: Duration(seconds: 20)),
  VideoPart(cid: '102', page: 2, title: 'P2', duration: Duration(seconds: 20)),
];
const _third = VideoPart(
  cid: '103',
  page: 1,
  title: 'B1',
  duration: Duration(seconds: 20),
);
const _collection = VideoCollection(
  id: '1',
  title: '测试合集',
  entries: [
    VideoCollectionEntry(id: _a, title: 'A', parts: _parts),
    VideoCollectionEntry(id: _b, title: 'B', parts: [_third]),
  ],
);
VideoDetail _video(VideoId id, List<VideoPart> parts) => VideoDetail(
  summary: VideoSummary(
    id: id,
    title: id == _a ? '视频 A' : '视频 B',
    coverUrl: '',
    author: 'UP',
    duration: const Duration(seconds: 20),
  ),
  description: '',
  parts: parts,
  collection: _collection,
);
const _episodes = [
  PgcEpisode(
    id: PgcEpisodeId('1'),
    title: '1',
    bvid: 'BV1234567890',
    cid: '101',
  ),
  PgcEpisode(
    id: PgcEpisodeId('2'),
    title: '2',
    bvid: 'BV1234567890',
    cid: '102',
  ),
  PgcEpisode(
    id: PgcEpisodeId('3'),
    title: 'SP',
    bvid: 'BV1234567891',
    cid: '103',
    sectionTitle: 'SP',
  ),
];
final _season = PgcSeason(
  id: const PgcSeasonId('1'),
  title: '影视',
  episodes: _episodes,
);

void main() {
  test(
    'video order prioritizes parts, then collection or originating queue',
    () {
      final a = _video(_a, _parts), b = _video(_b, [_third]);
      expect(adjacentVideoSource(a, '101', 1), (id: _a, cid: '102'));
      expect(adjacentVideoSource(a, '102', 1), (id: _b, cid: '103'));
      expect(adjacentVideoSource(b, '103', 1), isNull);
      expect(adjacentVideoSource(a, 'missing', 1), isNull);
      final queue = WatchLaterQueue(
        id: '1',
        scope: 'guest',
        sessionEpoch: 0,
        items: [
          WatchLaterQueueItem(video: b.summary),
          WatchLaterQueueItem(video: a.summary),
        ],
      );
      expect(adjacentVideoSource(a, '102', 1, queue: queue), isNull);
      expect(adjacentVideoSource(b, '103', 1, queue: queue), (
        id: _a,
        cid: null,
      ));
    },
  );

  test(
    'PGC stays within the current section and stops at unavailable episodes',
    () {
      expect(adjacentPgcEpisode(_season, _episodes[0], 1), _episodes[1]);
      expect(adjacentPgcEpisode(_season, _episodes[1], 1), isNull);
      expect(adjacentPgcEpisode(_season, _episodes[2], 1), isNull);
      final restricted = PgcSeason(
        id: _season.id,
        title: '',
        episodes: [
          _episodes[0],
          const PgcEpisode(id: PgcEpisodeId('4'), title: '4', available: false),
          _episodes[1],
        ],
      );
      expect(adjacentPgcEpisode(restricted, _episodes[0], 1), isNull);
    },
  );

  for (final width in [390.0, 1400.0]) {
    for (final fullscreen in [false, true]) {
      testWidgets(
        'manual and continuous parts and collection width=$width fullscreen=$fullscreen',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 900);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final engine = _Engine();
          final session = _session(engine);
          addTearDown(session.close);
          final settings = ValueNotifier(
            AppSettings(continuousPlayback: false, danmakuEnabled: false),
          );
          addTearDown(settings.dispose);
          var id = _a;
          String? cid;
          final window = _Window();
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                playbackSessionProvider.overrideWithValue(session),
                authControllerProvider.overrideWith(_Auth.new),
                for (final video in [
                  _video(_a, _parts),
                  _video(_b, [_third]),
                ]) ...[
                  videoDetailProvider(video.summary.id).overrideWith((_) async {
                    if (video.summary.id == _b) {
                      await Future<void>.delayed(
                        const Duration(milliseconds: 50),
                      );
                    }
                    return video;
                  }),
                  relatedVideosProvider(video.summary.id)
                      .overrideWith((_) => const []),
                  videoTagsProvider(video.summary.id)
                      .overrideWith((_) => const []),
                ],
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: ValueListenableBuilder(
                    valueListenable: settings,
                    builder: (_, value, _) => StatefulBuilder(
                      builder: (_, update) => VideoScreen(
                        id: id,
                        initialCid: cid,
                        onPartChanged: (part) => update(() => cid = part.cid),
                        onAdvanceVideo: (next, nextCid) => update(() {
                          id = next;
                          cid = nextCid;
                        }),
                        playerBuilder: (_, detail, part) => PlaybackPanel(
                          detail: detail,
                          part: part,
                          settings: value,
                          onToggleComments: () {},
                          window: window,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await _frames(tester);
          if (fullscreen) {
            await tester.tap(find.byTooltip('全屏（F）'));
            await _frames(tester);
          }
          engine.end();
          await _frames(tester);
          expect(session.part?.cid, '101');
          expect(engine.opens, 1);
          final next = find.byKey(const ValueKey('player-next-episode'));
          expect(next, findsOneWidget);
          expect(tester.widget<IconButton>(next).onPressed, isNotNull);
          await tester.tap(next);
          await _frames(tester);
          expect(session.part?.cid, '102');
          expect(session.snapshots.value.desiredPlaying, isTrue);
          settings.value = settings.value.copyWith(continuousPlayback: true);
          await _frames(tester);
          engine.end();
          engine.end();
          await _frames(tester);
          expect(session.detail?.summary.id, _b);
          expect(session.part?.cid, '103');
          expect(engine.opens, 3);
          expect(engine.options?.startPosition, Duration.zero);
          expect(session.snapshots.value.desiredPlaying, isTrue);
          expect(window.fullscreen, fullscreen);
          expect(tester.widget<IconButton>(next).onPressed, isNull);
          engine.end();
          await _frames(tester);
          expect(engine.opens, 3);
          expect(session.snapshots.value.phase, PlaybackPhase.ended);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await _frames(tester);
        },
      );
    }
  }

  testWidgets(
    'hidden PGC page continues once and starts next episode at zero',
    (tester) async {
      final engine = _Engine();
      final session = _session(engine);
      addTearDown(session.close);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            playbackSessionProvider.overrideWithValue(session),
            authControllerProvider.overrideWith(_Auth.new),
            pgcRepositoryProvider.overrideWithValue(_PgcRepo()),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: visible,
                builder: (_, active, _) => Offstage(
                  offstage: !active,
                  child: WorkspaceActivity(
                    active: active,
                    child: PgcScreen(
                      seasonId: '1',
                      playerBuilder: (_, season, episode) {
                        final part = _parts.firstWhere(
                          (part) => part.cid == episode.cid,
                        );
                        return PlaybackPanel(
                          detail: _video(_a, [part]),
                          part: part,
                          target: PgcPlaybackTarget(
                            episode.episodeId,
                            cid: episode.cid,
                          ),
                          settings: AppSettings(
                            continuousPlayback: true,
                            danmakuEnabled: false,
                          ),
                          onToggleComments: () {},
                          window: _Window(),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await _frames(tester);
      expect(session.contentTarget, const PgcPlaybackTarget('1', cid: '101'));
      visible.value = false;
      await _frames(tester);
      engine.end();
      engine.end();
      await _frames(tester);
      expect(session.contentTarget, const PgcPlaybackTarget('2', cid: '102'));
      expect(engine.options?.startPosition, Duration.zero);
      expect(session.snapshots.value.desiredPlaying, isTrue);
      engine.end();
      await _frames(tester);
      expect(engine.opens, 2);
      await tester.pumpWidget(const SizedBox());
      await _frames(tester);
    },
  );

  test(
    'next source rejects account epoch changes and preserves manual pause',
    () async {
      var epoch = 0;
      final engine = _Engine();
      final session = _session(engine, epoch: () => epoch);
      final owner = Object();
      session.attach(owner);
      session.configureSettings(AppSettings(autoPlay: false));
      final video = _video(_a, _parts);
      await session.activate(owner, video, _parts[0]);
      expect(
        session.prepareNextVideo(_a, '101', nextId: _a, nextCid: '102'),
        isTrue,
      );
      await session.activate(owner, video, _parts[1]);
      expect(engine.options?.play, isFalse);
      engine.end();
      epoch++;
      expect(
        session.prepareNextVideo(_a, '102', nextId: _b, completed: true),
        isFalse,
      );
      await session.close();
    },
  );
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

PlaybackSession _session(_Engine engine, {int Function()? epoch}) =>
    PlaybackSession(
      engine: engine,
      repository: _PlaybackRepo(),
      contentRepository: _ContentRepo(),
      progress: _Progress(),
      accountScope: () => 'guest',
      sessionEpoch: epoch,
    );

class _Engine extends CardFakeEngine {
  void end() => publish(
    snapshot.copyWith(
      phase: PlaybackPhase.ended,
      position: const Duration(seconds: 20),
      desiredPlaying: false,
    ),
  );
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
  @override
  Future<void> setRate(double value) async =>
      publish(snapshot.copyWith(rate: value));
  @override
  Future<void> setVolume(double value) async =>
      publish(snapshot.copyWith(volume: value));
}

class _PlaybackRepo extends Fake implements PlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
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

class _ContentRepo extends Fake implements ContentPlaybackRepository {
  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) async => cardPreviewMedia();
}

class _Progress extends Fake implements PlaybackProgressStore {
  @override
  Future<Duration?> read(String scope, VideoId video, String cid) async =>
      const Duration(seconds: 8);
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

class _Window extends WindowService {
  bool fullscreen = false;
  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    fullscreen = value;
  }
}

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _PgcRepo extends Fake implements PgcRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    required RequestCancellation cancellation,
  }) async => _season;
}
