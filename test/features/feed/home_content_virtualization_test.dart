import 'dart:async';

import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/feed/application/home_controller.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';
import 'package:bilisail/features/feed/presentation/home_content.dart';
import 'package:bilisail/features/feed/presentation/home_feed_cards.dart';
import 'package:bilisail/features/video/application/watch_later_queue_registry.dart';
import 'package:bilisail/shared/ui/dynamic_post_interactions.dart';
import 'package:bilisail/shared/ui/responsive_card_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

void main() {
  testWidgets(
    'full refresh and sign-out unload cards and reset the body cache',
    (tester) async {
      final repository = _RefreshRepository();
      final container = ProviderContainer(
        overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final provider = homeControllerProvider((
        channel: HomeChannel.favorites,
        section: '默认收藏夹',
        scope: repository.accountScope,
        folderId: null,
      ));
      // Retain the same controller/data through the UI-only login toggle to
      // distinguish clearing the UI cache from a repository refresh.
      final subscription = container.listen(provider, (_, _) {});
      addTearDown(subscription.close);
      final signedIn = ValueNotifier(true);
      addTearDown(signedIn.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: ValueListenableBuilder(
                valueListenable: signedIn,
                builder: (_, value, _) => HomeContent(
                  channel: HomeChannel.favorites,
                  section: '默认收藏夹',
                  isSignedIn: value,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeVideoCard), findsOneWidget);
      final initialBody = tester.widget<SliverResponsiveCardGrid>(
        find.byType(SliverResponsiveCardGrid),
      );
      repository.refreshRead = Completer<HomePage>();
      final refresh = container.read(provider.notifier).refresh();
      await tester.pump();
      expect(container.read(provider).items.isLoading, isTrue);
      expect(find.byType(HomeVideoCard), findsNothing);
      expect(find.byType(SliverResponsiveCardGrid), findsNothing);
      repository.refreshRead!.complete(repository.page);
      await refresh;
      await tester.pumpAndSettle();
      expect(find.byType(HomeVideoCard), findsOneWidget);
      final refreshedBody = tester.widget<SliverResponsiveCardGrid>(
        find.byType(SliverResponsiveCardGrid),
      );
      expect(refreshedBody, isNot(same(initialBody)));
      final retainedItems = container.read(provider).items.requireValue;
      signedIn.value = false;
      await tester.pumpAndSettle();
      expect(find.byType(HomeVideoCard), findsNothing);
      expect(find.byType(SliverResponsiveCardGrid), findsNothing);
      expect(find.text('登录后可查看${HomeChannel.favorites.label}'), findsOneWidget);
      signedIn.value = true;
      await tester.pumpAndSettle();
      expect(container.read(provider).items.requireValue, same(retainedItems));
      expect(find.byType(HomeVideoCard), findsOneWidget);
      expect(
        tester.widget<SliverResponsiveCardGrid>(
          find.byType(SliverResponsiveCardGrid),
        ),
        isNot(same(refreshedBody)),
      );
      expect(repository.calls, 2);
      expect(tester.takeException(), isNull);
    },
  );

  for (final (channel, section) in [
    for (final section in HomeChannel.dynamic.sections)
      (HomeChannel.dynamic, section),
    (HomeChannel.videoDynamic, '最新视频'),
    (HomeChannel.bangumi, '推荐'),
    (HomeChannel.guochuang, '推荐'),
    (HomeChannel.cinema, '推荐'),
    (HomeChannel.live, '我的关注'),
    (HomeChannel.favorites, '默认收藏夹'),
    (HomeChannel.favorites, '我创建的收藏夹'),
    (HomeChannel.favorites, '我的收藏与订阅'),
    for (final section in HomeChannel.watchLater.sections)
      (HomeChannel.watchLater, section),
  ]) {
    testWidgets('$channel/$section mounts only nearby cards while scrolling', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repository = _Repository();
      await tester.pumpWidget(_app(repository, channel, section));
      await tester.pumpAndSettle();

      Finder cards() => channel == HomeChannel.dynamic
          ? find.byType(InteractiveDynamicPostCard)
          : find.byWidgetPredicate(
              (widget) => widget.key is ValueKey<(HomeEntryKind, String)>,
            );
      Map<Key?, Widget> mounted() => {
        for (final element in cards().evaluate())
          element.widget.key: element.widget,
      };
      final initial = mounted();
      expect(initial.length, inInclusiveRange(2, 50));
      final position = _position(tester);
      position.jumpTo(80);
      await tester.pumpAndSettle();
      final nearby = mounted();
      final retained = initial.keys.toSet().intersection(nearby.keys.toSet());
      expect(retained, isNotEmpty);
      for (final key in retained) {
        expect(
          nearby[key],
          same(initial[key]),
          reason: 'scrolling must not replace already mounted cards',
        );
      }

      position.jumpTo(3000);
      await tester.pumpAndSettle();
      final later = mounted();
      expect(later.length, inInclusiveRange(2, 50));
      expect(later.keys.toSet().difference(initial.keys.toSet()), isNotEmpty);
      expect(
        cards().evaluate().any(
          (element) => initial.keys.contains(element.widget.key),
        ),
        isFalse,
      );
      position.jumpTo(0);
      await tester.pumpAndSettle();
      expect(mounted().keys, containsAll(initial.keys));
      expect(repository.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('lazy folder detail restores its parent offset and loaded page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _Repository();
    await tester.pumpWidget(_app(repository, HomeChannel.favorites, '我创建的收藏夹'));
    await tester.pumpAndSettle();
    _position(tester).jumpTo(800);
    await tester.pumpAndSettle();
    final savedOffset = _position(tester).pixels;
    final folder =
        find.byType(FavoriteFolderCard).evaluate().firstWhere((element) {
              final rect = tester.getRect(find.byWidget(element.widget));
              return rect.top >= 0 && rect.bottom <= 600;
            }).widget
            as FavoriteFolderCard;
    await tester.tap(find.byWidget(folder));
    await tester.pumpAndSettle();
    expect(repository.calls.last.folderId, folder.entry.id);
    expect(
      find.byType(HomeVideoCard).evaluate().length,
      inInclusiveRange(2, 50),
    );
    _position(tester).jumpTo(1000);
    await tester.pumpAndSettle();
    _position(tester).jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('返回列表'));
    await tester.pumpAndSettle();
    expect(_position(tester).pixels, closeTo(savedOffset, 1));
    expect(repository.calls, hasLength(2));
    expect(tester.takeException(), isNull);
  });

  for (final channel in [
    HomeChannel.dynamic,
    HomeChannel.videoDynamic,
    HomeChannel.favorites,
    HomeChannel.bangumi,
  ]) {
    testWidgets('$channel pagination status preserves mounted card instances', (
      tester,
    ) async {
      final repository = _Repository(itemCount: 100, hasMore: true);
      final section = channel == HomeChannel.favorites
          ? '默认收藏夹'
          : channel.sections.first;
      await tester.pumpWidget(_app(repository, channel, section));
      await tester.pumpAndSettle();
      final provider = homeControllerProvider((
        channel: channel,
        section: section,
        scope: repository.accountScope,
        folderId: null,
      ));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(HomeContent)),
      );
      final originals = find
          .byWidgetPredicate(
            (widget) =>
                widget is InteractiveDynamicPostCard ||
                widget.key is ValueKey<(HomeEntryKind, String)>,
          )
          .evaluate()
          .map((element) => element.widget)
          .toList();
      expect(originals, isNotEmpty);
      final pending = container.read(provider.notifier).loadMore();
      await tester.pump();
      await tester.pump();
      expect(container.read(provider).loadingMore, isTrue);
      for (final card in originals) {
        expect(find.byWidget(card), findsOneWidget);
      }
      repository.nextPage.completeError(
        const AppFailure(AppFailureKind.network, '下一页失败'),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(container.read(provider).pageError, isA<AppFailure>());
      for (final card in originals) {
        expect(find.byWidget(card), findsOneWidget);
      }
      expect(repository.calls, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'watch-later navigation captures loaded entries outside viewport',
    (tester) async {
      final repository = _Repository();
      final container = ProviderContainer(
        overrides: [
          homeRepositoryProvider.overrideWithValue(repository),
          sessionEpochProvider.overrideWithValue(() => 4),
        ],
      );
      addTearDown(container.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(
              body: HomeContent(
                channel: HomeChannel.watchLater,
                section: '全部',
                isSignedIn: true,
              ),
            ),
          ),
          GoRoute(path: '/video/:bvid', builder: (_, _) => const SizedBox()),
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
      expect(find.text('第199条内容'), findsNothing);
      await tester.tap(find.text('第0条内容'));
      await tester.pumpAndSettle();
      final uri = router.routeInformationProvider.value.uri;
      final queue = container
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            uri.queryParameters['queue'],
            scope: repository.accountScope,
            sessionEpoch: 4,
          );
      expect(queue, isNotNull);
      expect(queue!.items, hasLength(200));
      expect(queue.items.last.video.title, '第199条内容');
      expect(tester.takeException(), isNull);
    },
  );
}

ScrollPosition _position(WidgetTester tester) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.byType(CustomScrollView),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

Widget _app(_Repository repository, HomeChannel channel, String section) =>
    ProviderScope(
      overrides: [homeRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        home: Scaffold(
          body: HomeContent(
            channel: channel,
            section: section,
            isSignedIn: true,
          ),
        ),
      ),
    );

final class _Repository implements HomeRepository {
  _Repository({this.itemCount = 200, this.hasMore = false});
  final int itemCount;
  final bool hasMore;
  final nextPage = Completer<HomePage>();
  final calls = <HomeQuery>[];
  @override
  String get accountScope => 'user:7';

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls.add(query);
    if (page > 1) return nextPage.future;
    final folders =
        query.channel == HomeChannel.favorites &&
        query.folderId == null &&
        query.section != '默认收藏夹';
    return HomePage(
      [
        for (var i = 0; i < itemCount; i++)
          HomeEntry(
            id: '$i',
            title: '第$i条内容',
            authorName: '测试作者',
            subtitle: '内容简介',
            kind: folders
                ? HomeEntryKind.folder
                : switch (query.channel) {
                    HomeChannel.dynamic => HomeEntryKind.dynamic,
                    HomeChannel.live => HomeEntryKind.live,
                    HomeChannel.videoDynamic ||
                    HomeChannel.watchLater ||
                    HomeChannel.favorites => HomeEntryKind.video,
                    _ => HomeEntryKind.season,
                  },
            bvid: 'BV${i.toString().padLeft(10, '0')}',
            dynamicPost: query.channel == HomeChannel.dynamic
                ? DynamicPost(id: '$i', authorName: '测试作者', text: '第$i条动态内容')
                : null,
          ),
      ],
      hasMore: hasMore,
      nextCursor: hasMore ? 'next' : null,
    );
  }
}

final class _RefreshRepository implements HomeRepository {
  final page = const HomePage([
    HomeEntry(
      id: '1',
      title: '缓存生命周期',
      kind: HomeEntryKind.video,
      bvid: 'BV1abc123456',
    ),
  ], hasMore: false);
  Completer<HomePage>? refreshRead;
  int calls = 0;
  @override
  String get accountScope => 'user:7';
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    calls++;
    return refreshRead?.future ?? this.page;
  }
}
