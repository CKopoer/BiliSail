import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/page_result.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/recommendation_settings.dart';
import '../../../shared/application/recommendation_filter_provider.dart';
import '../../video/domain/video_actions_repository.dart';
import '../domain/feed_repository.dart';
import '../domain/home_channel.dart';
import '../domain/popular_feed.dart';
import 'filtered_feed_index.dart';
import 'app_recommendation_identity.dart';

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
    this.popularSection = PopularSection.all,
    this.weeklyIssue,
    this.weeklyIssues = const [],
    this.hasMore = false,
    this.loadingMore = false,
    this.refreshing = false,
    this.previousStartIndex,
    this.pageError,
    this.rejecting = const {},
    this.rejected = const {},
    this.uncertainRestorations = const {},
  });

  final AsyncValue<List<VideoSummary>> items;
  final String? categoryId;
  final HomeChannel channel;
  final PopularSection popularSection;
  final int? weeklyIssue;
  final List<PopularWeek> weeklyIssues;
  bool get popular => channel == HomeChannel.popular;
  final bool hasMore;
  final bool loadingMore;
  final bool refreshing;
  final int? previousStartIndex;
  final Object? pageError;
  final Set<VideoId> rejecting;
  final Set<VideoId> rejected;
  final Set<VideoId> uncertainRestorations;

  FeedState copyWith({
    AsyncValue<List<VideoSummary>>? items,
    String? categoryId,
    bool clearCategory = false,
    HomeChannel? channel,
    PopularSection? popularSection,
    int? weeklyIssue,
    bool clearWeeklyIssue = false,
    List<PopularWeek>? weeklyIssues,
    bool? hasMore,
    bool? loadingMore,
    bool? refreshing,
    int? previousStartIndex,
    bool clearPreviousStart = false,
    Object? pageError,
    bool clearPageError = false,
    Set<VideoId>? rejecting,
    Set<VideoId>? rejected,
    Set<VideoId>? uncertainRestorations,
  }) => FeedState(
    items: items ?? this.items,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    channel: channel ?? this.channel,
    popularSection: popularSection ?? this.popularSection,
    weeklyIssue: clearWeeklyIssue ? null : weeklyIssue ?? this.weeklyIssue,
    weeklyIssues: weeklyIssues ?? this.weeklyIssues,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    refreshing: refreshing ?? this.refreshing,
    previousStartIndex: clearPreviousStart
        ? null
        : previousStartIndex ?? this.previousStartIndex,
    pageError: clearPageError ? null : pageError ?? this.pageError,
    rejecting: rejecting ?? this.rejecting,
    rejected: rejected ?? this.rejected,
    uncertainRestorations: uncertainRestorations ?? this.uncertainRestorations,
  );
}

final class FeedController extends Notifier<FeedState> {
  // Recommendations can repeat a sample; one overlapping page is not an end.
  static const _maxPagesWithoutNewItems = 2;
  static const maximumPopularEntries = 500;
  static const maximumCachedWeeks = 6;
  int _generation = 0;
  int _page = 0;
  int _pagesWithoutNewItems = 0;
  RequestCancellation? _cancellation;
  final Map<HomeChannel, (FeedState, int, int)> _savedChannels = {};
  final _itemIndices = <Object, FilteredFeedIndex>{};
  final _unloadedChannels = <HomeChannel, FeedState>{};
  final _savedPopular = <PopularSection, (FeedState, int, int)>{};
  final _unloadedPopular = <PopularSection, FeedState>{};
  final _savedWeeks = <int, (FeedState, int, int)>{};
  List<PopularWeek> _popularWeeks = const [];
  final _rejectWrites = <VideoId, RequestCancellation>{};
  // Undo uses the exact context that was accepted, even after a refresh.
  final _rejected = <VideoId, RecommendationFeedback>{};
  final _uncertainRejections = <VideoId>{};
  final _uncertainRestorations = <VideoId>{};
  ({RecommendationSource source, int identity})? _recommendationKey;
  String _appRecommendationCursor = '0';
  AppRecommendationRequest? _failedAppRefresh;

