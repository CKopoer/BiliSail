import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/search_repository.dart';
import '../domain/search_result.dart';

final searchRepositoryProvider = Provider<SearchRepository>(
  (ref) => throw UnimplementedError('SearchRepository must be provided by app'),
);

final searchControllerProvider =
    NotifierProvider<SearchController, SearchState>(SearchController.new);

enum SearchFilterField {
  duration,
  publicationPeriod,
  videoZone,
  articleZone,
  userType,
}

final class SearchState {
  const SearchState({
    this.query = '',
    this.category = SearchCategory.all,
    this.order = SearchOrder.relevance,
    this.duration = SearchDuration.any,
    this.userType = SearchUserType.any,
    this.videoZone = SearchVideoZone.any,
    this.articleZone = SearchArticleZone.any,
    this.publicationPeriod = SearchPublicationPeriod.any,
    this.publicationRange,
    this.counts = const {},
    this.items = const AsyncData([]),
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
  });

  final String query;
  final SearchCategory category;
  final SearchOrder order;
  final SearchDuration duration;
  final SearchUserType userType;
  final SearchVideoZone videoZone;
  final SearchArticleZone articleZone;
  final SearchPublicationPeriod publicationPeriod;
  final SearchPublicationRange? publicationRange;
  final Map<SearchCategory, int> counts;
  final AsyncValue<List<SearchEntry>> items;
  final bool hasMore, loadingMore;
  final Object? pageError;

  List<SearchFilterField> get activeFilters => [
    if (duration != SearchDuration.any) SearchFilterField.duration,
    if (publicationPeriod != SearchPublicationPeriod.any)
      SearchFilterField.publicationPeriod,
    if (videoZone != SearchVideoZone.any) SearchFilterField.videoZone,
    if (articleZone != SearchArticleZone.any) SearchFilterField.articleZone,
    if (userType != SearchUserType.any) SearchFilterField.userType,
  ];

  bool get hasFilters => activeFilters.isNotEmpty;

  SearchState copyWith({
    String? query,
    SearchCategory? category,
    SearchOrder? order,
    SearchDuration? duration,
    SearchUserType? userType,
    SearchVideoZone? videoZone,
    SearchArticleZone? articleZone,
    SearchPublicationPeriod? publicationPeriod,
    SearchPublicationRange? publicationRange,
    Map<SearchCategory, int>? counts,
    AsyncValue<List<SearchEntry>>? items,
    bool? hasMore,
    bool? loadingMore,
    Object? pageError,
    bool clearPageError = false,
  }) => SearchState(
    query: query ?? this.query,
    category: category ?? this.category,
    order: order ?? this.order,
    duration: duration ?? this.duration,
    userType: userType ?? this.userType,
    videoZone: videoZone ?? this.videoZone,
    articleZone: articleZone ?? this.articleZone,
    publicationPeriod: publicationPeriod ?? this.publicationPeriod,
    publicationRange: publicationPeriod == SearchPublicationPeriod.any
        ? null
        : publicationRange ?? this.publicationRange,
    counts: counts ?? this.counts,
    items: items ?? this.items,
    hasMore: hasMore ?? this.hasMore,
    loadingMore: loadingMore ?? this.loadingMore,
    pageError: clearPageError ? null : pageError ?? this.pageError,
  );
}

final class SearchController extends Notifier<SearchState> {
  int _generation = 0, _page = 0;
  RequestCancellation? _cancellation;

