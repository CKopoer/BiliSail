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
  });
  final AsyncValue<List<HomeEntry>> items;
  final bool hasMore;
  final bool loadingMore;
  final bool limitReached;
  final Object? pageError;
}

final class HomeController extends Notifier<HomeState> {
  HomeController(this.query);
  // Rich posts retain images, spans and originals; bound each dynamic tab.
  static const maxDynamicEntries = 200;
  // The image/text tab filters an all-types feed. Advancing empty pages are
  // valid, but a bounded scan avoids an endless layout-driven request loop.
  static const _maxPagesWithoutNewItems = 3;
  final HomeQuery query;
  bool get _isDynamic =>
      query.channel == HomeChannel.dynamic ||
      query.channel == HomeChannel.videoDynamic;
  RequestCancellation? _cancellation;
  int _generation = 0;
  int _page = 0;
  String? _cursor;
  final Set<String> _seenCursors = {};
  int _pagesWithoutNewItems = 0;
  @override
  HomeState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
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
    state = const HomeState();
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
      final limitReached = _isDynamic && items.length >= maxDynamicEntries;
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
      );
    } catch (error, stack) {
      if (!_isCurrent(generation, cancellation, repository) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HomeState(items: AsyncError(error, stack));
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
      final limitReached = _isDynamic && items.length >= maxDynamicEntries;
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
      _pagesWithoutNewItems = items.length == current.length
          ? _pagesWithoutNewItems + 1
          : 0;
      state = HomeState(
        items: AsyncData(items),
        hasMore: result.hasMore && !limitReached,
        limitReached: limitReached,
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
      );
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
      if (_isDynamic &&
          unique.length >= maxDynamicEntries &&
          !unique.containsKey(key)) {
        continue;
      }
      unique[key] = entry;
    }
    return List.unmodifiable(unique.values);
  }
}
