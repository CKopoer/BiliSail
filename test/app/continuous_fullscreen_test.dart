import 'dart:async';

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/app/router.dart';
import 'package:bilisail/app/shell.dart';
import 'package:bilisail/core/platform/window_service.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/application/home_repository_provider.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/pgc/application/pgc_controller.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/application/settings_controller.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/features/settings/domain/settings_repository.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/application/video_extras_controller.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/features/video/domain/watch_later_queue.dart';
import 'package:bilisail/shared/ui/bili_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import '../support/input_test_app.dart';
import '../support/video_card_fake_engine.dart';

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

void main() {
  for (final mode in WorkspaceNavigationMode.values) {
    for (final historicalTarget in [false, true]) {
      testWidgets(
        'Android advancement retains history and rejects stale navigation $mode historicalTarget=$historicalTarget',
        (tester) async {
          final navigation = <String, ValueChanged<Uri>>{};
          final router = GoRouter(
            initialLocation: '/video/A',
            routes: [
              ShellRoute(
                builder: (context, state, child) => BiliAppShell(
                  location: state.uri.toString(),
                  navigationMode: mode,
                  pageBuilder: (context, tab) {
                    navigation[tab.location.path] =
                        WorkspacePageNavigation.maybeOf(context)!.navigate;
                    return tab.isPlayback
                        ? const _HistoryPage()
                        : const SizedBox();
                  },
                  child: child,
                ),
                routes: [
                  GoRoute(path: '/', builder: (_, _) => const SizedBox()),
                  GoRoute(
                    path: '/video/:id',
                    builder: (_, _) => const SizedBox(),
                  ),
                ],
              ),
            ],
          );
          addTearDown(router.dispose);
          await tester.pumpWidget(InputTestApp.router(routerConfig: router));
          await tester.pumpAndSettle();
          final first = tester.state(find.byType(_HistoryPage));
          router.go('/video/B');
          await tester.pumpAndSettle();
          final current = tester.state(find.byType(_HistoryPage));
          expect(current, isNot(same(first)));
          final stale = navigation['/video/B']!;
          final target = historicalTarget ? '/video/A' : '/video/C';
          stale(Uri.parse(target));
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(_HistoryPage)), same(current));
          expect(router.routeInformationProvider.value.uri.path, target);
          stale(Uri.parse('/video/stale'));
          await tester.pumpAndSettle();
          expect(router.routeInformationProvider.value.uri.path, target);
          expect(tester.state(find.byType(_HistoryPage)), same(current));
          if (!historicalTarget) {
            await tester.binding.handlePopRoute();
            await tester.pumpAndSettle();
            expect(router.routeInformationProvider.value.uri.path, '/video/A');
            expect(tester.state(find.byType(_HistoryPage)), same(first));
          }
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
        variant: TargetPlatformVariant.only(TargetPlatform.android),
      );
    }
  }

  for (final platform in [
    TargetPlatform.android,
    TargetPlatform.iOS,
    TargetPlatform.windows,
    TargetPlatform.macOS,
    TargetPlatform.linux,
  ]) {
    for (final mode in WorkspaceNavigationMode.values) {
      for (final sequence in [
        'collection',
        'related',
        'queue',
        'pgcEpisode',
        'pgcSeason',
      ]) {
        testWidgets(
          'continuous fullscreen retains owner $platform $mode $sequence',
          (tester) async {
            final mobile =
                platform == TargetPlatform.android ||
                platform == TargetPlatform.iOS;
            tester.view.devicePixelRatio = 1;
            tester.view.physicalSize = Size(mobile ? 390 : 1400, 900);
            addTearDown(tester.view.resetDevicePixelRatio);
            addTearDown(tester.view.resetPhysicalSize);
            final engine = _Engine();
            final session = PlaybackSession(
              engine: engine,
              repository: _PlaybackRepository(),
              contentRepository: _ContentRepository(),
              progress: _Progress(),
              accountScope: () => 'guest',
            );
            addTearDown(session.close);
            final settings = AppSettings.defaults(navigationMode: mode)
                .copyWith(
                  continuousPlayback: true,
                  continuousRelatedPlayback: sequence == 'related',
                  playerControlsMode: PlayerControlsMode.dynamic,
                  danmakuEnabled: false,
                );
            final window = _Window(platform);
            final registry = WatchLaterQueueRegistry();
            final videos = [
              _video(_a, collection: sequence == 'collection'),
              _video(_b, collection: sequence == 'collection'),
            ];
            final queue = sequence == 'queue'
                ? registry.capture(
                    scope: 'guest',
                    sessionEpoch: 0,
                    favoriteTitle: '测试收藏夹',
                    items: [
                      for (final video in videos)
                        WatchLaterQueueItem(video: video.summary),
                    ],
                  )
                : null;
            final pgc = sequence.startsWith('pgc');
            final router = createBiliRouter(
              initialLocation: pgc
                  ? sequence == 'pgcEpisode'
                        ? '/pgc/episode/1'
                        : '/pgc/season/1'
                  : '/video/${_a.value}${queue == null ? '' : '?queue=${queue.id}'}',
              playerBuilder: (_, detail, part) => PlaybackPanel(
                detail: detail,
                part: part,
                settings: settings,
                window: window,
                onToggleComments: () {},
              ),
              pgcPlayerBuilder: (_, season, episode) {
                final part = _parts.firstWhere(
                  (part) => part.cid == episode.cid,
                );
                final detail = VideoDetail(
                  summary: videos.first.summary,
                  description: '',
                  parts: [part],
                );
                return PlaybackPanel(
                  detail: detail,
                  part: part,
                  target: PgcPlaybackTarget(
                    episode.episodeId,
                    seasonId: season.seasonId,
                    cid: episode.cid,
                  ),
                  settings: settings,
                  window: window,
                  onToggleComments: () {},
                );
              },
            );
            addTearDown(router.dispose);
            await tester.pumpWidget(
              ProviderScope(
                overrides: [
                  settingsRepositoryProvider.overrideWithValue(
                    _SettingsRepository(settings),
                  ),
                  playbackSessionProvider.overrideWithValue(session),
                  authControllerProvider.overrideWith(_Auth.new),
                  feedRepositoryProvider.overrideWithValue(_FeedRepository()),
                  homeRepositoryProvider.overrideWithValue(_HomeRepository()),
                  pgcRepositoryProvider.overrideWithValue(_PgcRepository()),
                  watchLaterQueueRegistryProvider.overrideWithValue(registry),
                  for (final video in videos) ...[
                    videoDetailProvider(video.summary.id)
                        .overrideWith((_) async {
                          if (video.summary.id == _b) {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 50),
                            );
                          }
                          return video;
                        }),
                    relatedVideosProvider(video.summary.id).overrideWith(
                      (_) => sequence == 'related' && video.summary.id == _a
                          ? [videos.last.summary]
                          : const [],
                    ),
                    videoTagsProvider(video.summary.id)
                        .overrideWith((_) => const []),
                  ],
                ],
                child: InputTestApp.router(routerConfig: router),
              ),
            );
            await _frames(tester);
            final owner = tester.state(find.byType(PlaybackPanel));
            final tab =
                router
                    .routeInformationProvider
                    .value
                    .uri
                    .queryParameters['tab'] ??
                'tab-1';
            final fullscreen = find.byIcon(BiliIcons.fullscreen);
            await tester.tap(fullscreen);
            await _frames(tester);
            expect(window.fullscreen, isTrue);
            final route = ModalRoute.of(
              tester.element(find.byKey(const ValueKey('player-next-episode'))),
            );

            // Parts and season-based episode routes keep the same path. The
            // following cross-video/episode advance also changes the path.
            final advances = pgc ? 1 : 2;
            for (var advance = 0; advance < advances; advance++) {
              engine.end();
              engine.end();
              await _frames(tester);
              expect(tester.state(find.byType(PlaybackPanel)), same(owner));
              expect(window.commands, [true]);
              expect(window.fullscreen, isTrue);
              expect(
                ModalRoute.of(
                  tester.element(
                    find.byKey(const ValueKey('player-next-episode')),
                  ),
                ),
                same(route),
              );
              expect(
                router
                    .routeInformationProvider
                    .value
                    .uri
                    .queryParameters['tab'],
                tab,
              );
            }
            final uri = router.routeInformationProvider.value.uri;
            expect(
              uri.path,
              pgc
                  ? sequence == 'pgcEpisode'
                        ? '/pgc/episode/2'
                        : '/pgc/season/1'
                  : '/video/${_b.value}',
            );
            expect(
              pgc
                  ? (session.contentTarget as PgcPlaybackTarget).cid
                  : session.part?.cid,
              pgc ? '102' : '103',
            );
            expect(engine.opens, pgc ? 2 : 3);
            expect(engine.disposals, 0);
            expect(engine.options?.startPosition, Duration.zero);
            expect(session.snapshots.value.desiredPlaying, isTrue);

            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await _frames(tester);
            expect(window.commands, [true, false]);
            expect(window.fullscreen, isFalse);
            expect(tester.state(find.byType(PlaybackPanel)), same(owner));
            expect(tester.takeException(), isNull);
            await tester.pumpWidget(const SizedBox());
            await _frames(tester);
          },
          variant: TargetPlatformVariant.only(platform),
        );
      }
    }
  }
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage();
  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