  @override
  SearchState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
    });
    return const SearchState();
  }

  Future<void> search(String input) => _reload(
    state.copyWith(
      query: input.trim(),
      counts: input.trim() == state.query ? null : const {},
    ),
  );

  Future<void> refresh() => _reload(state);

  Future<void> selectCategory(SearchCategory category) {
    if (category == state.category) return Future.value();
    return _reload(
      state.copyWith(
        category: category,
        order: SearchOrder.relevance,
        duration: SearchDuration.any,
        userType: SearchUserType.any,
        videoZone: SearchVideoZone.any,
        articleZone: SearchArticleZone.any,
        publicationPeriod: SearchPublicationPeriod.any,
      ),
    );
  }

  Future<void> selectOrder(SearchOrder order) {
    if (order == state.order || !state.category.orders.contains(order)) {
      return Future.value();
    }
    return _reload(state.copyWith(order: order));
  }

  Future<void> removeFilter(SearchFilterField field) {
    if (!state.activeFilters.contains(field)) return Future.value();
    return _reload(switch (field) {
      SearchFilterField.duration => state.copyWith(
        duration: SearchDuration.any,
      ),
      SearchFilterField.publicationPeriod => state.copyWith(
        publicationPeriod: SearchPublicationPeriod.any,
      ),
      SearchFilterField.videoZone => state.copyWith(
        videoZone: SearchVideoZone.any,
      ),
      SearchFilterField.articleZone => state.copyWith(
        articleZone: SearchArticleZone.any,
      ),
      SearchFilterField.userType => state.copyWith(
        userType: SearchUserType.any,
      ),
    });
  }

  Future<void> applyFilters({
    required SearchCategory category,
    required SearchOrder order,
    SearchDuration duration = SearchDuration.any,
    SearchUserType userType = SearchUserType.any,
    SearchVideoZone videoZone = SearchVideoZone.any,
    SearchArticleZone articleZone = SearchArticleZone.any,
    SearchPublicationPeriod publicationPeriod = SearchPublicationPeriod.any,
    SearchPublicationRange? publicationRange,
  }) async {
    if (category != state.category ||
        !category.orders.contains(order) ||
        (!category.hasVideoFilters &&
            (duration != SearchDuration.any ||
                videoZone != SearchVideoZone.any ||
                publicationPeriod != SearchPublicationPeriod.any)) ||
        (!category.hasArticleFilters && articleZone != SearchArticleZone.any) ||
        (!category.hasUserFilters && userType != SearchUserType.any) ||
        (publicationPeriod == SearchPublicationPeriod.customRange) !=
            (publicationRange != null)) {
      return;
    }
    final range = switch (publicationPeriod) {
      SearchPublicationPeriod.any => null,
      SearchPublicationPeriod.customRange => publicationRange,
      _ => _presetRange(publicationPeriod, DateTime.now()),
    };
    if (state.order == order &&
        state.duration == duration &&
        state.userType == userType &&
        state.videoZone == videoZone &&
        state.articleZone == articleZone &&
        state.publicationPeriod == publicationPeriod &&
        state.publicationRange == range) {
      return;
    }
    await _reload(
      state.copyWith(
        order: order,
        duration: duration,
        userType: userType,
        videoZone: videoZone,
        articleZone: articleZone,
        publicationPeriod: publicationPeriod,
        publicationRange: range,
      ),
    );
  }

  static SearchPublicationRange _presetRange(
    SearchPublicationPeriod period,
    DateTime now,
  ) {
    final daysBefore = switch (period) {
      SearchPublicationPeriod.day => 0,
      SearchPublicationPeriod.week => 6,
      SearchPublicationPeriod.halfYear => 179,
      _ => throw ArgumentError.value(period),
    };
    return SearchPublicationRange(
      start: DateTime(now.year, now.month, now.day - daysBefore),
      end: now,
    );
  }

  Future<SearchPage> _request(
    SearchState request,
    int page,
    RequestCancellation cancellation,
  ) => ref
      .read(searchRepositoryProvider)
      .search(
        query: request.query,
        page: page,
        category: request.category,
        order: request.order,
        duration: request.duration,
        userType: request.userType,
        videoZone: request.videoZone,
        articleZone: request.articleZone,
        publicationRange: request.publicationRange,
        cancellation: cancellation,
      );

  Future<void> _reload(SearchState request) async {
    final generation = ++_generation;
    _cancellation?.cancel();
    _page = 0;
    if (request.query.isEmpty) {
      state = const SearchState();
      return;
    }
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    state = request.copyWith(
      items: const AsyncLoading(),
      hasMore: false,
      loadingMore: false,
      clearPageError: true,
    );
    try {
      final result = await _request(request, 1, cancellation);
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled) {
        return;
      }
      _page = 1;
      state = state.copyWith(
        items: AsyncData(_unique(result.items)),
        counts: _categoryCounts(request, result),
        hasMore: result.hasMore,
      );
    } catch (error, stackTrace) {
      if (!ref.mounted || generation != _generation) return;
      if (_cancelled(error)) {
        state = state.copyWith(items: const AsyncData([]));
        return;
      }
      state = state.copyWith(items: AsyncError(error, stackTrace));
    }
  }

  Future<void> loadMore() async {
    final current = state.items.asData?.value;
    if (current == null ||
        state.query.isEmpty ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    final generation = _generation;
    final cancellation = _cancellation;
    if (cancellation == null || cancellation.isCancelled) return;
    final request = state;
    state = state.copyWith(loadingMore: true, clearPageError: true);
    try {
      final result = await _request(request, _page + 1, cancellation);
      if (!ref.mounted ||
          generation != _generation ||
          cancellation.isCancelled) {
        return;
      }
      _page++;
      final merged = _unique([...current, ...result.items]);
      state = state.copyWith(
        items: AsyncData(merged),
        // A repeated/empty page must not trigger an endless scroll-load loop.
        hasMore: result.hasMore && merged.length > current.length,
        counts: _categoryCounts(request, result),
        loadingMore: false,
      );
    } catch (error) {
      if (!ref.mounted || generation != _generation) return;
      state = state.copyWith(
        loadingMore: false,
        pageError: _cancelled(error) ? null : error,
      );
    }
  }

  Map<SearchCategory, int> _categoryCounts(
    SearchState request,
    SearchPage result,
  ) {
    // Category badges describe the keyword, even while the list is filtered.
    if (request.hasFilters ||
        (request.category == SearchCategory.all &&
            request.order != SearchOrder.relevance)) {
      return state.counts;
    }
    return Map.unmodifiable({...state.counts, ...result.counts});
  }

  static List<SearchEntry> _unique(Iterable<SearchEntry> items) {
    final seen = <String>{};
    return List.unmodifiable(items.where((item) => seen.add(item.key)));
  }

  static bool _cancelled(Object error) =>
      error is AppFailure && error.kind == AppFailureKind.cancelled;
}
