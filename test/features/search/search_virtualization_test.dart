import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/live/domain/live_room.dart';
import 'package:bilisail/features/pgc/domain/pgc_repository.dart';
import 'package:bilisail/features/search/application/search_controller.dart';
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
import 'package:bilisail/features/search/presentation/search_screen.dart';
import 'package:bilisail/features/search/presentation/search_results.dart';
import 'package:bilisail/shared/ui/video_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (name, unavailable)
      in <(String, SearchState Function(SearchState))>[
        ('empty query', (_) => const SearchState()),
        (
          'whole-page loading',
          (state) => state.copyWith(items: const AsyncLoading()),
        ),
        (
          'whole-page error',
          (state) => state.copyWith(
            items: AsyncError(
              const AppFailure(AppFailureKind.network, '搜索失败'),
              StackTrace.empty,
            ),
          ),
        ),
        ('empty data', (state) => state.copyWith(items: const AsyncData([]))),
        (
          'changed query loading',
          (state) =>
              state.copyWith(query: '另一个查询', items: const AsyncLoading()),
        ),
        (
          'changed category loading',
          (state) => state.copyWith(
            category: SearchCategory.user,
            items: const AsyncLoading(),
          ),
        ),
      ]) {
    testWidgets(
      '$name releases the previous result widget even if the same data later returns',
      (tester) async {
        final container = ProviderContainer(
          overrides: [
            searchRepositoryProvider.overrideWithValue(_Repository()),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: SearchScreen(query: '条目')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final initial = container.read(searchControllerProvider);
        final previousWidget = tester.widget<SearchResults>(
          find.byType(SearchResults),
        );
        final controller = container.read(searchControllerProvider.notifier);
        void show(SearchState state) {
          // Inject presentation states with identical items to detect retained UI
          // memo references independently of controller list-copying behavior.
          // ignore: invalid_use_of_protected_member
          controller.state = state;
        }

        show(unavailable(initial));
        await tester.pump();
        expect(find.byType(SearchResults), findsNothing);
        show(initial);
        await tester.pumpAndSettle();
        expect(
          tester.widget<SearchResults>(find.byType(SearchResults)),
          isNot(same(previousWidget)),
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  for (final category in SearchCategory.values) {
    testWidgets(
      '$category keeps mounted search results bounded while scrolling',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer(
          overrides: [
            searchRepositoryProvider.overrideWithValue(_Repository()),
          ],
        );
        addTearDown(container.dispose);
        await container
            .read(searchControllerProvider.notifier)
            .selectCategory(category);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(body: SearchScreen(query: '条目')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final titles = find.textContaining(
          RegExp(r'条目[0-9]+'),
          findRichText: true,
        );
        expect(titles.evaluate().length, inExclusiveRange(0, 35));
        expect(find.text('条目499', findRichText: true), findsNothing);
        final scroll = tester
            .widget<CustomScrollView>(find.byType(CustomScrollView))
            .controller!;
        final firstTitle = titles.evaluate().first.widget;
        scroll.jumpTo(1);
        await tester.pumpAndSettle();
        expect(
          titles.evaluate().any(
            (element) => identical(element.widget, firstTitle),
          ),
          isTrue,
        );
        scroll.jumpTo(2500);
        await tester.pumpAndSettle();
        expect(titles.evaluate().length, inExclusiveRange(0, 35));
        expect(find.text('条目0', findRichText: true), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }

  testWidgets(
    'paging status preserves cards and offset, then retry appends results',
    (tester) async {
      final repository = _PagingRepository();
      final container = ProviderContainer(
        overrides: [searchRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: SearchScreen(query: '条目')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final controller = container.read(searchControllerProvider.notifier);
      final scroll = tester
          .widget<CustomScrollView>(find.byType(CustomScrollView))
          .controller!;
      scroll.jumpTo(400);
      await tester.pumpAndSettle();
      final firstCard = tester.widget<VideoCard>(find.byType(VideoCard).first);
      final pending = controller.loadMore();
      await tester.pump();
      expect(
        tester.widget<VideoCard>(find.byType(VideoCard).first),
        same(firstCard),
      );
      expect(scroll.offset, 400);
      repository.nextPage.completeError(
        const AppFailure(AppFailureKind.network, '分页失败'),
      );
      await pending;
      await tester.pumpAndSettle();
      expect(
        container.read(searchControllerProvider).pageError,
        isA<AppFailure>(),
      );
      expect(
        tester.widget<VideoCard>(find.byType(VideoCard).first),
        same(firstCard),
      );
      expect(scroll.offset, 400);
      for (var attempt = 0; attempt < 3; attempt++) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(find.text('分页失败'), findsOneWidget);
      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(
        container.read(searchControllerProvider).items.asData!.value.length,
        106,
      );
      expect(find.text('分页失败'), findsNothing);
      for (var attempt = 0; attempt < 3; attempt++) {
        scroll.jumpTo(scroll.position.maxScrollExtent);
        await tester.pumpAndSettle();
      }
      expect(find.text('条目105', findRichText: true), findsOneWidget);
      expect(find.byType(VideoCard).evaluate().length, lessThan(20));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}

final class _PagingRepository implements SearchRepository {
  final nextPage = Completer<SearchPage>();
  int pageTwoRequests = 0;
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) async {
    if (page == 1) {
      return SearchPage(
        items: [
          for (var index = 0; index < 100; index++)
            _entry(SearchCategory.video, index),
        ],
        hasMore: true,
      );
    }
    if (pageTwoRequests++ == 0) return nextPage.future;
    return SearchPage(
      items: [
        for (var index = 100; index < 106; index++)
          _entry(SearchCategory.video, index),
      ],
      hasMore: false,
    );
  }
}

final class _Repository implements SearchRepository {
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) async => SearchPage(
    items: [for (var index = 0; index < 500; index++) _entry(category, index)],
    hasMore: false,
  );
}

SearchEntry _entry(SearchCategory category, int index) => switch (category) {
  SearchCategory.all || SearchCategory.video => SearchVideoEntry(
    VideoSummary(
      id: VideoId('BV${index.toString().padLeft(10, '0')}'),
      title: '条目$index',
      coverUrl: '',
      author: '作者',
      duration: const Duration(minutes: 1),
    ),
  ),
  SearchCategory.user => SearchUserEntry(
    id: UserId('$index'),
    name: '条目$index',
  ),
  SearchCategory.article => SearchArticleEntry(
    id: ArticleId('$index'),
    title: '条目$index',
  ),
  SearchCategory.live => SearchLiveEntry(
    id: RoomId('$index'),
    title: '条目$index',
    author: '作者',
  ),
  SearchCategory.bangumi || SearchCategory.film => SearchMediaEntry(
    id: PgcSeasonId('$index'),
    title: '条目$index',
    category: category,
    description: '影视说明',
  ),
};
