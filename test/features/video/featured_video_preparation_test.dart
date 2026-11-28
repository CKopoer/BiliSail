import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/playback/application/featured_prepared_engine.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/presentation/playback_panel.dart';
import 'package:bilisail/features/settings/domain/app_settings.dart';
import 'package:bilisail/core/presentation/workspace_activity.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/recommendation_settings.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/featured_feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/video/application/featured_video_preparation.dart';
import 'package:bilisail/features/video/application/video_controller.dart';
import 'package:bilisail/features/video/domain/video_repository.dart';
import 'package:bilisail/features/video/presentation/featured_video_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/input_test_app.dart';
import '../../support/system_media_playback_fixture.dart';
import '../../support/video_card_fake_engine.dart';
import '../../support/window_service_fake.dart';

class _Videos implements VideoRepository, FeaturedFeedRepository {
  _Videos({int count = 5})
    : items = List.generate(
        count,
        (i) => VideoSummary(
          id: VideoId('BV17x411w7K${i.toRadixString(36)}'),
          title: '视频 $i',
          author: '作者',
          coverUrl: '',
          duration: const Duration(minutes: 1),
          previewCid: i == 1 ? null : '${i + 1}',
        ),
      );
  final List<VideoSummary> items;
  final reads = <VideoId>[];
  @override
  Future<PageResult<VideoSummary>> loadFeatured({
    required FeaturedSource source,
    required int batch,
    required bool refresh,
    FeaturedSeed? seed,
    required RequestCancellation cancellation,
  }) async => PageResult(items: items, hasMore: false);
  @override
  Future<VideoDetail> loadDetail(
    VideoId id, {
    required RequestCancellation cancellation,
  }) async {
    reads.add(id);
    final video = items.firstWhere((item) => item.id == id);
    return VideoDetail(
      summary: video,
      description: '',
      parts: [
        VideoPart(
          cid: video.previewCid ?? '2',
          page: 1,
          title: video.title,
          duration: video.duration,
        ),
      ],
    );
  }
}

class _PagingEngine extends CardFakeEngine {
  @override
  Future<void> setVolume(double volume) async =>
      publish(snapshot.copyWith(volume: volume));
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
  );
}

