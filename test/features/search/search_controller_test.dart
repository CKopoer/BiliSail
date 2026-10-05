import 'dart:async';

import 'package:bili_lite/domain/app_failure.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/domain/video.dart';
import 'package:bili_lite/features/search/application/search_controller.dart';
import 'package:bili_lite/features/search/domain/search_repository.dart';
import 'package:bili_lite/features/search/domain/search_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  late _DeferredRepository repository;
  late ProviderContainer container;
  late SearchController controller;
  setUp(() {
    repository = _DeferredRepository();
    container = ProviderContainer(
      overrides: [searchRepositoryProvider.overrideWithValue(repository)],
    );
    controller = container.read(searchControllerProvider.notifier);
  });
  tearDown(() => container.dispose());

  test(
    'late response from an older query cannot replace newer results',
    () async {
      final old = controller.search('old');
      final latest = controller.search('new');
      expect(repository.calls.first.cancellation.isCancelled, isTrue);
      repository.complete(1, [_video('new')]);
      await latest;
      repository.complete(0, [_video('old')]);
      await old;
      final state = container.read(searchControllerProvider);
      expect(state.query, 'new');
      expect(
        (state.items.value?.single as SearchVideoEntry).video.title,
        'new',
      );
    },
  );

  test(
    'category switch cancels first-page request and resets unsupported options',
    () async {
      final original = controller.search('query');
      final sorted = controller.selectOrder(SearchOrder.favorites);
      final filtered = controller.selectDuration(SearchDuration.overSixty);
      final users = controller.selectCategory(SearchCategory.user);
      expect(
        repository.calls.take(3).every((call) => call.cancellation.isCancelled),
        isTrue,
      );
      final last = repository.calls.last;
      expect(last.category, SearchCategory.user);
      expect(last.order, SearchOrder.relevance);
      expect(last.duration, SearchDuration.any);
      repository.complete(3, []);
      await users;
      for (var i = 0; i < 3; i++) {
        repository.complete(i, [_video('stale$i')]);
      }
      await Future.wait([original, sorted, filtered]);
      expect(
        container.read(searchControllerProvider).category,
        SearchCategory.user,
      );
      expect(container.read(searchControllerProvider).items.value, isEmpty);
    },
  );

  test(
    'late pagination after order change cannot append old results',
    () async {
      final first = controller.search('query');
      repository.complete(0, [_video('first')], more: true);
      await first;
      final oldPage = controller.loadMore();
      final sorted = controller.selectOrder(SearchOrder.latest);
      expect(repository.calls[1].page, 2);
      expect(repository.calls[1].cancellation.isCancelled, isTrue);
      expect(repository.calls[2].page, 1);
      repository.complete(2, [_video('latest')]);
      await sorted;
      repository.complete(1, [_video('old page')]);
      await oldPage;
      expect(
        (container.read(searchControllerProvider).items.value?.single
                as SearchVideoEntry)
            .video
            .title,
        'latest',
      );
    },
  );

  test(
    'same-query counts survive category changes, new query clears them',
    () async {
      final first = controller.search('query');
      repository.calls[0].completion.complete(
        SearchPage(
          items: [],
          hasMore: false,
          counts: {SearchCategory.video: 120, SearchCategory.user: 3},
        ),
      );
      await first;
      final users = controller.selectCategory(SearchCategory.user);
      expect(
        container.read(searchControllerProvider).counts[SearchCategory.video],
        120,
      );
      repository.calls[1].completion.complete(
        SearchPage(items: [], hasMore: false, counts: {SearchCategory.user: 2}),
      );
      await users;
      expect(
        container.read(searchControllerProvider).counts[SearchCategory.user],
        2,
      );
      final next = controller.search('other');
      expect(container.read(searchControllerProvider).counts, isEmpty);
      repository.complete(2, []);
      await next;
    },
  );

  test(
    'failed page retry keeps options and repeated page stops pagination',
    () async {
      final first = controller.search('query');
      repository.complete(0, [_video('one')], more: true);
      await first;
      final page = controller.loadMore();
      repository.calls[1].completion.completeError(
        const AppFailure(AppFailureKind.network, 'offline'),
      );
      await page;
      expect(
        container.read(searchControllerProvider).pageError,
        isA<AppFailure>(),
      );
      final retry = controller.loadMore();
      expect(repository.calls[2].page, 2);
      repository.complete(2, [_video('one')], more: true);
      await retry;
      expect(container.read(searchControllerProvider).hasMore, isFalse);
      expect(container.read(searchControllerProvider).items.value?.length, 1);
    },
  );

  test(
    'user sorting/filtering is forwarded and disposal cancels requests',
    () async {
      final first = controller.search('query');
      repository.complete(0, []);
      await first;
      final users = controller.selectCategory(SearchCategory.user);
      repository.complete(1, []);
      await users;
      final sort = controller.selectOrder(SearchOrder.fansAscending);
      repository.complete(2, []);
      await sort;
      final filter = controller.selectUserType(SearchUserType.uploader);
      expect(repository.calls.last.order, SearchOrder.fansAscending);
      expect(repository.calls.last.userType, SearchUserType.uploader);
      container.dispose();
      expect(repository.calls.last.cancellation.isCancelled, isTrue);
      repository.complete(3, []);
      await filter;
    },
  );

  test('cancelled requests do not show generic errors', () async {
    final operation = controller.search('query');
    repository.calls[0].completion.completeError(
      const AppFailure(AppFailureKind.cancelled, 'cancelled'),
    );
    await operation;
    expect(container.read(searchControllerProvider).items.hasError, isFalse);
  });
}

final class _Call {
  _Call(
    this.query,
    this.page,
    this.category,
    this.order,
    this.duration,
    this.userType,
    this.cancellation,
  );
  final String query;
  final int page;
  final SearchCategory category;
  final SearchOrder order;
  final SearchDuration duration;
  final SearchUserType userType;
  final RequestCancellation cancellation;
  final completion = Completer<SearchPage>();
}

final class _DeferredRepository implements SearchRepository {
  final calls = <_Call>[];
  @override
  Future<SearchPage> search({
    required String query,
    required int page,
    required SearchCategory category,
    required SearchOrder order,
    required SearchDuration duration,
    required SearchUserType userType,
    required RequestCancellation cancellation,
  }) {
    final call = _Call(
      query,
      page,
      category,
      order,
      duration,
      userType,
      cancellation,
    );
    calls.add(call);
    return call.completion.future;
  }

  void complete(int index, List<SearchEntry> items, {bool more = false}) =>
      calls[index].completion.complete(SearchPage(items: items, hasMore: more));
}

SearchVideoEntry _video(String title) => SearchVideoEntry(
  VideoSummary(
    id: VideoId(
      'BV1${title.hashCode.abs().toString().padLeft(9, '0').substring(0, 9)}',
    ),
    title: title,
    coverUrl: '',
    author: 'UP',
    duration: const Duration(minutes: 2),
  ),
);