  /// Keep cached content visible during the widget's deferred channel change.
  /// A temporary short loading page would clamp the restored scroll offset.
  FeedState stateForChannel(HomeChannel channel, {FeedState? current}) {
    // A selector supplies its snapshot: Riverpod forbids reading Notifier.state
    // from a select callback, even when the notifier was captured beforehand.
    final active = current ?? state;
    if (active.channel == channel) return active;
    final saved = _savedChannels[channel];
    if (saved == null) {
      return _unloadedChannels.putIfAbsent(
        channel,
        () => FeedState(channel: channel),
      );
    }
    // Only recommendation cards consume feedback. Derive it when changed,
    // without replacing unrelated channels' pagination/content versions.
    if (channel != HomeChannel.recommended ||
        saved.$1.rejecting.length == _rejectWrites.length &&
            saved.$1.rejecting.containsAll(_rejectWrites.keys) &&
            saved.$1.rejected.length == _rejected.length &&
            saved.$1.rejected.containsAll(_rejected.keys) &&
            saved.$1.uncertainRestorations.length ==
                _uncertainRestorations.length &&
            saved.$1.uncertainRestorations.containsAll(
              _uncertainRestorations,
            )) {
      return saved.$1;
    }
    final updated = _withFeedback(saved.$1);
    _savedChannels[channel] = (updated, saved.$2, saved.$3);
    return updated;
  }

  FeedState stateForPopularSection(
    PopularSection section, {
    required FeedState current,
  }) {
    if (current.popular && current.popularSection == section) return current;
    return _savedPopular[section]?.$1 ??
        _unloadedPopular.putIfAbsent(
          section,
          () =>
              FeedState(channel: HomeChannel.popular, popularSection: section),
        );
  }

  Object _indexKey(FeedState value) => value.popular
      ? (value.channel, value.popularSection, value.weeklyIssue)
      : value.channel;

  void _saveCurrent() {
    final snapshot = (
      state.copyWith(loadingMore: false, refreshing: false),
      _page,
      _pagesWithoutNewItems,
    );
    _savedChannels[state.channel] = snapshot;
    if (!state.popular) return;
    _savedPopular[state.popularSection] = snapshot;
    final week = state.weeklyIssue;
    if (state.popularSection == PopularSection.weekly &&
        week != null &&
        state.items.asData != null) {
      _savedWeeks.remove(week);
      _savedWeeks[week] = snapshot;
      while (_savedWeeks.length > maximumCachedWeeks) {
        final oldest = _savedWeeks.keys.first;
        _savedWeeks.remove(oldest);
        _itemIndices.remove((
          HomeChannel.popular,
          PopularSection.weekly,
          oldest,
        ));
      }
    }
  }

  FeedState _withFeedback(FeedState value) => value.copyWith(
    rejecting: value.channel == HomeChannel.recommended
        ? Set.unmodifiable(_rejectWrites.keys)
        : const {},
    rejected: value.channel == HomeChannel.recommended
        ? Set.unmodifiable(_rejected.keys)
        : const {},
    uncertainRestorations: value.channel == HomeChannel.recommended
        ? Set.unmodifiable(_uncertainRestorations)
        : const {},
  );

