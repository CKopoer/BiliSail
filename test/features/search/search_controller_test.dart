import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/search/application/search_controller.dart';
import 'package:bilisail/features/search/data/api_search_repository.dart';
import 'package:bilisail/features/search/domain/search_repository.dart';
import 'package:bilisail/features/search/domain/search_result.dart';
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
      final filtered = controller.applyFilters(
        category: SearchCategory.all,
        order: SearchOrder.favorites,
        duration: SearchDuration.overSixty,
      );
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

  test('applying video filters reloads once, preserves counts and retries the same page', () async {
    final first = controller.search('query');
    repository.complete(
      0,
      [_video('first')],
      more: true,
      counts: {SearchCategory.video: 100, SearchCategory.user: 4},
    );
    await first;
    final oldPage = controller.loadMore();
    final range = SearchPublicationRange(
      start: DateTime(2026, 1, 30),
      end: DateTime(2026, 2, 2),
    );
    final filtered = controller.applyFilters(
      category: SearchCategory.all,
      order: SearchOrder.comments,
      duration: SearchDuration.overSixty,
      videoZone: SearchVideoZone.technology,
      publicationPeriod: SearchPublicationPeriod.customRange,
      publicationRange: range,
    );
    expect(repository.calls, hasLength(3));
    expect(repository.calls[1].cancellation.isCancelled, isTrue);
    expect(repository.calls[2].page, 1);
    repository.complete(
      2,
      [_video('filtered')],
      more: true,
      counts: {SearchCategory.video: 2},
    );
    repository.complete(1, [_video('late unfiltered page')]);
    await Future.wait([filtered, oldPage]);
    expect(container.read(searchControllerProvider).counts, {
      SearchCategory.video: 100,
      SearchCategory.user: 4,
    });

    final page = controller.loadMore();
    repository.calls[3].completion.completeError(
      const AppFailure(AppFailureKind.network, 'offline'),
    );
    await page;
    final retry = controller.loadMore();
    expect(repository.calls.map((call) => call.page), [1, 2, 1, 2, 2]);
    for (final call in repository.calls.skip(2)) {
      expect(call.category, SearchCategory.all);
      expect(call.order, SearchOrder.comments);
      expect(call.duration, SearchDuration.overSixty);
      expect(call.videoZone, SearchVideoZone.technology);
      expect(call.publicationRange, range);
    }
    repository.complete(4, [_video('filtered page two')]);
    await retry;
    expect(
      container.read(searchControllerProvider).items.requireValue,
      hasLength(2),
    );

    final reset = controller.applyFilters(
      category: SearchCategory.all,
      order: SearchOrder.relevance,
    );
    expect(repository.calls.last.page, 1);
    expect(repository.calls.last.order, SearchOrder.relevance);
    expect(repository.calls.last.videoZone, SearchVideoZone.any);
    expect(repository.calls.last.publicationRange, isNull);
    repository.complete(
      5,
      [_video('mixed page one')],
      counts: {SearchCategory.video: 150, SearchCategory.user: 5},
    );
    await reset;
    final unfiltered = container.read(searchControllerProvider);
    expect(unfiltered.hasFilters, isFalse);
    expect(unfiltered.counts, {
      SearchCategory.video: 150,
      SearchCategory.user: 5,
    });
  });

  test('changing category clears video filters and discards previous category drafts', () async {
    final first = controller.search('query');
    repository.complete(0, []);
    await first;
    final filtered = controller.applyFilters(
      category: SearchCategory.all,
      order: SearchOrder.relevance,
      videoZone: SearchVideoZone.gaming,
      publicationPeriod: SearchPublicationPeriod.week,
    );
    final range = repository.calls[1].publicationRange;
    expect(
      range,
      isA<SearchPublicationRange>().having(
        (range) =>
            range.start ==
            DateTime(range.end.year, range.end.month, range.end.day - 6),
        'seven inclusive calendar days',
        isTrue,
      ),
    );
    final articles = controller.selectCategory(SearchCategory.article);
    final articleRequest = repository.calls[2];
    expect(repository.calls[1].cancellation.isCancelled, isTrue);
    expect(articleRequest.videoZone, SearchVideoZone.any);
    expect(articleRequest.publicationRange, isNull);
    await controller.applyFilters(
      category: SearchCategory.all,
      order: SearchOrder.comments,
      videoZone: SearchVideoZone.technology,
    );
    expect(repository.calls, hasLength(3));
    repository.complete(1, []);
    repository.complete(2, []);
    await Future.wait([filtered, articles]);

    final filterArticles = controller.applyFilters(
      category: SearchCategory.article,
      order: SearchOrder.comments,
      articleZone: SearchArticleZone.notes,
    );
    expect(repository.calls.last.articleZone, SearchArticleZone.notes);
    repository.complete(3, []);
    await filterArticles;
    final users = controller.selectCategory(SearchCategory.user);
    expect(repository.calls.last.articleZone, SearchArticleZone.any);
    expect(repository.calls.last.order, SearchOrder.relevance);
    repository.complete(4, []);
    await users;
  });

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
      final filter = controller.applyFilters(
        category: SearchCategory.user,
        order: SearchOrder.fansAscending,
        userType: SearchUserType.verified,
      );
      expect(repository.calls.last.order, SearchOrder.fansAscending);
      expect(repository.calls.last.userType, SearchUserType.verified);
      container.dispose();
      expect(repository.calls.last.cancellation.isCancelled, isTrue);
      repository.complete(3, []);
      await filter;
    },
  );

  test(
    'real search repository sends inclusive dates and restores mixed results',
    () async {
      final transport = _FilterTransport();
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final provider = ProviderContainer(
        overrides: [
          searchRepositoryProvider.overrideWithValue(
            ApiSearchRepository(api, requests),
          ),
        ],
      );
      addTearDown(provider.dispose);
      final search = provider.read(searchControllerProvider.notifier);
      List<SearchEntry> results() =>
          provider.read(searchControllerProvider).items.requireValue;

      await search.search('query');
      expect(results().whereType<SearchUserEntry>(), hasLength(1));
      await search.applyFilters(
        category: SearchCategory.all,
        order: SearchOrder.comments,
        videoZone: SearchVideoZone.technology,
        publicationPeriod: SearchPublicationPeriod.customRange,
        publicationRange: SearchPublicationRange(
          start: DateTime(2026, 1, 30, 15),
          end: DateTime(2026, 2, 2, 10),
        ),
      );
      expect(results().single, isA<SearchVideoEntry>());
      final request = transport.searches.last;
      expect(request.path, '/x/web-interface/wbi/search/type');
      expect(request.queryParameters, containsPair('tids', '188'));
      expect(request.queryParameters, containsPair('order', 'scores'));
      expect(
        request.queryParameters['pubtime_begin_s'],
        '${DateTime(2026, 1, 30).millisecondsSinceEpoch ~/ 1000}',
      );
      expect(
        request.queryParameters['pubtime_end_s'],
        '${DateTime(2026, 2, 2, 23, 59, 59).millisecondsSinceEpoch ~/ 1000}',
      );

      await search.applyFilters(
        category: SearchCategory.all,
        order: SearchOrder.relevance,
      );
      expect(results().whereType<SearchUserEntry>(), hasLength(1));
      expect(transport.searches, hasLength(5));
      for (final uri in transport.searches.skip(3)) {
        expect(uri.queryParameters['tids'], isNull);
        expect(uri.queryParameters['pubtime_begin_s'], isNull);
        expect(uri.queryParameters['pubtime_end_s'], isNull);
      }
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

final class _FilterTransport implements ApiTransport {
  final searches = <Uri>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (!uri.path.endsWith('/nav')) searches.add(uri);
    final data = switch (uri.path) {
      '/x/web-interface/nav' => {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
        },
      },
      '/x/web-interface/wbi/search/all/v2' => {
        'result': [
          {
            'result_type': 'bili_user',
            'data': [
              {'mid': '123', 'uname': '测试用户'},
            ],
          },
        ],
      },
      '/x/web-interface/wbi/search/type' => {
        'numPages': 1,
        'result': [
          {'type': 'video', 'bvid': 'BV1abc123456', 'title': '测试视频'},
        ],
      },
      _ => throw StateError('Unexpected API endpoint ${uri.path}'),
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}

final class _Call {
  _Call(
    this.query,
    this.page,
    this.category,
    this.order,
    this.duration,
    this.userType,
    this.videoZone,
    this.articleZone,
    this.publicationRange,
    this.cancellation,
  );
  final String query;
  final int page;
  final SearchCategory category;
  final SearchOrder order;
  final SearchDuration duration;
  final SearchUserType userType;
  final SearchVideoZone videoZone;
  final SearchArticleZone articleZone;
  final SearchPublicationRange? publicationRange;
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
    SearchVideoZone videoZone = SearchVideoZone.any,
    SearchArticleZone articleZone = SearchArticleZone.any,
    SearchPublicationRange? publicationRange,
    required RequestCancellation cancellation,
  }) {
    final call = _Call(
      query,
      page,
      category,
      order,
      duration,
      userType,
      videoZone,
      articleZone,
      publicationRange,
      cancellation,
    );
    calls.add(call);
    return call.completion.future;
  }

  void complete(
    int index,
    List<SearchEntry> items, {
    bool more = false,
    Map<SearchCategory, int> counts = const {},
  }) => calls[index].completion.complete(
    SearchPage(items: items, hasMore: more, counts: counts),
  );
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
