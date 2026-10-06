import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/library_repository.dart';

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) =>
      throw UnimplementedError('LibraryRepository must be provided by app'),
);

final historyProvider =
    NotifierProvider.autoDispose<HistoryController, HistoryState>(
      HistoryController.new,
    );

final class HistoryState {
  const HistoryState({
    this.items = const AsyncLoading(),
    this.hasMore = false,
    this.loadingMore = false,
    this.pageError,
    this.limitReached = false,
  });
  final AsyncValue<List<WatchHistoryEntry>> items;
  final bool hasMore, loadingMore, limitReached;
  final Object? pageError;
}

final class HistoryController extends Notifier<HistoryState> {
  static const maxEntries = 500;
  RequestCancellation? _cancellation;
  int _generation = 0;
  String? _cursor;
  final Set<String> _seenCursors = {};
  int _emptyPages = 0;
  String _scope = '';
  int _epoch = 0;

  @override
  HistoryState build() {
    ref.watch(libraryRepositoryProvider);
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
    });
    Future<void>.microtask(refresh);
    return const HistoryState();
  }

  bool _current(int generation, RequestCancellation cancellation) =>
      ref.mounted &&
      generation == _generation &&
      !cancellation.isCancelled &&
      _scope == ref.read(libraryRepositoryProvider).accountScope &&
      _epoch == ref.read(sessionEpochProvider)();

  void _validateCursor(WatchHistoryPage page) {
    if (page.hasMore &&
        (page.nextCursor == null || _seenCursors.contains(page.nextCursor))) {
      throw const AppFailure(AppFailureKind.protocol, '历史分页游标没有前进，请刷新重试');
    }
  }

  List<WatchHistoryEntry> _merge(
    List<WatchHistoryEntry> before,
    List<WatchHistoryEntry> incoming,
  ) {
    final entries = <(String, String, String?), WatchHistoryEntry>{};
    for (final entry in [...before, ...incoming]) {
      final key = (entry.video.id.value, entry.part.cid, entry.episodeId);
      final old = entries[key];
      if (old == null || entry.watchedAt.isAfter(old.watchedAt)) {
        entries[key] = entry;
      }
    }
    return List.unmodifiable(entries.values.take(maxEntries));
  }

  void _accept(
    WatchHistoryPage page,
    List<WatchHistoryEntry> items,
    int beforeCount,
  ) {
    _cursor = page.nextCursor;
    if (_cursor case final cursor?) _seenCursors.add(cursor);
    _emptyPages = items.length == beforeCount ? _emptyPages + 1 : 0;
    final limit = items.length >= maxEntries;
    state = HistoryState(
      items: AsyncData(items),
      hasMore: page.hasMore && !limit,
      limitReached: limit,
      pageError: page.hasMore && !limit && _emptyPages >= 3
          ? const AppFailure(AppFailureKind.protocol, '连续多页没有视频记录，可重试继续加载')
          : null,
    );
  }

  Future<void> refresh() async {
    if (!ref.mounted) return;
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = RequestCancellation();
    _cancellation = cancellation;
    _cursor = null;
    _seenCursors.clear();
    _emptyPages = 0;
    _scope = ref.read(libraryRepositoryProvider).accountScope;
    _epoch = ref.read(sessionEpochProvider)();
    state = const HistoryState();
    try {
      final page = await ref
          .read(libraryRepositoryProvider)
          .loadHistory(cancellation: cancellation);
      if (!_current(generation, cancellation)) return;
      _validateCursor(page);
      _accept(page, _merge(const [], page.items), 0);
    } catch (error, stack) {
      if (!_current(generation, cancellation) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HistoryState(items: AsyncError(error, stack));
    }
  }

  Future<void> loadMore() async {
    final items = state.items.asData?.value;
    final cancellation = _cancellation;
    if (items == null ||
        cancellation == null ||
        !state.hasMore ||
        state.loadingMore) {
      return;
    }
    final generation = _generation;
    if (!_current(generation, cancellation)) return;
    _emptyPages = state.pageError == null ? _emptyPages : 0;
    state = HistoryState(
      items: AsyncData(items),
      hasMore: true,
      loadingMore: true,
    );
    try {
      final page = await ref
          .read(libraryRepositoryProvider)
          .loadHistory(cursor: _cursor, cancellation: cancellation);
      if (!_current(generation, cancellation)) return;
      _validateCursor(page);
      _accept(page, _merge(items, page.items), items.length);
    } catch (error) {
      if (!_current(generation, cancellation) ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = HistoryState(
        items: AsyncData(items),
        hasMore: true,
        pageError: error,
      );
    }
  }
}