  @override
  FeedState build() {
    _recommendationKey = ref.read(recommendationQueryKeyProvider);
    ref.listen(recommendationQueryKeyProvider, (_, next) {
      if (_recommendationKey == next) return;
      final identityChanged =
          next.source == RecommendationSource.app &&
          _recommendationKey?.source == next.source;
      _recommendationKey = next;
      _appRecommendationCursor = '0';
      _failedAppRefresh = null;
      _savedChannels.remove(HomeChannel.recommended);
      _unloadedChannels.remove(HomeChannel.recommended);
      _itemIndices.remove(HomeChannel.recommended);
      for (final token in _rejectWrites.values) {
        token.cancel();
      }
      _rejectWrites.clear();
      _rejected.clear();
      _uncertainRejections.clear();
      _uncertainRestorations.clear();
      if (state.channel == HomeChannel.recommended) {
        _generation++;
        _cancellation?.cancel();
        _page = 0;
        _pagesWithoutNewItems = 0;
        state = const FeedState();
        unawaited(
          refresh(
            appReason: identityChanged
                ? AppRecommendationLoadReason.identityChanged
                : AppRecommendationLoadReason.initial,
          ),
        );
      } else {
        // Notify retained recommendation selectors without replacing other data.
        state = state.copyWith();
      }
    });
    ref.listen(
      recommendationFilterProvider,
      (_, filter) => _applyPreferences(filter),
    );
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
      for (final token in _rejectWrites.values) {
        token.cancel();
      }
      _savedChannels.clear();
      _itemIndices.clear();
      _unloadedChannels.clear();
      _savedPopular.clear();
      _unloadedPopular.clear();
      _savedWeeks.clear();
      _popularWeeks = const [];
      _rejectWrites.clear();
      _rejected.clear();
      _uncertainRejections.clear();
      _uncertainRestorations.clear();
      _page = 0;
      _pagesWithoutNewItems = 0;
      _cancellation = null;
      _appRecommendationCursor = '0';
      _failedAppRefresh = null;
    });
    return const FeedState();
  }

  RecommendationSurface _surface(FeedState value) =>
      value.channel == HomeChannel.recommended
      ? RecommendationSurface.recommended
      : RecommendationSurface.discovery;

  int? _previousStart(FilteredFeedIndex index) {
    final settings = ref.read(recommendationSettingsProvider);
    return settings.keepPrevious && settings.showPreviousMarker
        ? index.previousStartIndex
        : null;
  }

  void _applyPreferences(RecommendationFilter filter) {
    for (final index in _itemIndices.values) {
      index.configure(filter);
    }
    FeedState update(FeedState value) {
      final index = _itemIndices[_indexKey(value)];
      if (index == null || value.items.asData == null) return value;
      final items = _boundedItems(index.items, value: value);
      final marker = _previousStart(index);
      if (identical(items, value.items.asData?.value) &&
          marker == value.previousStartIndex) {
        return value;
      }
      return value.copyWith(
        items: AsyncData(items),
        previousStartIndex: marker,
        clearPreviousStart: marker == null,
      );
    }

    void updateCache<K>(Map<K, (FeedState, int, int)> cache) {
      for (final entry in cache.entries.toList()) {
        cache[entry.key] = (
          update(entry.value.$1),
          entry.value.$2,
          entry.value.$3,
        );
      }
    }

    updateCache(_savedChannels);
    updateCache(_savedPopular);
    updateCache(_savedWeeks);
    final next = update(state);
    if (!identical(next, state)) state = next;
  }

  Future<void> selectRecommended() async {
    await selectChannel(HomeChannel.recommended);
  }

  Future<bool> rejectRecommendation(
    VideoSummary video, {
    RecommendationFeedbackReason? reason,
  }) async {
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
    if (feedback.source != ref.read(recommendationQueryKeyProvider).source) {
      return false;
    }
    if (feedback.source == RecommendationSource.app && reason == null) {
      throw const AppFailure(AppFailureKind.protocol, '请选择此视频的反馈原因');
    }
    return _submitFeedback(
      video.id,
      reason == null ? feedback : feedback.selectReason(reason),
      undo: false,
    );
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
      if (identical(_rejectWrites[id], token)) _rejectWrites.remove(id);
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
    _saveCurrent();
    _generation++;
    _cancellation?.cancel();
    _cancellation = RequestCancellation();
    final saved = _savedChannels[channel];
    if (saved != null && !saved.$1.items.isLoading) {
      state = _withFeedback(saved.$1);
      _page = saved.$2;
      _pagesWithoutNewItems = saved.$3;
      if (_page == 0) await refresh();
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
    await refresh(
      reloadRankingRegions: channel != HomeChannel.ranking,
      appReason: channel == HomeChannel.recommended
          ? AppRecommendationLoadReason.tabClick
          : null,
    );
  }

  Future<void> selectPopularSection(PopularSection section) async {
    if (state.popular && state.popularSection == section) {
      if (_page == 0 && state.items.isLoading) await refresh();
      return;
    }
    _saveCurrent();
    _generation++;
    _cancellation?.cancel();
    _cancellation = RequestCancellation();
    final saved = _savedPopular[section];
    if (saved != null && !saved.$1.items.isLoading) {
      state = saved.$1;
      _page = saved.$2;
      _pagesWithoutNewItems = saved.$3;
      return;
    }
    state = FeedState(
      channel: HomeChannel.popular,
      popularSection: section,
      categoryId: section == PopularSection.ranking ? '0' : null,
    );
    await refresh(reloadRankingRegions: false);
  }

  Future<void> selectPopularWeek(int number) async {
    if (!state.popular ||
        state.popularSection != PopularSection.weekly ||
        !_popularWeeks.any((week) => week.number == number)) {
      return;
    }
    if (state.weeklyIssue == number) return;
    _saveCurrent();
    _generation++;
    _cancellation?.cancel();
    _cancellation = RequestCancellation();
    final saved = _savedWeeks.remove(number);
    if (saved != null) {
      state = saved.$1.copyWith(weeklyIssues: _popularWeeks);
      _page = saved.$2;
      _pagesWithoutNewItems = saved.$3;
      return;
    }
    state = FeedState(
      channel: HomeChannel.popular,
      popularSection: PopularSection.weekly,
      weeklyIssue: number,
      weeklyIssues: _popularWeeks,
    );
    await refresh(reloadWeeklyIndex: false);
  }

  Future<void> selectCategory(String id) async {
    if (state.categoryId == id) return;
    state = state.copyWith(categoryId: id);
    await refresh(reloadRankingRegions: false);
  }

  Future<void> refresh({
    bool reloadWeeklyIndex = true,
    bool reloadRankingRegions = true,
    AppRecommendationLoadReason? appReason,
  }) async {
    final failedAppRefresh = _failedAppRefresh;
    final appRequest = appReason == null && failedAppRefresh != null
        ? failedAppRefresh
        : AppRecommendationRequest(
            cursor: _appRecommendationCursor,
            reason:
                appReason ??
                (_page == 0
                    ? AppRecommendationLoadReason.initial
                    : AppRecommendationLoadReason.refreshButton),
          );
    if (reloadRankingRegions &&
        (state.channel == HomeChannel.ranking ||
            state.popular && state.popularSection == PopularSection.ranking)) {
      ref.invalidate(rankingCategoriesProvider);
    }
    final previousIndex = _itemIndices[_indexKey(state)];
    final keepPrevious =
        state.channel == HomeChannel.recommended &&
        ref.read(recommendationSettingsProvider).keepPrevious &&
        state.items.asData != null;
    final previous = keepPrevious
        ? previousIndex?.rawItems.take(200).toList() ?? <VideoSummary>[]
        : <VideoSummary>[];
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    _page = 0;
    _pagesWithoutNewItems = 0;
    if (!keepPrevious) _itemIndices.remove(_indexKey(state));
    state = state.copyWith(
      items: keepPrevious ? state.items : const AsyncLoading(),
      hasMore: false,
      loadingMore: false,
      refreshing: keepPrevious,
      clearPreviousStart: true,
      clearPageError: true,
    );
    if (!state.channel.hasVideoFeed) {
      state = state.copyWith(items: const AsyncData([]));
      return;
    }
    try {
      final result = await _loadPage(
        1,
        cancellation,
        reloadWeeklyIndex: reloadWeeklyIndex,
        appRequest: appRequest,
      );
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled) {
        return;
      }
      final index = FilteredFeedIndex(
        ref.read(recommendationFilterProvider),
        _surface(state),
      );
      final merged = index.merge(result.items);
      final freshCount = merged.length;
      final freshIds = result.items.map((item) => item.id).toSet();
      final retained = previous
          .where((item) => !freshIds.contains(item.id))
          .toList();
      if (retained.isNotEmpty) {
        index.merge(retained);
        index.markPrevious(retained.map((item) => item.id));
      }
      final items = _boundedItems(index.items);
      _itemIndices[_indexKey(state)] = index;
      _page = 1;
      if (state.channel == HomeChannel.recommended &&
          ref.read(recommendationQueryKeyProvider).source ==
              RecommendationSource.app) {
        _appRecommendationCursor = result.nextCursor ?? appRequest.cursor;
        _failedAppRefresh = null;
      }
      _pagesWithoutNewItems = freshCount == 0 ? 1 : 0;
      state = state.copyWith(
        items: AsyncData(items),
        hasMore: result.hasMore && _underLimit(items),
        refreshing: false,
        previousStartIndex: _previousStart(index),
        clearPreviousStart: _previousStart(index) == null,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      if (state.channel == HomeChannel.recommended &&
          ref.read(recommendationQueryKeyProvider).source ==
              RecommendationSource.app) {
        _failedAppRefresh = appRequest;
      }
      state = keepPrevious
          ? state.copyWith(refreshing: false, pageError: error)
          : state.copyWith(
              items: AsyncError(error, stackTrace),
              refreshing: false,
            );
    }
  }

  Future<void> loadMore() async {
    if (_page == 0 && state.pageError != null && !state.refreshing) {
      await refresh();
      return;
    }
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
      final index = _itemIndices[_indexKey(state)];
      if (index == null) throw StateError('Loaded feed has no item index');
      final items = _boundedItems(index.merge(result.items));
      _pagesWithoutNewItems = items.length == current.length
          ? _pagesWithoutNewItems + 1
          : 0;
      _page++;
      // Official LoadMoreAction keeps the first card's batch anchor. A refresh
      // replaces it; appended pages must not turn it into a page counter/tail.
      state = state.copyWith(
        items: AsyncData(items),
        hasMore: result.hasMore && _underLimit(items),
        loadingMore: false,
        previousStartIndex: _previousStart(index),
        clearPreviousStart: _previousStart(index) == null,
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

  List<VideoSummary> _boundedItems(
    List<VideoSummary> items, {
    FeedState? value,
  }) =>
      (value ?? state).popular &&
          (value ?? state).popularSection != PopularSection.all &&
          items.length > maximumPopularEntries
      ? List.unmodifiable(items.take(maximumPopularEntries))
      : items;

  bool _underLimit(List<VideoSummary> items) =>
      !state.popular ||
      state.popularSection == PopularSection.all ||
      items.length < maximumPopularEntries;

  Future<PageResult<VideoSummary>> _loadPage(
    int page,
    RequestCancellation cancellation, {
    bool reloadWeeklyIndex = false,
    AppRecommendationRequest? appRequest,
  }) async {
    final repository = ref.read(feedRepositoryProvider);
    if (state.channel == HomeChannel.recommended &&
        ref.read(recommendationQueryKeyProvider).source ==
            RecommendationSource.desktop) {
      if (repository is! DesktopRecommendationFeedRepository) {
        throw const AppFailure(AppFailureKind.protocol, '当前推荐服务暂不支持桌面端来源');
      }
      return (repository as DesktopRecommendationFeedRepository)
          .loadDesktopRecommendations(page: page, cancellation: cancellation);
    }
    if (state.channel == HomeChannel.recommended &&
        ref.read(recommendationQueryKeyProvider).source ==
            RecommendationSource.app) {
      if (repository is! AppRecommendationFeedRepository) {
        throw const AppFailure(AppFailureKind.protocol, '当前推荐服务暂不支持 App 来源');
      }
      return (repository as AppRecommendationFeedRepository)
          .loadAppRecommendations(
            request:
                appRequest ??
                AppRecommendationRequest(
                  cursor: _appRecommendationCursor,
                  reason: AppRecommendationLoadReason.loadMore,
                ),
            cancellation: cancellation,
          );
    }
    if (state.channel == HomeChannel.ranking ||
        state.popular && state.popularSection == PopularSection.ranking) {
      if (repository is RankingFeedRepository) {
        return (repository as RankingFeedRepository).loadRanking(
          categoryId: state.categoryId ?? '0',
          cancellation: cancellation,
        );
      }
      throw const AppFailure(AppFailureKind.protocol, '排行榜服务暂不可用');
    }
    if (state.popular && state.popularSection != PopularSection.all) {
      if (repository is! PopularFeedRepository) {
        throw const AppFailure(AppFailureKind.protocol, '热门精选服务暂不可用');
      }
      final selections = repository as PopularFeedRepository;
      if (state.popularSection == PopularSection.precious) {
        return selections.loadPrecious(cancellation: cancellation);
      }
      if (reloadWeeklyIndex || _popularWeeks.isEmpty) {
        final weeks = await selections.loadPopularWeeks(
          cancellation: cancellation,
        );
        if (!ref.mounted ||
            cancellation.isCancelled ||
            !identical(cancellation, _cancellation)) {
          throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
        }
        _popularWeeks = List.unmodifiable(weeks);
        final selected = weeks.any((week) => week.number == state.weeklyIssue)
            ? state.weeklyIssue
            : weeks.firstOrNull?.number;
        final obsolete = _savedWeeks.keys
            .where((number) => !weeks.any((week) => week.number == number))
            .toList();
        for (final number in obsolete) {
          _savedWeeks.remove(number);
          _itemIndices.remove((
            HomeChannel.popular,
            PopularSection.weekly,
            number,
          ));
        }
        state = state.copyWith(
          weeklyIssues: _popularWeeks,
          weeklyIssue: selected,
          clearWeeklyIssue: selected == null,
        );
      }
      final number = state.weeklyIssue;
      if (number == null) return const PageResult(items: [], hasMore: false);
      return selections.loadPopularWeek(
        number: number,
        cancellation: cancellation,
      );
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
