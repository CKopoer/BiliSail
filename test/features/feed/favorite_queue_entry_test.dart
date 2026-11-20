import '../../support/material_tooltip_finder.dart';

import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/favorite_content_filter.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/auth/application/auth_controller.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/features/video/application/playback_queue_controller.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/shared/ui/app_notice.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../messages/message_fakes.dart';

void main() {
  late _Repository repository;
  late ProviderContainer container;
  late GoRouter router;
  late AuthFake auth;
  setUp(() {
    auth = AuthFake();
    repository = _Repository();
    container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(auth),
        homeRepositoryProvider.overrideWithValue(repository),
        sessionEpochProvider.overrideWithValue(() => 4),
      ],
    );
  });
  tearDown(() async {
    router.dispose();
    container.dispose();
    await auth.stream.close();
  });
  Future<void> mount(
    WidgetTester tester,
    String section, {
    double scale = 1,
  }) async {
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: HomeContent(
              channel: HomeChannel.favorites,
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
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          routerConfig: router,
          builder: (context, child) => AppNoticeHost(
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'default folder can search all favorites and page the filtered queue',
    (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await mount(tester, '默认收藏夹', scale: 2);

      final search = find.byKey(const ValueKey('favorite-content-search'));
      await tester.enterText(search, '  测试  ');
      await tester.tap(find.byKey(const ValueKey('favorite-search-scope')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<bool>, '我的全部收藏'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('favorite-content-sort')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(CheckedPopupMenuItem<FavoriteContentOrder>, '最多播放'),
      );
      await tester.pumpAndSettle();
      const filter = (
        keyword: '测试',
        order: FavoriteContentOrder.mostPlayed,
        allFolders: true,
      );
      expect(repository.filteredCalls.last, (filter, 1));
      expect(find.text('匹配 1'), findsOneWidget);
      expect(find.text('视频 1'), findsNothing);
      expect(tester.takeException(), isNull);

      final beforeCapture = repository.filteredCalls.length;
      await tester.tap(find.byKey(const ValueKey('favorite-play-all')));
      await tester.pumpAndSettle();
      final queueId =
          router.routeInformationProvider.value.uri.queryParameters['queue']!;
      final subscription = container.listen(
        playbackQueueProvider(queueId),
        (_, _) {},
      );
      addTearDown(subscription.close);
      await tester.pumpAndSettle();
      final queueController = container.read(
        playbackQueueProvider(queueId).notifier,
      );
      await queueController.loadMore(const VideoId('BV0000000001'));
      expect(repository.filteredCalls.skip(beforeCapture), [
        (filter, 1),
        (filter, 2),
      ]);
    },
  );

  testWidgets(
    'new folder searches cancel the previous page and can be cleared',
    (tester) async {
      await mount(tester, '我创建的收藏夹');
      await tester.tap(find.text('测试收藏夹'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('favorite-search-scope')), findsNothing);
      final search = find.byKey(const ValueKey('favorite-content-search'));
      final pending = repository.pendingFilter = Completer<HomePage>();
      await tester.enterText(search, '旧搜索');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      final stale = repository.lastCancellation!;
      repository.pendingFilter = null;
      await tester.enterText(search, '无结果');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(stale.isCancelled, isTrue);
      pending.complete(
        const HomePage([
          HomeEntry(id: '99', kind: HomeEntryKind.video, title: '旧结果'),
        ], hasMore: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('旧结果'), findsNothing);
      expect(find.text('没有找到匹配的收藏视频'), findsOneWidget);
      await tester.tap(find.byTooltip('清除搜索'));
      await tester.pumpAndSettle();
      expect(find.text('视频 1'), findsOneWidget);
    },
  );

  for (final section in ['默认收藏夹', '我创建的收藏夹']) {
    testWidgets('$section remaining video opens immediately after removal', (
      tester,
    ) async {
      repository.totalVideos = 3;
      await mount(tester, section);
      if (section != '默认收藏夹') {
        await tester.tap(find.text('测试收藏夹'));
        await tester.pumpAndSettle();
      }
      await tester.longPress(
        find.ancestor(
          of: find.text('视频 1'),
          matching: find.byType(HomeVideoCard),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消收藏'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('确认取消'));
      await tester.pumpAndSettle();
      expect(find.text('视频 1'), findsNothing);
      final before = repository.pages.length;
      await tester.tap(find.text('视频 2'));
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/video/BV0000000002');
      final queue = container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            uri.queryParameters['queue'],
            scope: 'user:7',
            sessionEpoch: 4,
          )!;
      expect(queue.items.map((item) => item.video.id.value), [
        'BV0000000002',
        'BV0000000003',
      ]);
      expect(repository.pages.skip(before), [1]);
      expect(tester.takeException(), isNull);
    });
  }

  for (final section in ['默认收藏夹', '我创建的收藏夹', '我的收藏与订阅']) {
    for (final playAll in [true, false]) {
      testWidgets(
        '$section ${playAll ? 'play all' : 'select item'} starts with a single source page',
        (tester) async {
          await mount(tester, section);
          if (section != '默认收藏夹') {
            expect(
              find.byKey(const ValueKey('favorite-play-all')),
              findsNothing,
            );
            await tester.tap(find.text('测试收藏夹'));
            await tester.pumpAndSettle();
          }
          final readsBefore = repository.pages.length;
          await tester.tap(
            playAll
                ? find.byKey(const ValueKey('favorite-play-all'))
                : find.text('视频 2'),
          );
          await tester.pumpAndSettle();
          final uri = router.routeInformationProvider.value.uri;
          expect(
            uri.path,
            playAll ? '/video/BV0000000001' : '/video/BV0000000002',
          );
          final queue = container
              .read(watchLaterQueueRegistryProvider)
              .resolve(
                uri.queryParameters['queue'],
                scope: 'user:7',
                sessionEpoch: 4,
              )!;
          expect(queue.items, hasLength(24));
          expect(queue.items.last.video.id.value, 'BV0000000024');
          expect(queue.hasMore, true);
          expect(queue.homeSource, isNotNull);
          expect(queue.title, section == '默认收藏夹' ? section : '测试收藏夹');
          expect(queue.isWatchLater, isFalse);
          expect(repository.pages.skip(readsBefore), [1]);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  testWidgets(
    'play all disables duplicate requests, leaving folder cancels pending navigation',
    (tester) async {
      await mount(tester, '我创建的收藏夹');
      await tester.tap(find.text('测试收藏夹'));
      await tester.pumpAndSettle();
      repository.pending = Completer<HomePage>();
      await tester.tap(find.byKey(const ValueKey('favorite-play-all')));
      await tester.pump();
      final button = tester.widget<TextButton>(
        find.byKey(const ValueKey('favorite-play-all')),
      );
      expect(button.onPressed, isNull);
      final cancellation = repository.lastCancellation!;
      await tester.tap(findMaterialTooltip('返回列表'));
      await tester.pumpAndSettle();
      expect(cancellation.isCancelled, isTrue);
      repository.pending!.complete(const HomePage([], hasMore: false));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('leaving a folder cancels reconciliation and late navigation', (
    tester,
  ) async {
    repository.totalVideos = 3;
    await mount(tester, '我创建的收藏夹');
    await tester.tap(find.text('测试收藏夹'));
    await tester.pumpAndSettle();
    const query = (
      channel: HomeChannel.favorites,
      section: '我创建的收藏夹',
      scope: 'user:7',
      folderId: '42',
    );
    final provider = homeControllerProvider(query);
    final first = container
        .read(provider)
        .items
        .requireValue
        .firstWhere((entry) => entry.id == '1');
    expect(await container.read(provider.notifier).removeFavorite(first), true);
    await tester.pumpAndSettle();
    repository.pending = Completer<HomePage>();
    final before = repository.pages.length;
    await tester.tap(find.text('视频 2'));
    await tester.pump();
    final cancellation = repository.lastCancellation!;
    await tester.tap(findMaterialTooltip('返回列表'));
    await tester.pumpAndSettle();
    expect(cancellation.isCancelled, true);
    repository.pending!.complete(const HomePage([], hasMore: true));
    await tester.pumpAndSettle();
    expect(repository.pages.skip(before), [1]);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'clicking a video on a later browser page does not add the earlier page',
    (tester) async {
      await mount(tester, '默认收藏夹');
      final query = (
        channel: HomeChannel.favorites,
        section: '默认收藏夹',
        scope: 'user:7',
        folderId: null as String?,
      );
      await container.read(homeControllerProvider(query).notifier).loadMore();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('视频 25'),
        400,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final before = repository.pages.length;
      await tester.tap(find.text('视频 25'));
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      final queue = container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            uri.queryParameters['queue'],
            scope: 'user:7',
            sessionEpoch: 4,
          )!;
      expect(queue.items, hasLength(1));
      expect(queue.items.single.video.id.value, 'BV0000000025');
      expect(queue.pages.single.page, 2);
      expect(queue.hasPrevious, true);
      expect(repository.pages.skip(before), [2]);
    },
  );

  testWidgets(
    'subscribed UGC collections retain their distinct paging identity',
    (tester) async {
      repository.collection = true;
      await mount(tester, '我的收藏与订阅');
      await tester.tap(find.text('测试收藏夹'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('favorite-play-all')));
      await tester.pumpAndSettle();
      expect(repository.folderIds, everyElement('ugc:42'));
      expect(
        router.routeInformationProvider.value.uri.path,
        '/video/BV0000000001',
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'a retained later-page card opens after moving to the first page',
    (tester) async {
      await mount(tester, '默认收藏夹');
      const query = (
        channel: HomeChannel.favorites,
        section: '默认收藏夹',
        scope: 'user:7',
        folderId: null,
      );
      final provider = homeControllerProvider(query);
      final controller = container.read(provider.notifier);
      await controller.loadMore();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('视频 25'),
        400,
        scrollable: find.descendant(
          of: find.byType(CustomScrollView),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Scrollable &&
                widget.axisDirection == AxisDirection.down,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = container
          .read(provider)
          .items
          .requireValue
          .firstWhere((entry) => entry.id == '1');
      expect(await controller.removeFavorite(first), true);
      // Tap the retained card before a browser frame can reconcile its page.
      await tester.tap(find.text('视频 25'));
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      expect(uri.path, '/video/BV0000000025');
      final queue = container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            uri.queryParameters['queue'],
            scope: 'user:7',
            sessionEpoch: 4,
          )!;
      expect(queue.pages.single.page, 1);
      expect(queue.items, hasLength(24));
      expect(queue.items.last.video.id.value, 'BV0000000025');
      expect(queue.hasPrevious, false);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folder header fits narrow screens with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mount(tester, '我创建的收藏夹', scale: 2);
    await tester.tap(find.text('测试收藏夹'));
    await tester.pumpAndSettle();
    expect(find.text('播放全部'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

final class _Repository
    implements
        HomeRepository,
        HomeFavoriteRepository,
        HomeFavoriteContentRepository {
  @override
  String get accountScope => 'user:7';
  final pages = <int>[];
  final folderIds = <String?>[];
  bool collection = false;
  int totalVideos = 25;
  final removed = <String>{};
  Completer<HomePage>? pending;
  Completer<HomePage>? pendingFilter;
  RequestCancellation? lastCancellation;
  final filteredCalls = <(FavoriteContentFilter, int)>[];

  @override
  Future<HomePage> loadFilteredFavorites(
    HomeQuery query,
    FavoriteContentFilter filter, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    filteredCalls.add((filter, page));
    lastCancellation = cancellation;
    if (pendingFilter case final pending?) return pending.future;
    if (filter.keyword == '无结果') return const HomePage([], hasMore: false);
    return HomePage(
      [
        for (var n = (page - 1) * 24 + 1; n <= page * 24; n++)
          HomeEntry(
            id: '$n',
            aid: '$n',
            kind: HomeEntryKind.video,
            title: '匹配 $n',
            bvid: 'BV${n.toString().padLeft(10, '0')}',
          ),
      ],
      hasMore: page == 1,
      favoriteFolderId: '42',
    );
  }

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    if (query.folderId == null && query.section != '默认收藏夹') {
      return HomePage([
        HomeEntry(
          id: '42',
          kind: collection ? HomeEntryKind.collection : HomeEntryKind.folder,
          title: '测试收藏夹',
        ),
      ], hasMore: false);
    }
    pages.add(page);
    if (query.folderId != null) folderIds.add(query.folderId);
    lastCancellation = cancellation;
    if (pending != null) return pending!.future;
    final videos = [
      for (var n = 1; n <= totalVideos; n++)
        if (!removed.contains('$n'))
          HomeEntry(
            id: '$n',
            aid: '$n',
            kind: HomeEntryKind.video,
            title: '视频 $n',
            bvid: 'BV${n.toString().padLeft(10, '0')}',
          ),
    ];
    return HomePage(
      [
        if (page == 1)
          const HomeEntry(
            id: 'invalid',
            title: '失效视频',
            kind: HomeEntryKind.video,
          ),
        ...videos.skip((page - 1) * 24).take(24),
      ],
      hasMore: page * 24 < videos.length,
      favoriteFolderId: '42',
    );
  }

  @override
  Future<void> removeFavorite(
    HomeEntry entry, {
    required String folderId,
    required String scope,
    required RequestCancellation cancellation,
  }) async {
    removed.add(entry.id);
  }

  @override
  Future<void> deleteFavoriteFolder(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) async => throw UnimplementedError();
}
