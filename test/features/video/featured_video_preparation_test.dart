import 'dart:async';
import 'dart:ui' as ui;

import 'package:bili_player/bili_player.dart';
import 'package:bilisail/features/playback/application/featured_prepared_engine.dart';
import 'package:bilisail/features/playback/application/playback_manager.dart';
import 'package:bilisail/features/playback/application/playback_session.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
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
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../support/input_test_app.dart';
import '../../support/fake_video_output.dart';
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

class _PagingRepository extends SystemMediaFixtureRepository {
  @override
  Future<List<TimedComment>> comments(
    String cid,
    int segment, {
    required RequestCancellation cancellation,
  }) async => [
    TimedComment(
      id: cid,
      position: Duration.zero,
      text: 'MMMM',
      mode: 5,
      color: cid == '1' ? 0x00ff00 : 0xff00ff,
      fontSize: 24,
    ),
  ];
}

class _PagingEngine extends CardFakeEngine {
  _PagingEngine(this.color);
  final Color color;
  Completer<void>? pauseBarrier;
  late final _output = FakeVideoOutput(
    () => ColoredBox(key: ObjectKey(this), color: color),
  );
  @override
  VideoOutput get videoOutput => _output;

  @override
  Future<void> setVolume(double volume) async =>
      publish(snapshot.copyWith(volume: volume));
  @override
  Future<void> play() async => publish(
    snapshot.copyWith(phase: PlaybackPhase.playing, desiredPlaying: true),
  );
  @override
  Future<void> pause() async {
    publish(
      snapshot.copyWith(phase: PlaybackPhase.paused, desiredPlaying: false),
    );
    await pauseBarrier?.future;
  }
}

