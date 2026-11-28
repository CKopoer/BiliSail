import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/responsive_layout_settings.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/shared/ui/app_cover_image.dart';
import 'package:bilisail/shared/ui/responsive_layout_scope.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:material_ui/material_ui.dart';
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
          child: ResponsiveLayoutScope(
            settings: ResponsiveLayoutSettings(
              cardCoverRatios: const {
                CardCoverGroup.mine: CardCoverRatio.standard,
              },
            ),
            child: MaterialApp.router(routerConfig: router),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final covers = tester.widgetList<AppCoverImage>(
        find.byType(AppCoverImage),
      );
      expect(covers.map((image) => image.url), [_firstWide, _secondStandard]);
      expect(covers.map((image) => image.fit), everyElement(BoxFit.cover));
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
      expect(queue.items.first.video.cover43Url, isNull);
      expect(queue.items.last.video.coverUrl, _secondWide);
      expect(queue.items.last.video.cover43Url, Uri.parse(_secondStandard));
      expect(queue.items.last.entryId, '2');
      expect(queue.items.last.aid, '9007199254740993');
      expect(tester.takeException(), isNull);
    });
  }
}

const _firstWide = 'https://i0.hdslb.com/first-wide.jpg';
const _secondWide = 'https://i0.hdslb.com/second-wide.jpg';
const _secondStandard = 'https://i0.hdslb.com/second-standard.jpg';

final class _Repository implements HomeRepository {
  @override
  String get accountScope => 'user:7';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async => HomePage([
    HomeEntry(
      id: '1',
      title: '第一条',
      kind: HomeEntryKind.video,
      bvid: 'BV1abc123456',
      coverUrl: Uri.parse(_firstWide),
    ),
    const HomeEntry(id: 'invalid', title: '失效条目', kind: HomeEntryKind.video),
    HomeEntry(
      id: '2',
      aid: '9007199254740993',
      title: '第二条',
      kind: HomeEntryKind.video,
      bvid: 'BV2abc123456',
      coverUrl: Uri.parse(_secondWide),
      cover43Url: Uri.parse(_secondStandard),
      authorName: '测试 UP',
      playCountText: '2万',
      danmakuCountText: '100',
    ),
  ], hasMore: false);
}