void main() {
  testWidgets(
    'the feed retains details for the last 16 visited parts across navigation',
    (tester) async {
      final videos = _Videos(count: 18);
      final visible = ValueNotifier(true);
      addTearDown(visible.dispose);
      final feed = FeaturedFeedController(
        videos,
        FeaturedSource.desktop,
        RecommendationFilter(const RecommendationSettings.defaults()),
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [videoRepositoryProvider.overrideWithValue(videos)],
          child: InputTestApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: visible,
                builder: (_, on, child) =>
                    WorkspaceMediaPermission(allowed: on, child: child!),
                child: FeaturedVideoScreen(
                  createController: () => feed,
                  splitWidth: 1000,
                  onLogin: () {},
                  onOpenUser: (_) {},
                  playerBuilder: (_, detail, _) =>
                      Text(detail.summary.id.value),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> visit(int index) async {
        tester
            .widget<PageView>(find.byType(PageView))
            .controller!
            .jumpToPage(index);
        await tester.pumpAndSettle();
        expect(feed.selected, index);
        expect(find.text(videos.items[index].id.value), findsOneWidget);
      }

      for (var i = 1; i < videos.items.length; i++) {
        await visit(i);
      }
      expect(videos.reads, videos.items.map((item) => item.id));
      visible.value = false;
      await tester.pumpAndSettle();
      visible.value = true;
      await tester.pumpAndSettle();
      expect(
        tester.widget<PageView>(find.byType(PageView)).controller!.page,
        17,
      );
      expect(find.text(videos.items[17].id.value), findsOneWidget);
      for (var i = 16; i >= 2; i--) {
        await visit(i);
      }
      expect(videos.reads, hasLength(18));
      await visit(1);
      expect(videos.reads, hasLength(19));
      expect(videos.reads.last, videos.items[1].id);
    },
  );

  testWidgets(
    'swiping the actual player adopts the silent neighbor without a second DASH open',
    (tester) async {
      final videos = _Videos();
      final primary = _PagingEngine();
      final spares = <_PagingEngine>[];
      final repo = SystemMediaFixtureRepository();
      final session = PlaybackSession(
        engine: primary,
        repository: repo,
        progress: SystemMediaFixtureProgress(),
        accountScope: () => 'guest',
        featuredStandby: FeaturedPreparedEngine(
          createEngine: () {
            final engine = _PagingEngine();
            spares.add(engine);
            return engine;
          },
        ),
        resolveFeatured: repo.resolve,
      );
      final manager = PlaybackManager(createSession: (_) => session);
      final window = FakePlaybackWindowService(
        viewId: tester.view.viewId,
        setFullScreen: (_) async {},
        activate: () async {},
      );
      final settings = const AppSettings.defaults().copyWith(
        autoPlay: false,
        danmakuEnabled: false,
      );
      Future<void> frames() async {
        for (var i = 0; i < 7; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoRepositoryProvider.overrideWithValue(videos),
            featuredPlayInfoPreparationProvider.overrideWithValue(
              (_, _, {required neighbor}) => () {},
            ),
            playbackManagerProvider.overrideWithValue(manager),
            playbackSessionProvider.overrideWithValue(session),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: FeaturedVideoScreen(
                createController: () => FeaturedFeedController(
                  videos,
                  FeaturedSource.desktop,
                  RecommendationFilter(const RecommendationSettings.defaults()),
                ),
                splitWidth: 1000,
                onLogin: () {},
                onOpenUser: (_) {},
                playerBuilder: (_, detail, part) => PlaybackPanel(
                  detail: detail,
                  part: part,
                  settings: settings,
                  window: window,
                  onToggleComments: () {},
                ),
              ),
            ),
          ),
        ),
      );
      await frames();
      expect(primary.opens, 1);
      expect(spares.single.currentSnapshot.volume, 0);
      expect(spares.single.currentSnapshot.desiredPlaying, isFalse);
      final prepared = spares.single;
      await tester.fling(find.byType(PageView), const Offset(0, -350), 900);
      await tester.pumpAndSettle();
      await frames();
      expect(session.detail?.summary.id, videos.items[1].id);
      expect(session.engine, same(prepared));
      expect(prepared.opens, 1);
      expect(primary.disposals, 0);
      expect(primary.currentSnapshot.phase, PlaybackPhase.paused);
      expect(primary.currentSnapshot.volume, 0);
      await tester.fling(find.byType(PageView), const Offset(0, 350), 900);
      await tester.pumpAndSettle();
      await frames();
      expect(session.detail?.summary.id, videos.items.first.id);
      expect(session.engine, same(primary));
      expect(primary.opens, 1);
      expect(prepared.currentSnapshot.phase, PlaybackPhase.paused);
      expect(prepared.currentSnapshot.volume, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await frames();
      final closing = session.close();
      await frames();
      await closing;
      await manager.close();
    },
  );

  testWidgets(
    'next card resolves before a swipe, only the settled card mounts a player and leaving drops leases',
    (tester) async {
      final videos = _Videos();
      final active = ValueNotifier(true);
      addTearDown(active.dispose);
      final opened = <VideoId>{};
      final leases = <(VideoId, String, bool)>{};
      final preparations = <VideoId>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoRepositoryProvider.overrideWithValue(videos),
            featuredPlayInfoPreparationProvider.overrideWithValue((
              video,
              cid, {
              required neighbor,
            }) {
              preparations.add(video);
              leases.add((video, cid, neighbor));
              return () => leases.remove((video, cid, neighbor));
            }),
          ],
          child: InputTestApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: active,
                builder: (context, on, child) =>
                    WorkspaceActivity(active: on, child: child!),
                child: FeaturedVideoScreen(
                  createController: () => FeaturedFeedController(
                    videos,
                    FeaturedSource.desktop,
                    RecommendationFilter(
                      const RecommendationSettings.defaults(),
                    ),
                  ),
                  splitWidth: 1000,
                  onLogin: () {},
                  onOpenUser: (_) {},
                  playerBuilder: (_, detail, part) {
                    opened.add(detail.summary.id);
                    return const SizedBox.expand();
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final ids = videos.items.map((e) => e.id).toList();
      expect(videos.reads, ids.take(2));
      expect(leases, {(ids[0], '1', false), (ids[1], '2', true)});
      expect(opened, {ids[0]});
      await tester.fling(find.byType(PageView), const Offset(0, -350), 900);
      await tester.pumpAndSettle();
      expect(videos.reads, ids.take(3));
      expect(preparations.toSet(), ids.take(3).toSet());
      expect(opened, {ids[0], ids[1]});
      expect(leases, {
        (ids[0], '1', true),
        (ids[1], '2', false),
        (ids[2], '3', true),
      });
      await tester.fling(find.byType(PageView), const Offset(0, 350), 900);
      await tester.pumpAndSettle();
      expect(videos.reads, ids.take(3));
      expect(leases, {(ids[0], '1', false), (ids[1], '2', true)});
      active.value = false;
      await tester.pumpAndSettle();
      expect(leases, isEmpty);
    },
  );
}
