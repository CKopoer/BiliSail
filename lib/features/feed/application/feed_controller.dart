import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/page_result.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../video/domain/video_actions_repository.dart';
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
    this.rejecting = const {},
    this.rejected = const {},
    this.uncertainRestorations = const {},
  });

  final AsyncValue<List<VideoSummary>> items;
  final String? categoryId;
  final HomeChannel channel;
  bool get popular => channel == HomeChannel.popular;
  final bool hasMore;
  final bool loadingMore;
  final Object? pageError;
  final Set<VideoId> rejecting;
  final Set<VideoId> rejected;
  final Set<VideoId> uncertainRestorations;

  FeedState copyWith({
    AsyncValue<List<VideoSummary>>? items,
    String? categoryId,
    bool clearCategory = false,
    HomeChannel? channel,
    bool? hasMore,
    bool? loadingMore,
    Object? pageError,
    bool clearPageError = false,
    Set<VideoId>? rejecting,
    Set<VideoId>? rejected,
    Set<VideoId>? uncertainRestorations,
  }) => FeedState(
    items: items ?? this.items,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    channel: channel ?? this.channel,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    pageError: clearPageError ? null : pageError ?? this.pageError,
    rejecting: rejecting ?? this.rejecting,
    rejected: rejected ?? this.rejected,
    uncertainRestorations: uncertainRestorations ?? this.uncertainRestorations,
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
  final _rejectWrites = <VideoId, RequestCancellation>{};
  // Undo uses the exact context that was accepted, even after a refresh.
  final _rejected = <VideoId, RecommendationFeedback>{};
  final _uncertainRejections = <VideoId>{};
  final _uncertainRestorations = <VideoId>{};

  /// Keep cached content visible during the widget's deferred channel change.
  /// A temporary short loading page would clamp the restored scroll offset.
  FeedState stateForChannel(HomeChannel channel) => _withFeedback(
    state.channel == channel
        ? state
        : _savedChannels[channel]?.$1 ?? FeedState(channel: channel),
  );

  FeedState _withFeedback(FeedState value) => value.copyWith(
    rejecting: Set.unmodifiable(_rejectWrites.keys),
    rejected: value.channel == HomeChannel.recommended
        ? Set.unmodifiable(_rejected.keys)
        : const {},
    uncertainRestorations: value.channel == HomeChannel.recommended
        ? Set.unmodifiable(_uncertainRestorations)
        : const {},
  );

  @override
  FeedState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
      for (final token in _rejectWrites.values) {
        token.cancel();
      }
    });
    return const FeedState();
  }

  Future<void> selectRecommended() async {
    await selectChannel(HomeChannel.recommended);
  }

  Future<bool> rejectRecommendation(VideoSummary video) async {
    if (!ref.mounted ||
        state.channel != HomeChannel.recommended ||
        state.items.asData?.value.any((item) => item.id == video.id) != true ||
        _rejectWrites.containsKey(video.id) ||
        _rejected.containsKey(video.id)) {
      return false;
    }
    if (_uncertainRejections.contains(video.id)) {
      throw const UnknownWriteOutcome();
    }
    final repository = ref.read(feedRepositoryProvider);
    final feedback = video.recommendationFeedback;
    if (repository is! RecommendationFeedbackRepository || feedback == null) {
      throw const AppFailure(AppFailureKind.protocol, '此推荐暂不支持反馈，请刷新后重试');
    }
    if (_rejected.length + _uncertainRejections.length >= 500) {
      throw const AppFailure(AppFailureKind.protocol, '本次浏览的反馈操作已达上限');
    }
    return _submitFeedback(video.id, feedback, undo: false);
  }

  Future<bool> undoRecommendationFeedback(VideoId id) async {
    if (!ref.mounted ||
        state.channel != HomeChannel.recommended ||
        _rejectWrites.containsKey(id)) {
      return false;
    }
    final feedback = _rejected[id];
    if (feedback == null) return false;
    if (_uncertainRestorations.contains(id)) {
      throw const UnknownWriteOutcome();
    }
    return _submitFeedback(id, feedback, undo: true);
  }

  Future<bool> _submitFeedback(
    VideoId id,
    RecommendationFeedback feedback, {
    required bool undo,
  }) async {
    final repository = ref.read(feedRepositoryProvider);
    if (repository is! RecommendationFeedbackRepository) {
      throw const AppFailure(AppFailureKind.protocol, '当前无法提交推荐反馈');
    }
    if (_rejectWrites.length >= 8) {
      throw const AppFailure(AppFailureKind.protocol, '推荐反馈操作较多，请稍后重试');
    }
    final capability = repository as RecommendationFeedbackRepository;
    final scope = capability.feedbackScope;
    final token = RequestCancellation();
    bool current() =>
        ref.mounted && !token.isCancelled && capability.feedbackScope == scope;
    _rejectWrites[id] = token;
    state = _withFeedback(state);
    try {
      if (undo) {
        await capability.undoRecommendationFeedback(
          feedback,
          cancellation: token,
        );
      } else {
        await capability.rejectRecommendation(feedback, cancellation: token);
      }
      if (!current()) return false;
      if (undo) {
        _rejected.remove(id);
      } else {
        _rejected[id] = feedback;
      }
      state = _withFeedback(state);
      return true;
    } on UnknownWriteOutcome {
      if (!current()) return false;
      (undo ? _uncertainRestorations : _uncertainRejections).add(id);
      rethrow;
    } on AppFailure catch (failure) {
      if (!current() || failure.kind == AppFailureKind.cancelled) return false;
      rethrow;
    } finally {
      _rejectWrites.remove(id);
      if (ref.mounted) {
        state = _withFeedback(state);
      }
    }
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
      state = _withFeedback(saved.$1);
      _page = saved.$2;
      _pagesWithoutNewItems = saved.$3;
      return;
    }
    state = _withFeedback(
      FeedState(
        channel: channel,
        categoryId: channel == HomeChannel.categories
            ? '1'
            : channel == HomeChannel.ranking
            ? '0'
            : null,
      ),
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
      final latest = state.items.asData?.value ?? current;
      final items = _mergeItems(latest, result.items);
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
