import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/user.dart';
import '../domain/dynamic_author.dart';
import '../../../core/network/api_requests.dart';
import '../../video/domain/video_actions_repository.dart';
import '../domain/home_channel.dart';
import '../domain/home_repository.dart';
import 'watch_later_removal_controller.dart';
import 'home_repository_provider.dart';
export 'home_repository_provider.dart';

final homeControllerProvider = NotifierProvider.autoDispose
    .family<HomeController, HomeState, HomeQuery>(
      HomeController.new,
      // The workspace and each account-content list override this family.
      // Declare scoping so nested overrides fork their family directory instead
      // of redirecting sibling queries into the account list's container.
      dependencies: const [],
    );

final dynamicAuthorFeedProvider = NotifierProvider.autoDispose
    .family<HomeController, HomeState, ({HomeQuery query, UserId authorId})>(
      (request) => HomeController(request.query, authorId: request.authorId),
      dependencies: [homeControllerProvider],
    );

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
  // Pending subscription, video and folder removals share the same card state.
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
  HomeController(this.query, {this.authorId});
  // Rich posts retain images, spans and originals; bound each dynamic tab.
  static const maxDynamicEntries = 200;
  static const maxFavoriteEntries = 500;
  // The image/text tab filters an all-types feed. Advancing empty pages are
  // valid, but a bounded scan avoids an endless layout-driven request loop.
  static const _maxPagesWithoutNewItems = 3;
  final HomeQuery query;
  final UserId? authorId;

  Future<HomePage> _load(
    HomeRepository repository, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final author = authorId;
    if (author != null) {
      if (repository is! HomeDynamicRepository) {
        throw const AppFailure(AppFailureKind.protocol, '当前无法按 UP 主筛选动态');
      }
      return (repository as HomeDynamicRepository).loadAuthorFeed(
        query,
        author,
        page: page,
        cursor: cursor,
        cancellation: cancellation,
      );
    }
    return repository.load(
      query,
      page: page,
      cursor: cursor,
      cancellation: cancellation,
    );
  }

  final Map<VideoId, ({int page, String? cursor})> _queuePages = {};
  ({int page, String? cursor})? queuePageFor(VideoId id) => _queuePages[id];
  void _trackQueuePage(List<HomeEntry> items, int page, String? cursor) {
    if (query.channel != HomeChannel.favorites) return;
    for (final item in items) {
      final id = VideoId(item.bvid ?? '');
      if (id.isValid && _queuePages.length < maxFavoriteEntries) {
        _queuePages.putIfAbsent(id, () => (page: page, cursor: cursor));
      }
    }
  }

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
  String? _defaultFolderId;
  final Set<String> _seenCursors = {};
  int _pagesWithoutNewItems = 0;
  int _reconcileUntilPage = 0;
  final Map<(HomeEntryKind, String), RequestCancellation> _removals = {};
  final Set<(HomeEntryKind, String)> _removedEntries = {};
  final Set<(HomeEntryKind, String)> _uncertainRemovals = {};
  Set<(HomeEntryKind, String)> get _pending => Set.unmodifiable(_removals.keys);
  @override
  HomeState build() {
    if (query.channel == HomeChannel.watchLater) {
      ref.listen(watchLaterRemovalProvider(query.scope), (_, next) {
        final items = state.items.asData?.value;
        state = HomeState(
          items: items == null
              ? state.items
              : AsyncData(
                  List.unmodifiable(
                    items.where((entry) => !next.removed.contains(entry.id)),
                  ),
                ),
          hasMore: state.hasMore,
          loadingMore: state.loadingMore,
          limitReached: state.limitReached,
          pageError: state.pageError,
          unsubscribing: state.unsubscribing,
        );
      });
    }
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
      for (final cancellation in _removals.values) {
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
    _queuePages.clear();
    _cursor = null;
    _defaultFolderId = null;
    _seenCursors.clear();
    _pagesWithoutNewItems = 0;
    _reconcileUntilPage = 0;
    _removedEntries.clear();
    _uncertainRemovals.clear();
    state = HomeState(unsubscribing: _pending);
    final repository = ref.read(homeRepositoryProvider);
    try {
      if (!_isCurrent(generation, cancellation, repository)) return;
      final result = await _load(
        repository,
        page: 1,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation, cancellation, repository)) return;
      final items = _mergeItems(const [], result.items);
      _trackQueuePage(result.items, 1, result.nextCursor);
      final limitReached = _reachedLimit(items);
      if (_isDynamic &&
          result.hasMore &&
          !limitReached &&
          !_cursorAdvances(result.nextCursor)) {
        throw const AppFailure(AppFailureKind.protocol, '动态分页游标没有前进，请重试');
      }
      _page = 1;
      _cursor = result.nextCursor;
      if (query.section == '默认收藏夹') {
        _defaultFolderId = result.favoriteFolderId ?? result.nextCursor;
      }
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
      final result = await _load(
        repository,
        page: _page + 1,
        cursor: _cursor,
        cancellation: cancellation,
      );
      if (!_isCurrent(generation, cancellation, repository)) return;
      final items = _mergeItems(current, result.items);
      _trackQueuePage(result.items, _page + 1, result.nextCursor ?? _cursor);
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
    return _removeEntry(entry, (repository, cancellation) {
      if (repository is! HomeSubscriptionRepository) {
        throw const AppFailure(AppFailureKind.protocol, '当前无法取消订阅');
      }
      return (repository as HomeSubscriptionRepository).unsubscribeFavorite(
        entry,
        scope: query.scope,
        cancellation: cancellation,
      );
    });
  }

  bool canRemoveFavorite(HomeEntry entry) =>
      query.channel == HomeChannel.favorites &&
      (query.section == '默认收藏夹' || query.section == '我创建的收藏夹') &&
      (query.folderId != null || query.section == '默认收藏夹') &&
      query.folderId?.startsWith('ugc:') != true &&
      entry.kind == HomeEntryKind.video &&
      entry.aid != null;

  Future<bool> removeFavorite(HomeEntry entry) async {
    if (!canRemoveFavorite(entry)) return false;
    final folderId = query.folderId ?? _defaultFolderId;
    if (folderId == null) return false;
    return _removeEntry(entry, (repository, cancellation) {
      if (repository is! HomeFavoriteRepository) {
        throw const AppFailure(AppFailureKind.protocol, '当前无法取消收藏');
      }
      return (repository as HomeFavoriteRepository).removeFavorite(
        entry,
        folderId: folderId,
        scope: query.scope,
        cancellation: cancellation,
      );
    });
  }

  Future<bool> deleteFavoriteFolder(HomeEntry entry) async {
    if (query.channel != HomeChannel.favorites ||
        query.section != '我创建的收藏夹' ||
        query.folderId != null ||
        entry.kind != HomeEntryKind.folder ||
        entry.id == _cursor) {
      return false;
    }
    return _removeEntry(entry, (repository, cancellation) {
      if (repository is! HomeFavoriteRepository) {
        throw const AppFailure(AppFailureKind.protocol, '当前无法删除收藏夹');
      }
      return (repository as HomeFavoriteRepository).deleteFavoriteFolder(
        entry,
        scope: query.scope,
        cancellation: cancellation,
      );
    });
  }

  Future<bool> _removeEntry(
    HomeEntry entry,
    Future<void> Function(HomeRepository, RequestCancellation) write,
  ) async {
    if (!ref.mounted) return false;
    final key = (entry.kind, entry.id);
    final items = state.items.asData?.value;
    if (items == null ||
        !items.any((item) => (item.kind, item.id) == key) ||
        _removals.containsKey(key)) {
      return false;
    }
    if (_uncertainRemovals.contains(key)) throw const UnknownWriteOutcome();
    final repository = ref.read(homeRepositoryProvider);
    final epoch = ref.read(sessionEpochProvider)();
    final cancellation = RequestCancellation();
    _removals[key] = cancellation;
    state = state.withUnsubscribing(_pending);
    bool current() =>
        ref.mounted &&
        !cancellation.isCancelled &&
        repository.accountScope == query.scope &&
        ref.read(sessionEpochProvider)() == epoch;
    try {
      if (!current()) return false;
      await write(repository, cancellation);
      if (!current()) return false;
      _removedEntries.add(key);
      if (_removedEntries.length > maxFavoriteEntries) {
        _removedEntries.remove(_removedEntries.first);
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
      _queuePages.clear();
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
      if (error is UnknownWriteOutcome) _uncertainRemovals.add(key);
      rethrow;
    } finally {
      _removals.remove(key);
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

  (HomeEntryKind, String) _mergeKey(HomeEntry entry) {
    final videoOnly =
        query.channel == HomeChannel.videoDynamic ||
        query.channel == HomeChannel.dynamic && query.section == '视频';
    final bvid = entry.bvid;
    if (videoOnly &&
        entry.kind == HomeEntryKind.video &&
        bvid != null &&
        VideoId(bvid).isValid &&
        entry.dynamicPost?.original == null) {
      // Each coauthor has a different dynamic ID for the same archive.
      return (entry.kind, bvid);
    }
    return (entry.kind, entry.id);
  }

  List<HomeEntry> _mergeItems(
    List<HomeEntry> current,
    List<HomeEntry> incoming,
  ) {
    final removedWatchLater = query.channel == HomeChannel.watchLater
        ? ref.read(watchLaterRemovalProvider(query.scope)).removed
        : const <String>{};
    final unique = {
      for (final entry in current)
        if (!removedWatchLater.contains(entry.id)) _mergeKey(entry): entry,
    };
    for (final entry in incoming) {
      if (_removedEntries.contains((entry.kind, entry.id))) continue;
      if (removedWatchLater.contains(entry.id)) continue;
      final key = _mergeKey(entry);
      final previous = unique[key];
      if (previous != null && previous.id != entry.id && key.$2 == entry.bvid) {
        // Only the explicit upload action identifies the primary submission.
        // Otherwise keep the first coauthor in server order, including across
        // pages. Replacing the value preserves its slot and full interaction ID.
        if (previous.dynamicPost?.actionText == '投稿了视频' ||
            entry.dynamicPost?.actionText != '投稿了视频') {
          continue;
        }
      }
      final limit = _entryLimit;
      if (limit != null && unique.length >= limit && !unique.containsKey(key)) {
        continue;
      }
      unique[key] = entry;
    }
    return List.unmodifiable(unique.values);
  }
}
