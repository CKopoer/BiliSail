import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/dynamic_author.dart';
import 'home_controller.dart';

final dynamicAuthorsProvider = NotifierProvider.autoDispose
    .family<DynamicAuthorsController, DynamicAuthorsState, String>(
      DynamicAuthorsController.new,
      dependencies: [homeControllerProvider],
    );

final class DynamicAuthorsState {
  const DynamicAuthorsState({
    this.items = const [],
    this.selected,
    this.loading = false,
    this.hasMore = false,
    this.error,
  });

  final List<DynamicAuthor> items;
  final DynamicAuthor? selected;
  final bool loading;
  final bool hasMore;
  final Object? error;
}

final class DynamicAuthorsController extends Notifier<DynamicAuthorsState> {
  DynamicAuthorsController(this.scope);
  static const maxAuthors = 500;
  final String scope;
  RequestCancellation? _cancellation;
  int _generation = 0;
  String? _cursor;
  final _seenCursors = <String>{};

  @override
  DynamicAuthorsState build() {
    ref.onDispose(() {
      _generation++;
      _cancellation?.cancel();
    });
    Future<void>.microtask(refresh);
    return const DynamicAuthorsState(loading: true);
  }

  void select(UserId? id) {
    if (!ref.mounted || state.selected?.id == id) return;
    final author = id == null
        ? null
        : state.items.where((item) => item.id == id).firstOrNull;
    if (id != null && author == null) return;
    state = DynamicAuthorsState(
      items: state.items,
      selected: author,
      loading: state.loading,
      hasMore: state.hasMore,
      error: state.error,
    );
  }

  Future<void> refresh() => _load(refresh: true);
  Future<void> loadMore() => !state.loading && state.hasMore
      ? _load(refresh: _cursor == null)
      : Future.value();

  Future<void> _load({required bool refresh}) async {
    if (!ref.mounted) return;
    final repository = ref.read(homeRepositoryProvider);
    if (repository is! HomeDynamicRepository) return;
    if (repository.accountScope != scope) return;
    final generation = ++_generation;
    _cancellation?.cancel();
    final cancellation = _cancellation = RequestCancellation();
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        !cancellation.isCancelled &&
        repository.accountScope == scope;
    if (refresh) {
      _cursor = null;
      _seenCursors.clear();
    }
    state = DynamicAuthorsState(
      items: state.items,
      selected: state.selected,
      loading: true,
      hasMore: state.hasMore,
    );
    try {
      final page = await (repository as HomeDynamicRepository)
          .loadDynamicAuthors(
            scope: scope,
            cursor: _cursor,
            cancellation: cancellation,
          );
      if (!current()) return;
      final next = page.nextCursor;
      if (page.hasMore &&
          (next == null || next.isEmpty || _seenCursors.contains(next))) {
        throw const AppFailure(AppFailureKind.protocol, 'UP 主列表分页没有前进，请重试');
      }
      // Portal/uplist provide recent-update order. Deduplicate without sorting
      // by name, visit frequency or a timestamp inferred from unread status.
      final unique = <UserId, DynamicAuthor>{
        if (!refresh)
          for (final item in state.items) item.id: item,
      };
      for (final item in page.items) {
        if (unique.length >= maxAuthors && !unique.containsKey(item.id)) break;
        unique[item.id] = item;
      }
      if (!refresh && page.hasMore && unique.length == state.items.length) {
        throw const AppFailure(AppFailureKind.protocol, '没有新的 UP 主，可重试继续加载');
      }
      _cursor = next;
      if (next != null) _seenCursors.add(next);
      final selected = state.selected;
      state = DynamicAuthorsState(
        items: List.unmodifiable(unique.values),
        // An explicit selection survives refresh even if it moves to a later
        // author page. It stays visible through the selector's pinned entry.
        selected: unique[selected?.id] ?? selected,
        hasMore: page.hasMore && unique.length < maxAuthors,
      );
    } catch (error) {
      if (!current() ||
          error is AppFailure && error.kind == AppFailureKind.cancelled) {
        return;
      }
      state = DynamicAuthorsState(
        items: state.items,
        selected: state.selected,
        error: error,
        hasMore: state.hasMore,
      );
    }
  }
}