VideoDetail _video(VideoId id, {required bool collection}) => VideoDetail(
  summary: VideoSummary(
    id: id,
    title: id == _a ? '视频 A' : '视频 B',
    coverUrl: '',
    author: 'UP',
    duration: const Duration(seconds: 20),
  ),
  description: '',
  parts: id == _a ? _parts : const [_third],
  collection: !collection
      ? null
      : const VideoCollection(
          id: '1',
          title: '测试合集',
          entries: [
            VideoCollectionEntry(id: _a, title: 'A', parts: _parts),
            VideoCollectionEntry(id: _b, title: 'B', parts: [_third]),
          ],
        ),
);

class _Engine extends CardFakeEngine {
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );

  void end() => publish(
    snapshot.copyWith(
      phase: PlaybackPhase.ended,
      position: const Duration(seconds: 20),
      desiredPlaying: false,
    ),
  );
}

class _Window extends WindowService {
  _Window(this.platform);
  final TargetPlatform platform;
  final commands = <bool>[];
  bool fullscreen = false;
  @override
  bool get hasDesktopWindow =>
      platform != TargetPlatform.android && platform != TargetPlatform.iOS;
  @override
  bool get supportsBackgroundAudio => true;
  @override
  Stream<FullScreenOrientation?> get deviceOrientations => const Stream.empty();
  @override
  Future<void> setFullScreen(
    bool value, {
    FullScreenOrientation? orientation,
  }) async {
    fullscreen = value;
    commands.add(value);
  }
}

class _Auth extends AuthController {
  @override
  AuthState build() => const AuthState();
}

class _SettingsRepository implements SettingsRepository {
  _SettingsRepository(this.settings);
  final AppSettings settings;
  @override
  Future<AppSettings> load() async => settings;
  @override
  Future<void> save(AppSettings value) async {}
}

class _PlaybackRepository extends Fake implements PlaybackRepository {
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

class _ContentRepository extends Fake implements ContentPlaybackRepository {
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

class _FeedRepository extends Fake implements FeedRepository {
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) async => const PageResult(items: [], hasMore: false);
}

class _HomeRepository extends Fake implements HomeRepository {
  @override
  String get accountScope => 'guest';
}

class _PgcRepository extends Fake implements PgcRepository {
  @override
  String get accountScope => 'guest';
  @override
  int get sessionEpoch => 0;
  @override
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    bool refresh = false,
    required RequestCancellation cancellation,
  }) async => PgcSeason(
    id: const PgcSeasonId('1'),
    title: '影视',
    episodes: const [
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
    ],
  );
}
