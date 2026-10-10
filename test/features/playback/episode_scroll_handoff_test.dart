import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/pgc/presentation/pgc_episode_panel.dart';
import 'package:bilisail/features/video/presentation/video_collection_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final kind in [
    'pgc-list',
    'pgc-grid',
    'video-parts',
    'video-collection',
  ]) {
    testWidgets(
      '$kind hands remaining touch drag to the intro at both edges',
      (tester) async {
        final outer = ScrollController();
        addTearDown(outer.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authControllerProvider.overrideWith(_GuestAuth.new)],
            child: MaterialApp(
              theme: ThemeData(platform: defaultTargetPlatform),
              home: Scaffold(
                body: SingleChildScrollView(
                  controller: outer,
                  child: Column(
                    children: [
                      const SizedBox(height: 180, child: Text('简介最上方')),
                      _panel(kind, 100),
                      const SizedBox(height: 1000, child: Text('简介底部')),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (kind == 'pgc-grid') {
          await tester.tap(find.byKey(const ValueKey('pgc-episode-view')));
          await tester.pumpAndSettle();
        }
        final viewport = kind == 'pgc-grid'
            ? find.byType(GridView)
            : find.byWidgetPredicate(
                (w) => w is ListView && w.scrollDirection == Axis.vertical,
              );
        final inner = tester
            .state<ScrollableState>(
              find
                  .descendant(of: viewport, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        outer.jumpTo(120);
        inner.jumpTo(35);
        await tester.pump();
        final gesture = await tester.startGesture(tester.getCenter(viewport));
        await gesture.moveBy(const Offset(0, 30));
        await gesture.moveBy(const Offset(0, 80));
        await tester.pump();
        expect(inner.pixels, 0);
        expect(
          outer.offset,
          lessThan(120),
          reason: 'remainder of the same drag must reach the intro',
        );
        await gesture.moveBy(const Offset(0, 180));
        await tester.pump();
        expect(outer.offset, 0);
        await gesture.up();
        await tester.pumpAndSettle();

        outer.jumpTo(120);
        inner.jumpTo(inner.maxScrollExtent - 35);
        await tester.pump();
        final reverse = await tester.startGesture(tester.getCenter(viewport));
        await reverse.moveBy(const Offset(0, -30));
        await reverse.moveBy(const Offset(0, -80));
        await tester.pump();
        expect(inner.pixels, inner.maxScrollExtent);
        expect(outer.offset, greaterThan(120));
        await reverse.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
    testWidgets(
      '$kind hands off a fling that reaches the edge after release',
      (tester) async {
        final outer = ScrollController();
        addTearDown(outer.dispose);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authControllerProvider.overrideWith(_GuestAuth.new)],
            child: MaterialApp(
              theme: ThemeData(platform: defaultTargetPlatform),
              home: Scaffold(
                body: SingleChildScrollView(
                  controller: outer,
                  child: Column(
                    children: [
                      const SizedBox(height: 180),
                      _panel(kind, 100),
                      const SizedBox(height: 1000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        if (kind == 'pgc-grid') {
          await tester.tap(find.byKey(const ValueKey('pgc-episode-view')));
          await tester.pumpAndSettle();
        }
        final viewport = kind == 'pgc-grid'
            ? find.byType(GridView)
            : find.byWidgetPredicate(
                (w) => w is ListView && w.scrollDirection == Axis.vertical,
              );
        final inner = tester
            .state<ScrollableState>(
              find
                  .descendant(of: viewport, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        outer.jumpTo(120);
        inner.jumpTo(140);
        await tester.pump();
        await tester.fling(viewport, const Offset(0, 70), 1500);
        expect(inner.pixels, greaterThan(0));
        expect(outer.offset, 120);
        await tester.pumpAndSettle();
        expect(inner.pixels, 0);
        expect(outer.offset, lessThan(120));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
    for (final count in [2, 100]) {
      testWidgets(
        '$kind continues a fling from the top ($count items)',
        (tester) async {
          final outer = ScrollController();
          addTearDown(outer.dispose);
          await tester.pumpWidget(
            ProviderScope(
              overrides: [authControllerProvider.overrideWith(_GuestAuth.new)],
              child: MaterialApp(
                theme: ThemeData(platform: defaultTargetPlatform),
                home: Scaffold(
                  body: SingleChildScrollView(
                    controller: outer,
                    child: Column(
                      children: [
                        const SizedBox(height: 180),
                        _panel(kind, count),
                        const SizedBox(height: 1000),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          if (kind == 'pgc-grid') {
            await tester.tap(find.byKey(const ValueKey('pgc-episode-view')));
            await tester.pumpAndSettle();
          }
          final viewport = kind == 'pgc-grid'
              ? find.byType(GridView)
              : find.byWidgetPredicate(
                  (w) => w is ListView && w.scrollDirection == Axis.vertical,
                );
          final inner = tester
              .state<ScrollableState>(
                find
                    .descendant(of: viewport, matching: find.byType(Scrollable))
                    .first,
              )
              .position;
          outer.jumpTo(160);
          inner.jumpTo(0);
          await tester.pump();
          await tester.fling(viewport, const Offset(0, 70), 900);
          final afterDrag = outer.offset;
          expect(afterDrag, lessThan(160));
          // Start the clamping simulation's ticker before advancing its clock.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 80));
          expect(
            outer.offset,
            lessThan(afterDrag),
            reason: 'outer motion must continue after lifting the finger',
          );
          await tester.pumpAndSettle();
          expect(outer.offset, closeTo(0, .01));
          expect(inner.pixels, closeTo(0, .01));
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
        }),
      );
    }
  }
}

Widget _panel(String kind, int count) {
  if (kind.startsWith('pgc')) {
    final season = PgcSeason(
      id: const PgcSeasonId('1'),
      title: '选集',
      episodes: [
        for (var i = 0; i < count; i++)
          PgcEpisode(
            id: PgcEpisodeId('${i + 1}'),
            title: '第 ${i + 1} 集',
            bvid: 'BV1ab411c7mD',
            cid: '${i + 1}',
          ),
      ],
    );
    return PgcEpisodePanel(
      season: season,
      selected: season.episodes.first,
      onSelect: (_) {},
    );
  }
  final parts = [
    for (var i = 0; i < count; i++)
      VideoPart(
        cid: '${i + 1}',
        page: i + 1,
        title: '分 P ${i + 1}',
        duration: const Duration(minutes: 1),
      ),
  ];
  final collection = kind == 'video-collection'
      ? VideoCollection(
          id: '1',
          title: '视频合集',
          entries: [
            for (var i = 0; i < count; i++)
              VideoCollectionEntry(
                id: i == 0
                    ? const VideoId('BV1ab411c7mD')
                    : VideoId('BV1ab411${i.toString().padLeft(4, '0')}'),
                title: '视频 ${i + 1}',
                parts: [parts.first],
              ),
          ],
        )
      : null;
  final video = VideoDetail(
    summary: const VideoSummary(
      id: VideoId('BV1ab411c7mD'),
      title: '视频',
      author: 'UP',
      coverUrl: '',
      duration: Duration(minutes: 1),
    ),
    description: '',
    parts: parts,
    collection: collection,
  );
  return VideoCollectionPanel(
    video: video,
    selected: parts.first,
    onSelectPart: (_) {},
  );
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthState();
}
