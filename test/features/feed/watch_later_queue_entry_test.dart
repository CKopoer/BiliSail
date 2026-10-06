import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  for (final section in HomeChannel.watchLater.sections) {
    testWidgets('$section opens its complete ordered watch-later snapshot', (
      tester,
    ) async {
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(_Repository()),
          sessionEpochProvider.overrideWithValue(() => 4),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => Scaffold(
              body: HomeContent(
                channel: HomeChannel.watchLater,
                section: section,
                isSignedIn: true,
              ),
            ),
          ),
          GoRoute(
            path: '/video/:bvid',
            builder: (_, _) => const SizedBox.shrink(),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<VideoCard>(find.byType(VideoCard))
            .every((card) => !card.showWatchLaterButton),
        isTrue,
      );
      await tester.tap(find.text('第二条'));
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/video/BV2abc123456');
      final queue = container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            uri.queryParameters['queue'],
            scope: 'user:7',
            sessionEpoch: 4,
          );
      expect(queue, isNotNull);
      expect(queue!.items.map((item) => item.video.id), [
        const VideoId('BV1abc123456'),
        const VideoId('BV2abc123456'),
      ]);
      expect(queue.items.last.playCountText, '2万');
      expect(queue.items.last.danmakuCountText, '100');
      expect(queue.items.last.video.author, '测试 UP');
      expect(tester.takeException(), isNull);
    });
  }
}

final class _Repository implements HomeRepository {
  @override
  String get accountScope => 'user:7';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => const HomePage([
    HomeEntry(
      id: '1',
      title: '第一条',
      kind: HomeEntryKind.video,
      bvid: 'BV1abc123456',
    ),
    HomeEntry(id: 'invalid', title: '失效条目', kind: HomeEntryKind.video),
    HomeEntry(
      id: '2',
      title: '第二条',
      kind: HomeEntryKind.video,
      bvid: 'BV2abc123456',
      authorName: '测试 UP',
      playCountText: '2万',
      danmakuCountText: '100',
    ),
  ], hasMore: false);
}
