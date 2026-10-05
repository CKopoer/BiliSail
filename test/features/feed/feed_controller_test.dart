import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/page_result.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/feed/application/feed_controller.dart';
import 'package:bilisail/features/feed/domain/feed_repository.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'channel change cancels old read and discards its completed response',
    () async {
      final repository = _DelayedRepository();
      final container = ProviderContainer(
        overrides: [feedRepositoryProvider.overrideWithValue(repository)],
      );
      addTearDown(container.dispose);
      final controller = container.read(feedControllerProvider.notifier);
      final oldRead = controller.selectChannel(HomeChannel.recommended);
      await controller.selectChannel(HomeChannel.popular);
      expect(repository.oldCancellation.isCancelled, isTrue);
      repository.oldResponse.complete(_page('旧推荐'));
      await oldRead;
      final state = container.read(feedControllerProvider);
      expect(state.channel, HomeChannel.popular);
      expect(state.items.requireValue.single.title, '新热门');
    },
  );
  test('stable video IDs deduplicate the first page and later pages', () async {
    final (container, repository, controller) = _setup();
    final refresh = controller.refresh();
    repository.calls.single.result.complete(
      _videos(['1', '1', '2'], hasMore: true),
    );
    await refresh;
    expect(_ids(container), ['1', '2']);
    final more = controller.loadMore();
    repository.calls.last.result.complete(
      PageResult(
        items: [
          _video('2', title: '更新'),
          _video('3'),
          _video('3'),
        ],
        hasMore: false,
      ),
    );
    await more;
    expect(_ids(container), ['1', '2', '3']);
    expect(
      container.read(feedControllerProvider).items.requireValue[1].title,
      '更新',
    );
  });
  test('concurrent load-more calls share one request', () async {
    final (container, repository, controller) = _setup();
    await _refresh(controller, repository, _videos(['1'], hasMore: true));
    final pending = controller.loadMore();
    final duplicate = controller.loadMore();
    expect(repository.calls.length, 2);
    expect(container.read(feedControllerProvider).loadingMore, isTrue);
    repository.calls.last.result.complete(_videos(['2'], hasMore: true));
    await Future.wait([pending, duplicate]);
    expect(_ids(container), ['1', '2']);
  });
  test('failed page waits for explicit retry at the same page', () async {
    final (container, repository, controller) = _setup();
    await _refresh(controller, repository, _videos(['1'], hasMore: true));
    final failure = const AppFailure(AppFailureKind.network, '下一页失败');
    final pending = controller.loadMore();
    repository.calls.last.result.completeError(failure);
    await pending;
    expect(repository.calls.length, 2);
    expect(_ids(container), ['1']);
    expect(container.read(feedControllerProvider).pageError, same(failure));
    expect(container.read(feedControllerProvider).loadingMore, isFalse);
    final retry = controller.loadMore();
    expect(repository.calls.last.page, 2);
    expect(container.read(feedControllerProvider).pageError, isNull);
    repository.calls.last.result.complete(_videos(['2'], hasMore: false));
    await retry;
    expect(_ids(container), ['1', '2']);
  });
  test(
    'overlapping recommendations have a bounded scan and manual continuation',
    () async {
      final (container, repository, controller) = _setup();
      await _refresh(controller, repository, _videos(['1'], hasMore: true));
      await _more(controller, repository, _videos(['1'], hasMore: true));
      expect(container.read(feedControllerProvider).pageError, isNull);
      await _more(controller, repository, _videos([], hasMore: true));
      var state = container.read(feedControllerProvider);
      expect(state.hasMore, isTrue);
      expect(state.pageError, isA<AppFailure>());
      expect((state.pageError as AppFailure).kind, AppFailureKind.protocol);
      expect(_ids(container), ['1']);
      // The view stops automatic calls on pageError; an explicit retry gets
      // another bounded scan while preserving the server's page progression.
      final retry = controller.loadMore();
      expect(repository.calls.last.page, 4);
      repository.calls.last.result.complete(_videos(['1'], hasMore: true));
      await retry;
      expect(container.read(feedControllerProvider).pageError, isNull);
      await _more(controller, repository, _videos(['2'], hasMore: true));
      await _more(controller, repository, _videos([], hasMore: true));
      expect(container.read(feedControllerProvider).pageError, isNull);
      await _more(controller, repository, _videos([], hasMore: false));
      state = container.read(feedControllerProvider);
      expect(state.hasMore, isFalse);
      expect(state.pageError, isNull);
      final calls = repository.calls.length;
      await controller.loadMore();
      expect(repository.calls.length, calls);
    },
  );
  test(
    'refresh resets a stalled scan and discards an old pagination response',
    () async {
      final (container, repository, controller) = _setup();
      await _refresh(controller, repository, _videos(['1'], hasMore: true));
      await _more(controller, repository, _videos([], hasMore: true));
      await _more(controller, repository, _videos([], hasMore: true));
      expect(container.read(feedControllerProvider).pageError, isNotNull);
      final oldMore = controller.loadMore();
      final oldCall = repository.calls.last;
      await _refresh(controller, repository, _videos(['2'], hasMore: true));
      expect(oldCall.cancellation.isCancelled, isTrue);
      oldCall.result.complete(_videos(['旧响应'], hasMore: false));
      await oldMore;
      expect(_ids(container), ['2']);
      await _more(controller, repository, _videos([], hasMore: true));
      expect(container.read(feedControllerProvider).pageError, isNull);
    },
  );
  test('category change isolates the pending page and its error', () async {
    final (container, repository, controller) = _setup();
    final select = controller.selectChannel(HomeChannel.categories);
    expect(repository.calls.last.categoryId, '1');
    repository.calls.last.result.complete(_videos(['1'], hasMore: true));
    await select;
    final oldMore = controller.loadMore();
    final oldCall = repository.calls.last;
    final newCategory = controller.selectCategory('3');
    expect(oldCall.cancellation.isCancelled, isTrue);
    expect(repository.calls.last.categoryId, '3');
    expect(repository.calls.last.page, 1);
    repository.calls.last.result.complete(_videos(['3'], hasMore: true));
    await newCategory;
    oldCall.result.completeError(
      const AppFailure(AppFailureKind.network, '旧请求失败'),
    );
    await oldMore;
    expect(_ids(container), ['3']);
    expect(container.read(feedControllerProvider).pageError, isNull);
  });
  test('restored channels retain their pagination safety budget', () async {
    final (container, repository, controller) = _setup();
    await _refresh(controller, repository, _videos(['1'], hasMore: true));
    await _more(controller, repository, _videos([], hasMore: true));
    final popular = controller.selectPopular();
    expect(repository.calls.last.popular, isTrue);
    repository.calls.last.result.complete(_videos(['热门'], hasMore: false));
    await popular;
    final calls = repository.calls.length;
    await controller.selectRecommended();
    expect(repository.calls.length, calls);
    await _more(controller, repository, _videos([], hasMore: true));
    expect(repository.calls.last.page, 3);
    expect(container.read(feedControllerProvider).pageError, isNotNull);
  });
  test(
    'account-scope provider invalidation cancels and ignores the old feed',
    () async {
      final (container, repository, controller) = _setup();
      final oldRead = controller.refresh();
      final oldCall = repository.calls.single;
      // The workspace invalidates this provider when its account scope changes.
      container.invalidate(feedControllerProvider);
      final next = container.read(feedControllerProvider.notifier);
      await _refresh(next, repository, _videos(['新账号'], hasMore: false));
      expect(oldCall.cancellation.isCancelled, isTrue);
      oldCall.result.complete(_videos(['旧账号'], hasMore: true));
      await oldRead;
      expect(_ids(container), ['新账号']);
    },
  );
}

