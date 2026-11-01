import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/request_cancellation.dart';
import '../data/search_discovery_repository.dart';
import '../domain/search_discovery_repository.dart';

final searchDiscoveryRepositoryProvider = Provider<SearchDiscoveryRepository>(
  (ref) => MemorySearchDiscoveryRepository(),
);
final searchHistoryScopeProvider = Provider<String>((ref) => 'guest');
final searchDiscoveryControllerProvider =
    NotifierProvider<SearchDiscoveryController, SearchDiscoveryState>(
      SearchDiscoveryController.new,
    );

final class SearchDiscoveryState {
  const SearchDiscoveryState({
    this.history = const [],
    this.historyError = false,
    this.trending = const AsyncLoading(),
  });
  final List<String> history;
  final bool historyError;
  final AsyncValue<List<SearchTrend>> trending;
}

final class SearchDiscoveryController extends Notifier<SearchDiscoveryState> {
  Object _generation = Object();
  Future<void> _pending = Future.value();
  Future<void>? _trending;
  DateTime? _fetchedAt;
  RequestCancellation? _request;
  bool _historyLoaded = false;

  @override
  SearchDiscoveryState build() {
    final scope = ref.watch(searchHistoryScopeProvider);
    final repository = ref.watch(searchDiscoveryRepositoryProvider);
    final generation = _generation = Object();
    _trending = null;
    _fetchedAt = null;
    _historyLoaded = false;
    ref.onDispose(() {
      _generation = Object();
      _request?.cancel();
    });
    _pending = Future.microtask(() async {
      try {
        final history = await repository.loadHistory(scope);
        if (!_current(generation)) return;
        _historyLoaded = true;
        state = SearchDiscoveryState(
          history: normalizeSearchHistory(history),
          trending: state.trending,
        );
      } catch (_) {
        if (!_current(generation)) return;
        state = SearchDiscoveryState(
          historyError: true,
          trending: state.trending,
        );
      }
    });
    return const SearchDiscoveryState();
  }

  bool _current(Object generation) =>
      ref.mounted && identical(_generation, generation);

  Future<void> remember(String query) =>
      _update((history) => [query, ...history]);
  Future<void> clearHistory() => _update((_) => const [], clear: true);

  Future<void> _update(
    List<String> Function(List<String>) update, {
    bool clear = false,
  }) {
    final generation = _generation;
    final scope = ref.read(searchHistoryScopeProvider);
    final repository = ref.read(searchDiscoveryRepositoryProvider);
    return _pending = _pending.then((_) async {
      if (!_current(generation)) return;
      try {
        final history = _historyLoaded || clear
            ? state.history
            : await repository.loadHistory(scope);
        if (!_current(generation)) return;
        final next = normalizeSearchHistory(update(history));
        await repository.saveHistory(scope, next);
        if (!_current(generation)) return;
        _historyLoaded = true;
        state = SearchDiscoveryState(history: next, trending: state.trending);
      } catch (_) {
        if (!_current(generation)) return;
        state = SearchDiscoveryState(
          history: state.history,
          historyError: true,
          trending: state.trending,
        );
      }
    });
  }

  Future<void> loadTrending({bool force = false}) {
    if (_trending case final pending?) return pending;
    if (!force &&
        _fetchedAt != null &&
        DateTime.now().difference(_fetchedAt!) < const Duration(minutes: 5)) {
      return Future.value();
    }
    final generation = _generation;
    final request = _request = RequestCancellation();
    state = SearchDiscoveryState(
      history: state.history,
      historyError: state.historyError,
    );
    return _trending = () async {
      try {
        final result = await ref
            .read(searchDiscoveryRepositoryProvider)
            .loadTrending(request);
        if (!_current(generation)) return;
        _fetchedAt = DateTime.now();
        state = SearchDiscoveryState(
          history: state.history,
          historyError: state.historyError,
          trending: AsyncData(List.unmodifiable(result.take(10))),
        );
      } catch (error, stack) {
        if (!_current(generation) || request.isCancelled) return;
        state = SearchDiscoveryState(
          history: state.history,
          historyError: state.historyError,
          trending: AsyncError(error, stack),
        );
      } finally {
        if (_current(generation)) _trending = null;
      }
    }();
  }
}
