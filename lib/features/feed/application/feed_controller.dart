import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/page_result.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../domain/feed_repository.dart';
import '../domain/home_channel.dart';

final feedRepositoryProvider = Provider<FeedRepository>(
  (ref) => throw UnimplementedError('FeedRepository must be provided by app'),
);

final feedCategoriesProvider = FutureProvider<List<VideoCategory>>((ref) {
  final cancellation = RequestCancellation();
  ref.onDispose(cancellation.cancel);
  return ref
      .read(feedRepositoryProvider)
      .loadCategories(cancellation: cancellation);
});

final rankingCategoriesProvider = FutureProvider<List<VideoCategory>>((ref) {
  final cancellation = RequestCancellation();
  ref.onDispose(cancellation.cancel);
  final repository = ref.read(feedRepositoryProvider);
  if (repository is! RankingFeedRepository) {
    throw const AppFailure(AppFailureKind.protocol, '排行榜服务暂不可用');
  }
  return (repository as RankingFeedRepository).loadRankingCategories(
    cancellation: cancellation,
  );
});

final feedControllerProvider = NotifierProvider<FeedController, FeedState>(
  FeedController.new,
);

final class FeedState {
  const FeedState({
    this.items = const AsyncLoading(),
    this.categoryId,
    this.channel = HomeChannel.recommended,
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
  });

  final AsyncValue<List<VideoSummary>> items;
  final String? categoryId;
  final HomeChannel channel;
  bool get popular => channel == HomeChannel.popular;
  final bool hasMore;
  final bool loadingMore;
  final Object? pageError;

  FeedState copyWith({
    AsyncValue<List<VideoSummary>>? items,
    String? categoryId,
    bool clearCategory = false,
    HomeChannel? channel,
    bool? hasMore,
    bool? loadingMore,
    Object? pageError,
    bool clearPageError = false,
  }) => FeedState(
    items: items ?? this.items,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    channel: channel ?? this.channel,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    pageError: clearPageError ? null : pageError ?? this.pageError,
  );
}

final class FeedController extends Notifier<FeedState> {
  // Recommendations can repeat a sample; one overlapping page is not an end.
  static const _maxPagesWithoutNewItems = 2;
  int _generation = 0;
  int _page = 0;
  int _pagesWithoutNewItems = 0;
  RequestCancellation? _cancellation;
  final Map<HomeChannel, (FeedState, int, int)> _savedChannels = {};

  /// Keep cached content visible during the widget's deferred channel change.
  /// A temporary short loading page would clamp the restored scroll offset.
  FeedState stateForChannel(HomeChannel channel) => state.channel == channel
      ? state
      : _savedChannels[channel]?.$1 ?? FeedState(channel: channel);

  @override
  FeedState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
    });
    return const FeedState();
  }

  Future<void> selectRecommended() async {
    await selectChannel(HomeChannel.recommended);
  }

  Future<void> selectPopular() async {
    await selectChannel(HomeChannel.popular);
  }

  Future<void> selectChannel(HomeChannel channel) async {
    if (state.channel == channel) {
      if (_page == 0 && state.items.isLoading) await refresh();
      return;
    }
    _savedChannels[state.channel] = (
      state.copyWith(loadingMore: false),
      _page,
      _pagesWithoutNewItems,
    );
    _generation++;
    _cancellation?.cancel();
    _cancellation = RequestCancellation();
    final saved = _savedChannels[channel];
    if (saved != null && !saved.$1.items.isLoading) {
      state = saved.$1;
      _page = saved.$2;
      _pagesWithoutNewItems = saved.$3;
      return;
    }
    state = FeedState(
      channel: channel,
      categoryId: channel == HomeChannel.categories
          ? '1'
          : channel == HomeChannel.ranking
          ? '0'
          : null,
    );
    await refresh();
  }

  Future<void> selectCategory(String id) async {
    if (state.categoryId == id) return;
    state = state.copyWith(categoryId: id);
    await refresh();
  }

  Future<void> refresh() async {
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    _page = 0;
    _pagesWithoutNewItems = 0;
    state = state.copyWith(
      items: const AsyncLoading(),
      hasMore: false,
      loadingMore: false,
      clearPageError: true,
    );
    if (!state.channel.hasVideoFeed) {
      state = state.copyWith(items: const AsyncData([]));
      return;
    }
    try {
      final result = await _loadPage(1, cancellation);
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled) {
        return;
      }
      final items = _mergeItems(const [], result.items);
      _page = 1;
      _pagesWithoutNewItems = items.isEmpty ? 1 : 0;
      state = state.copyWith(items: AsyncData(items), hasMore: result.hasMore);
    } catch (error, stackTrace) {
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = state.copyWith(items: AsyncError(error, stackTrace));
    }
  }

  Future<void> loadMore() async {
    final current = state.items.asData?.value;
    if (current == null || !state.hasMore || state.loadingMore) return;
    final generation = _generation;
    final cancellation = _cancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    // A page error blocks automatic callers in the view. An explicit retry
    // gets a fresh budget so it can continue through overlapping samples.
    if (state.pageError != null) _pagesWithoutNewItems = 0;
    state = state.copyWith(loadingMore: true, clearPageError: true);
    try {
      final result = await _loadPage(_page + 1, cancellation);
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled) {
        return;
      }
      final items = _mergeItems(current, result.items);
      _pagesWithoutNewItems = items.length == current.length
          ? _pagesWithoutNewItems + 1
          : 0;
      _page++;
      state = state.copyWith(
        items: AsyncData(items),
        hasMore: result.hasMore,
        loadingMore: false,
        pageError:
            result.hasMore && _pagesWithoutNewItems >= _maxPagesWithoutNewItems
            ? const AppFailure(AppFailureKind.protocol, '连续多页没有新视频，可重试继续加载')
            : null,
      );
    } catch (error) {
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = state.copyWith(loadingMore: false, pageError: error);
    }
  }

  List<VideoSummary> _mergeItems(
    List<VideoSummary> current,
    List<VideoSummary> incoming,
  ) {
    final unique = {for (final item in current) item.id: item};
    for (final item in incoming) {
      unique[item.id] = item;
    }
    return List.unmodifiable(unique.values);
  }

  Future<PageResult<VideoSummary>> _loadPage(
    int page,
    RequestCancellation cancellation,
  ) {
    final repository = ref.read(feedRepositoryProvider);
    if (state.channel == HomeChannel.ranking) {
      if (repository is RankingFeedRepository) {
        return (repository as RankingFeedRepository).loadRanking(
          categoryId: state.categoryId ?? '0',
          cancellation: cancellation,
        );
      }
      throw const AppFailure(AppFailureKind.protocol, '排行榜服务暂不可用');
    }
    return state.popular
        ? repository.loadPopular(page: page, cancellation: cancellation)
        : repository.loadFeed(
            page: page,
            categoryId: state.categoryId,
            cancellation: cancellation,
          );
  }
}