(ProviderContainer, _Repository, FeedController) _setup() {
  final repository = _Repository();
  final container = ProviderContainer(
    overrides: [feedRepositoryProvider.overrideWithValue(repository)],
  );
  addTearDown(container.dispose);
  return (
    container,
    repository,
    container.read(feedControllerProvider.notifier),
  );
}

List<String> _ids(ProviderContainer container) => container
    .read(feedControllerProvider)
    .items
    .requireValue
    .map((item) => item.id.value)
    .toList();

VideoSummary _video(String id, {String? title}) => VideoSummary(
  id: VideoId(id),
  title: title ?? id,
  coverUrl: '',
  author: 'UP',
  duration: Duration.zero,
);

PageResult<VideoSummary> _videos(List<String> ids, {required bool hasMore}) =>
    PageResult(items: ids.map(_video).toList(), hasMore: hasMore);

Future<void> _refresh(
  FeedController controller,
  _Repository repository,
  PageResult<VideoSummary> result,
) async {
  final pending = controller.refresh();
  repository.calls.last.result.complete(result);
  await pending;
}

Future<void> _more(
  FeedController controller,
  _Repository repository,
  PageResult<VideoSummary> result,
) async {
  final pending = controller.loadMore();
  repository.calls.last.result.complete(result);
  await pending;
}

final class _Repository implements FeedRepository {
  final List<
    ({
      int page,
      String? categoryId,
      bool popular,
      RequestCancellation cancellation,
      Completer<PageResult<VideoSummary>> result,
    })
  >
  calls = [];
  Future<PageResult<VideoSummary>> _load(
    int page,
    String? categoryId,
    bool popular,
    RequestCancellation cancellation,
  ) {
    final result = Completer<PageResult<VideoSummary>>();
    calls.add((
      page: page,
      categoryId: categoryId,
      popular: popular,
      cancellation: cancellation,
      result: result,
    ));
    return result.future;
  }

  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) => _load(page, categoryId, false, cancellation);
  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) => _load(page, null, true, cancellation);
}

PageResult<VideoSummary> _page(String title) => PageResult(
  items: [
    VideoSummary(
      id: const VideoId('BV1234567890'),
      title: title,
      coverUrl: '',
      author: 'UP',
      duration: Duration.zero,
    ),
  ],
  hasMore: false,
);

final class _DelayedRepository implements FeedRepository {
  final oldResponse = Completer<PageResult<VideoSummary>>();
  late RequestCancellation oldCancellation;
  @override
  Future<List<VideoCategory>> loadCategories({
    required RequestCancellation cancellation,
  }) async => [];
  @override
  Future<PageResult<VideoSummary>> loadFeed({
    required int page,
    required String? categoryId,
    required RequestCancellation cancellation,
  }) {
    oldCancellation = cancellation;
    return oldResponse.future;
  }

  @override
  Future<PageResult<VideoSummary>> loadPopular({
    required int page,
    required RequestCancellation cancellation,
  }) async => _page('新热门');
}
