import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/home_channel.dart';
import '../domain/home_repository.dart';

final homeRepositoryProvider = Provider<HomeRepository>(
  (ref) => throw UnimplementedError('HomeRepository must be provided by app'),
);
final homeControllerProvider = NotifierProvider.autoDispose
    .family<HomeController, HomeState, HomeQuery>(HomeController.new);

final class HomeState {
  const HomeState({
    this.items = const AsyncLoading(),
    this.hasMore = false,
    this.loadingMore = false,
    this.limitReached = false,
    this.pageError,
    this.unsubscribing = const {},
  });
  final AsyncValue<List<HomeEntry>> items;
  final bool hasMore;
  final bool loadingMore;
  final bool limitReached;
  final Object? pageError;
  final Set<(HomeEntryKind, String)> unsubscribing;

  HomeState withUnsubscribing(Set<(HomeEntryKind, String)> pending) =>
      HomeState(
        items: items,
        hasMore: hasMore,
        loadingMore: loadingMore,
        limitReached: limitReached,
        pageError: pageError,
        unsubscribing: pending,
      );
}

final class HomeController extends Notifier<HomeState> {
  HomeController(this.query);
  // Rich posts retain images, spans and originals; bound each dynamic tab.
  static const maxDynamicEntries = 200;
  static const maxFavoriteEntries = 500;
  // The image/text tab filters an all-types feed. Advancing empty pages are
  // valid, but a bounded scan avoids an endless layout-driven request loop.
  static const _maxPagesWithoutNewItems = 3;
  final HomeQuery query;
  bool get _isDynamic =>
      query.channel == HomeChannel.dynamic ||
      query.channel == HomeChannel.videoDynamic;
  int? get _entryLimit => _isDynamic
      ? maxDynamicEntries
      : query.channel == HomeChannel.favorites
      ? maxFavoriteEntries
      : null;
  bool _reachedLimit(List<HomeEntry> items) {
    final limit = _entryLimit;
    return limit != null && items.length >= limit;
  }

