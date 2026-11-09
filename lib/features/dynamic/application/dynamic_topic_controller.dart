import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_topic_repository.dart';

final dynamicTopicRepositoryProvider = Provider<DynamicTopicRepository?>(
  (ref) => null,
);
final dynamicTopicProvider = NotifierProvider.autoDispose
    .family<DynamicTopicController, DynamicTopicState, String>(
      DynamicTopicController.new,
    );

final class DynamicTopicState {
  const DynamicTopicState({
    this.detail,
    this.posts = const [],
    this.sorts = const [],
    this.sort = 0,
    this.loading = false,
    this.hasMore = false,
    this.error,
    this.foldDescription = '',
    this.foldLoading = false,
    this.foldError,
  });
  final DynamicTopicDetail? detail;
  final List<DynamicPost> posts;
  final List<DynamicTopicSort> sorts;
  final int sort;
  final bool loading, hasMore, foldLoading;
  final Object? error, foldError;
  final String foldDescription;

  DynamicTopicState copy({
    DynamicTopicDetail? detail,
    List<DynamicPost>? posts,
    List<DynamicTopicSort>? sorts,
    int? sort,
    bool? loading,
    bool? hasMore,
    Object? error,
    String? foldDescription,
    bool? foldLoading,
    Object? foldError,
  }) => DynamicTopicState(
    detail: detail ?? this.detail,
    posts: posts ?? this.posts,
    sorts: sorts ?? this.sorts,
    sort: sort ?? this.sort,
    loading: loading ?? this.loading,
    hasMore: hasMore ?? this.hasMore,
    error: error,
    foldDescription: foldDescription ?? this.foldDescription,
    foldLoading: foldLoading ?? this.foldLoading,
    foldError: foldError,
  );
}

class DynamicTopicController extends Notifier<DynamicTopicState> {
  DynamicTopicController(this.id);
  static const maximumPosts = 500;
  final String id;
  RequestCancellation? _request, _foldRequest;
  int _generation = 0;
  String? _cursor;
  final _seenCursors = <String>{};
  bool _foldLoaded = false;
  bool _failedFirst = true, _failedHeader = true;

  @override
  DynamicTopicState build() {
    ref.watch(dynamicTopicRepositoryProvider);
    ref.watch(
      authControllerProvider.select((value) => (value.status, value.mid)),
    );
    ref.onDispose(() {
      _generation++;
      _request?.cancel();
      _foldRequest?.cancel();
    });
    Future<void>.microtask(refresh);
    return const DynamicTopicState(loading: true);
  }

  Future<void> refresh() => _load(first: true, header: true);
  Future<void> retry() => _load(first: _failedFirst, header: _failedHeader);
  Future<void> loadMore() =>
      !state.loading && state.hasMore ? _load(first: false) : Future.value();
  Future<void> selectSort(int sort) async {
    if (sort == state.sort ||
        sort < 0 ||
        sort > 255 ||
        state.sorts.isNotEmpty && !state.sorts.any((s) => s.id == sort)) {
      return;
    }
    state = state.copy(
      sort: sort,
      posts: const [],
      hasMore: false,
      foldDescription: '',
    );
    await _load(first: true, header: state.detail == null);
  }

  Future<void> _load({required bool first, bool header = false}) async {
    if (!ref.mounted) return;
    final repository = ref.read(dynamicTopicRepositoryProvider);
    if (repository == null) {
      state = state.copy(
        loading: false,
        error: const AppFailure(AppFailureKind.unknown, '话题服务暂不可用'),
      );
      return;
    }
    final generation = ++_generation;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    _request?.cancel();
    _foldRequest?.cancel();
    final request = _request = RequestCancellation();
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        !request.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch;
    if (first) {
      _cursor = null;
      _seenCursors.clear();
      _foldLoaded = false;
    }
    final sort = state.sort;
    _failedFirst = first;
    _failedHeader = header;
    state = state.copy(loading: true, foldLoading: false);
    try {
      final Future<DynamicTopicDetail?> detailRequest = header
          ? repository.detail(id, request)
          : Future<DynamicTopicDetail?>.value(state.detail);
      final results = await Future.wait<Object?>([
        detailRequest,
        repository.feed(
          id,
          sort: sort,
          cursor: first ? null : _cursor,
          cancellation: request,
        ),
      ], eagerError: true);
      final detail = results[0] as DynamicTopicDetail?;
      final page = results[1] as DynamicTopicPage;
      if (!current()) return;
      if (detail != null && detail.id != id) {
        throw const AppFailure(AppFailureKind.protocol, '话题身份不匹配');
      }
      final cursor = page.nextCursor;
      if (page.hasMore &&
          (cursor == null || cursor.isEmpty || _seenCursors.contains(cursor))) {
        throw const AppFailure(AppFailureKind.protocol, '话题分页没有前进，请重试');
      }
      final posts = _merge(first ? const [] : state.posts, page.posts);
      if (!first && page.hasMore && posts.length == state.posts.length) {
        throw const AppFailure(AppFailureKind.protocol, '没有新的动态，请刷新或重试');
      }
      _cursor = cursor;
      if (cursor != null) _seenCursors.add(cursor);
      final selected = page.selectedSort;
      state = state.copy(
        detail: detail,
        posts: posts,
        sorts: page.sorts.isEmpty ? state.sorts : page.sorts,
        sort:
            first && selected != null && page.sorts.any((s) => s.id == selected)
            ? selected
            : sort,
        loading: false,
        hasMore: page.hasMore && posts.length < maximumPosts,
        foldDescription: _foldLoaded
            ? ''
            : page.foldDescription.isEmpty && !first
            ? state.foldDescription
            : page.foldDescription,
      );
    } catch (error) {
      if (!current()) return;
      request.cancel();
      state = state.copy(
        loading: false,
        error: error is AppFailure && error.kind == AppFailureKind.cancelled
            ? null
            : error,
      );
    }
  }

  Future<void> loadFolded() async {
    if (state.loading ||
        state.foldLoading ||
        _foldLoaded ||
        state.foldDescription.isEmpty) {
      return;
    }
    final repository = ref.read(dynamicTopicRepositoryProvider);
    if (repository == null) return;
    final generation = _generation;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final request = _foldRequest = RequestCancellation();
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        !request.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch;
    state = state.copy(foldLoading: true);
    try {
      final page = await repository.feed(
        id,
        sort: state.sort,
        folded: true,
        cancellation: request,
      );
      if (!current()) return;
      _foldLoaded = true;
      final posts = _merge(state.posts, page.posts);
      state = state.copy(
        posts: posts,
        foldLoading: false,
        foldDescription: '',
        hasMore: state.hasMore && posts.length < maximumPosts,
      );
    } catch (error) {
      if (current()) {
        state = state.copy(
          foldLoading: false,
          foldError:
              error is AppFailure && error.kind == AppFailureKind.cancelled
              ? null
              : error,
        );
      }
    }
  }

  List<DynamicPost> _merge(
    List<DynamicPost> previous,
    List<DynamicPost> incoming,
  ) {
    final unique = {for (final post in previous) post.id: post};
    for (final post in incoming) {
      if (unique.length >= maximumPosts && !unique.containsKey(post.id)) break;
      unique[post.id] = post;
    }
    return List.unmodifiable(unique.values);
  }
}
