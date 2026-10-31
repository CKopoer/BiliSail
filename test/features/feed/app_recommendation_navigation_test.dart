import 'package:bilisail/core/platform/external_links.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/presentation/feed_video_grid.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final (kind, id, route) in [
    (RecommendationTargetKind.episode, '42', '/pgc/episode/42'),
    (RecommendationTargetKind.season, '99', '/pgc/season/99'),
    (RecommendationTargetKind.live, '777', '/live/777'),
    (RecommendationTargetKind.video, 'BV17x411w7KC', '/video/BV17x411w7KC'),
  ]) {
    testWidgets('accepted $kind opens its own destination', (tester) async {
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => _grid(RecommendationTarget(kind: kind, id: id)),
          ),
          GoRoute(
            path: route,
            builder: (_, _) => const Scaffold(body: Text('正确内容')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(child: MaterialApp.router(routerConfig: router)),
      );
      await tester.pumpAndSettle();
      tester.widget<VideoCard>(find.byType(VideoCard)).onTap();
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, route);
      expect(find.text('正确内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('dynamic recommendation uses the explicit link opener', (
    tester,
  ) async {
    final opened = <Uri>[];
    final url = Uri.parse('https://t.bilibili.com/9007199254740993123');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          externalLinkOpenerProvider.overrideWithValue((uri) async {
            opened.add(uri);
            return true;
          }),
        ],
        child: MaterialApp(
          home: _grid(
            RecommendationTarget(
              kind: RecommendationTargetKind.dynamic,
              url: url,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.widget<VideoCard>(find.byType(VideoCard)).onTap();
    await tester.pumpAndSettle();
    expect(opened, [url]);
    expect(tester.takeException(), isNull);
  });
}

Widget _grid(RecommendationTarget target) => Scaffold(
  body: CustomScrollView(
    slivers: [
      FeedVideoGrid(
        items: [
          VideoSummary(
            id: const VideoId('app:fixture:42'),
            title: '推荐内容',
            coverUrl: '',
            author: '',
            duration: Duration.zero,
            recommendationTarget: target,
          ),
        ],
        channel: HomeChannel.popular,
        onReject: (_) {},
        onUndo: (_) {},
      ),
    ],
  ),
);