  RequestCancellation? _cancellation;
  int _generation = 0;
  int _page = 0;
  String? _cursor;
  final Set<String> _seenCursors = {};
  int _pagesWithoutNewItems = 0;
  int _reconcileUntilPage = 0;
  final Map<(HomeEntryKind, String), RequestCancellation> _unsubscriptions = {};
  final Set<(HomeEntryKind, String)> _removedSubscriptions = {};
  Set<(HomeEntryKind, String)> get _pending =>
      Set.unmodifiable(_unsubscriptions.keys);
  @override
  HomeState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
      for (final cancellation in _unsubscriptions.values) {
        cancellation.cancel();
      }
    });
    Future<void>.microtask(refresh);
    return const HomeState();
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    _page = 0;
    _cursor = null;
    _seenCursors.clear();
    _pagesWithoutNewItems = 0;
    _reconcileUntilPage = 0;
    _removedSubscriptions.clear();
    state = HomeState(unsubscribing: _pending);
    final repository = ref.read(homeRepositoryProvider);
    try {
      if (!_isCurrent(generation, cancellation, repository)) return;
      final result = await repository.load(
        query,
        page: 1,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation, cancellation, repository)) return;
      final items = _mergeItems(const [], result.items);
      final limitReached = _reachedLimit(items);
      if (_isDynamic &&
          result.hasMore &&
          !limitReached &&
          !_cursorAdvances(result.nextCursor)) {
        throw const AppFailure(AppFailureKind.protocol, '动态分页游标没有前进，请重试');
      }
      _page = 1;
      _cursor = result.nextCursor;
      if (_cursor case final cursor?) _seenCursors.add(cursor);
      _pagesWithoutNewItems = items.isEmpty ? 1 : 0;
      state = HomeState(
        items: AsyncData(items),
        hasMore: result.hasMore && !limitReached,
        limitReached: limitReached,
        unsubscribing: _pending,
      );
    } catch (error, stack) {
      if (!_isCurrent(generation, cancellation, repository) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HomeState(
        items: AsyncError(error, stack),
        unsubscribing: _pending,
      );
    }
  }

  Future<void> loadMore() async {
    final current = state.items.asData?.value;
    final cancellation = _cancellation;
    if (current == null ||
        cancellation == null ||
        cancellation.isCancelled ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    final generation = _generation;
    final repository = ref.read(homeRepositoryProvider);
    if (!_isCurrent(generation, cancellation, repository)) return;
    if (state.pageError != null) _pagesWithoutNewItems = 0;
    state = HomeState(
      items: AsyncData(current),
      hasMore: true,
      loadingMore: true,
      unsubscribing: _pending,
    );
    try {
      final result = await repository.load(
        query,
        page: _page + 1,
        cursor: _cursor,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation, cancellation, repository)) return;
      final items = _mergeItems(current, result.items);
      final limitReached = _reachedLimit(items);
      final cursorStalled =
          _isDynamic &&
          result.hasMore &&
          !limitReached &&
          !_cursorAdvances(result.nextCursor);
      if (!cursorStalled) {
        _page++;
        _cursor = result.nextCursor;
        if (_cursor case final cursor?) _seenCursors.add(cursor);
      }
      _pagesWithoutNewItems = _page <= _reconcileUntilPage
          ? 0
          : items.length == current.length
          ? _pagesWithoutNewItems + 1
          : 0;
      state = HomeState(
        items: AsyncData(items),
        hasMore: result.hasMore && !limitReached,
        limitReached: limitReached,
        unsubscribing: _pending,
        pageError: limitReached || !result.hasMore
            ? null
            : cursorStalled
            ? const AppFailure(AppFailureKind.protocol, '动态分页游标没有前进，请重试')
            : _pagesWithoutNewItems >= _maxPagesWithoutNewItems
            ? const AppFailure(AppFailureKind.protocol, '连续多页没有新内容，可重试继续加载')
            : null,
      );
    } catch (error) {
      if (!_isCurrent(generation, cancellation, repository) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HomeState(
        items: AsyncData(current),
        hasMore: true,
        pageError: error,
        unsubscribing: _pending,
      );
    }
  }

  Future<bool> unsubscribeFavorite(HomeEntry entry) async {
    if (!ref.mounted ||
        query.channel != HomeChannel.favorites ||
        query.section != '我的收藏与订阅' ||
        query.folderId != null ||
        (entry.kind != HomeEntryKind.folder &&
            entry.kind != HomeEntryKind.collection)) {
      return false;
    }
    final key = (entry.kind, entry.id);
    final items = state.items.asData?.value;
    if (items == null ||
        !items.any((item) => (item.kind, item.id) == key) ||
        _unsubscriptions.containsKey(key)) {
      return false;
    }
    final repository = ref.read(homeRepositoryProvider);
    if (repository is! HomeSubscriptionRepository) {
      throw const AppFailure(AppFailureKind.protocol, '当前无法取消订阅');
    }
    final cancellation = RequestCancellation();
    _unsubscriptions[key] = cancellation;
    state = state.withUnsubscribing(_pending);
    bool current() =>
        ref.mounted &&
        !cancellation.isCancelled &&
        repository.accountScope == query.scope;
    try {
      if (!current()) return false;
      await (repository as HomeSubscriptionRepository).unsubscribeFavorite(
        entry,
        scope: query.scope,
        cancellation: cancellation,
      );
      if (!current()) return false;
      _removedSubscriptions.add(key);
      if (_removedSubscriptions.length > maxFavoriteEntries) {
        _removedSubscriptions.remove(_removedSubscriptions.first);
      }
      // A removal shifts server page offsets. Discard any outstanding read and
      // resume paging from page 1, deduplicating against the retained cards.
      final hasMore =
          state.hasMore ||
          state.loadingMore ||
          state.limitReached ||
          state.items.isLoading ||
          _page > 1;
      _generation++;
      _cancellation?.cancel();
      _cancellation = RequestCancellation();
      if (_page > _reconcileUntilPage) _reconcileUntilPage = _page;
      _page = 0;
      _cursor = null;
      _seenCursors.clear();
      _pagesWithoutNewItems = 0;
      state = HomeState(
        items: AsyncData(
          _mergeItems(const [], state.items.asData?.value ?? items),
        ),
        hasMore: hasMore,
        unsubscribing: _pending,
      );
      return true;
    } catch (error) {
      if (!current() ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return false;
      }
      rethrow;
    } finally {
      _unsubscriptions.remove(key);
      if (ref.mounted) state = state.withUnsubscribing(_pending);
    }
  }

  bool _isCurrent(
    int generation,
    RequestCancellation cancellation,
    HomeRepository repository,
  ) {
    if (!ref.mounted || generation != _generation || cancellation.isCancelled) {
      return false;
    }
    if (query.scope != repository.accountScope) {
      cancellation.cancel();
      return false;
    }
    return true;
  }

  bool _cursorAdvances(String? cursor) =>
      cursor != null && cursor.isNotEmpty && !_seenCursors.contains(cursor);

  List<HomeEntry> _mergeItems(
    List<HomeEntry> current,
    List<HomeEntry> incoming,
  ) {
    final unique = {for (final entry in current) (entry.kind, entry.id): entry};
    for (final entry in incoming) {
      final key = (entry.kind, entry.id);
      if (_removedSubscriptions.contains(key)) continue;
      final limit = _entryLimit;
      if (limit != null && unique.length >= limit && !unique.containsKey(key)) {
        continue;
      }
      unique[key] = entry;
    }
    return List.unmodifiable(unique.values);
  }
}