void main() {
  testWidgets(
    'the feed retains details for the last 8 visited parts across navigation',
    (tester) async {
      final videos = _Videos(count: 10);
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
        9,
      );
      expect(find.text(videos.items[9].id.value), findsOneWidget);
      for (var i = 8; i >= 2; i--) {
        await visit(i);
      }
      expect(videos.reads, hasLength(10));
      await visit(1);
      expect(videos.reads, hasLength(11));
      expect(videos.reads.last, videos.items[1].id);
    },
  );

  testWidgets(
    'a visible neighbor plays muted and keeps its surface through handoff',
    (tester) async {
      final videos = _Videos();
      final capture = GlobalKey();
      final primary = _PagingEngine(const Color(0xff206ba0));
      final spares = <_PagingEngine>[];
      final repo = _PagingRepository();
      final session = PlaybackSession(
        engine: primary,
        repository: repo,
        progress: SystemMediaFixtureProgress(),
        accountScope: () => 'guest',
        featuredStandby: FeaturedPreparedEngine(
          createEngine: () {
            final engine = _PagingEngine(const Color(0xffb54926));
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
        danmakuEnabled: true,
        danmakuOpacity: 1,
      );
      Future<void> frames() async {
        for (var i = 0; i < 7; i++) {
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pump(const Duration(milliseconds: 16));
        }
      }

      // The fixed layer is retained between paint ticks. Inspect its actual
      // pixels so a stale first paint cannot pass on controller identity alone.
      Future<String?> checkDanmaku(String step) async {
        final fixed = find.byKey(const ValueKey('danmaku-fixed-layer'));
        if (fixed.evaluate().isEmpty) return null;
        final panel = tester.widget<PlaybackPanel>(
          find.ancestor(of: fixed, matching: find.byType(PlaybackPanel)),
        );
        final box = tester.renderObject<RenderRepaintBoundary>(fixed);
        final layer = box.debugLayer! as OffsetLayer;
        final colors = await tester.runAsync(() async {
          final image = await layer.toImage(
            Rect.fromLTWH(box.size.width / 2 - 40, 0, 80, 48),
          );
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            final cids = <String>{};
            for (var i = 0; i < rgba.lengthInBytes; i += 4) {
              if (rgba.getUint8(i + 1) > 220 && rgba.getUint8(i) < 30) {
                cids.add('1');
              }
              if (rgba.getUint8(i) > 220 &&
                  rgba.getUint8(i + 1) < 30 &&
                  rgba.getUint8(i + 2) > 220) {
                cids.add('2');
              }
            }
            return cids;
          } finally {
            image.dispose();
          }
        });
        expect(
          colors!.difference({panel.part!.cid}),
          isEmpty,
          reason: '$step, visible CID ${panel.part!.cid}',
        );
        return colors.firstOrNull;
      }

      Future<void> checkPixel(_PagingEngine target, String step) async {
        final box =
            capture.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final layer = box.debugLayer! as OffsetLayer;
        final color = await tester.runAsync(() async {
          final image = await layer.toImage(
            Rect.fromLTWH(box.size.width / 2, box.size.height / 2, 1, 1),
          );
          try {
            final rgba = (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
            return Color.fromARGB(
              rgba.getUint8(3),
              rgba.getUint8(0),
              rgba.getUint8(1),
              rgba.getUint8(2),
            );
          } finally {
            image.dispose();
          }
        });
        expect(
          color,
          target.color,
          reason:
              '$step (selected video ${session.detail?.summary.id}, '
              'resolving ${session.isResolving}, '
              'mounted target surfaces ${find.byKey(ObjectKey(target)).evaluate().length})',
        );
      }

      Future<void> swipe(int direction, _PagingEngine target) async {
        final pager = find.byType(PageView);
        final leaving = session.engine as _PagingEngine;
        final pause = leaving.pauseBarrier = Completer<void>();
        final drag = await tester.startGesture(tester.getCenter(pager));
        await drag.moveBy(Offset(0, -30.0 * direction));
        await tester.pump();
        await drag.moveBy(
          Offset(0, -tester.getSize(pager).height * .7 * direction),
        );
        await tester.pump();
        expect(target.currentSnapshot.desiredPlaying, isTrue);
        expect(target.currentSnapshot.volume, 0);
        expect(session.engine, same(leaving));
        await checkPixel(target, 'incoming preview in direction $direction');
        await checkDanmaku('incoming preview in direction $direction');
        final surface = find.ancestor(
          of: find.byKey(ObjectKey(target)),
          matching: find.byType(VideoSurface),
        );
        final previewState = tester.state(surface);
        await drag.up();
        // Sample each animation frame across the change from preview to
        // selected. Waiting for settle alone misses a one-frame black mask.
        var resolvingFrames = 0;
        var playingSurfaceFrames = 0;
        final targetCid = direction == 1 ? '2' : '1';
        var paintedTarget = false;
        for (var frame = 0; frame < 90 && playingSurfaceFrames < 4; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          await checkPixel(target, 'direction $direction, frame $frame');
          final painted = await checkDanmaku(
            'direction $direction, frame $frame',
          );
          if (paintedTarget) {
            expect(painted, targetCid, reason: 'target danmaku disappeared');
          }
          if (painted == targetCid) paintedTarget = true;
          if (session.isResolving &&
              !pause.isCompleted &&
              ++resolvingFrames == 4) {
            pause.complete();
            leaving.pauseBarrier = null;
          }
          if (identical(session.engine, target) && !session.isResolving) {
            playingSurfaceFrames++;
          }
        }
        expect(resolvingFrames, 4);
        expect(playingSurfaceFrames, 4);
        expect(paintedTarget, isTrue);
        expect(tester.state(surface), same(previewState));
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
              body: RepaintBoundary(
                key: capture,
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
        ),
      );
      await frames();
      expect(await checkDanmaku('initial card'), '1');
      expect(primary.opens, 1);
      expect(spares.single.currentSnapshot.volume, 0);
      expect(spares.single.currentSnapshot.desiredPlaying, isFalse);
      final prepared = spares.single;
      final warmSurface = find.byWidgetPredicate(
        (widget) =>
            widget is VideoSurface && identical(widget.engine, prepared),
        skipOffstage: false,
      );
      final preparedState = tester.state(warmSurface);
      final pager = find.byType(PageView);
      final canceled = await tester.startGesture(tester.getCenter(pager));
      await canceled.moveBy(const Offset(0, -30));
      await canceled.moveBy(const Offset(0, -120));
      await tester.pump();
      expect(prepared.currentSnapshot.desiredPlaying, isTrue);
      expect(prepared.currentSnapshot.volume, 0);
      expect(session.engine, same(primary));
      await canceled.moveBy(const Offset(0, 160));
      await tester.pump();
      expect(prepared.currentSnapshot.desiredPlaying, isFalse);
      await canceled.up();
      await frames();
      expect(tester.widget<PageView>(pager).controller!.page, 0);
      expect(tester.state(warmSurface), same(preparedState));
      expect(session.engine, same(primary));
      expect(primary.currentSnapshot.desiredPlaying, isTrue);
      expect(prepared.opens, 1);

      final interrupted = await tester.startGesture(tester.getCenter(pager));
      await interrupted.moveBy(const Offset(0, -30));
      await interrupted.moveBy(const Offset(0, -120));
      await tester.pump();
      expect(prepared.currentSnapshot.desiredPlaying, isTrue);
      final context = tester.element(find.byType(FeaturedVideoScreen));
      final modal = showDialog<void>(
        context: context,
        builder: (_) => const AlertDialog(title: Text('测试弹窗')),
      );
      await frames();
      expect(prepared.currentSnapshot.desiredPlaying, isFalse);
      await interrupted.up();
      Navigator.of(context).pop();
      await modal;
      await frames();
      expect(tester.widget<PageView>(pager).controller!.page, 0);
      expect(session.engine, same(primary));
      expect(prepared.opens, 1);

      await swipe(1, prepared);
      expect(session.detail?.summary.id, videos.items[1].id);
      expect(session.engine, same(prepared));
      expect(prepared.opens, 1);
      expect(primary.disposals, 0);
      expect(primary.currentSnapshot.phase, PlaybackPhase.paused);
      expect(primary.currentSnapshot.volume, 0);
      await swipe(-1, primary);
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

      // A long swipe can cross another slot before it lands. Only the final
      // page mounts foreground controls and can acquire playback ownership.
      final pager = find.byType(PageView);
      final drag = await tester.startGesture(tester.getCenter(pager));
      await drag.moveBy(const Offset(0, -30));
      await drag.moveBy(Offset(0, -tester.getSize(pager).height * 2.8));
      await tester.pump();
      expect(opened, {ids[0], ids[1]});
      await drag.up();
      await tester.pumpAndSettle();
      expect(tester.widget<PageView>(pager).controller!.page, 3);
      expect(opened, {ids[0], ids[1], ids[3]});
      active.value = false;
      await tester.pumpAndSettle();
      expect(leases, isEmpty);
    },
  );
}
