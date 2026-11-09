import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_topic_repository.dart';
import '../domain/dynamic_repository.dart';

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
    this.actionBusy = false,
    this.favoriteUncertain = false,
    this.reportUncertain = false,
    this.reported = false,
    this.actionMessage,
  });
  final DynamicTopicDetail? detail;
  final List<DynamicPost> posts;
  final List<DynamicTopicSort> sorts;
  final int sort;
  final bool loading, hasMore, foldLoading;
  final Object? error, foldError;
  final String foldDescription;
  final bool actionBusy, favoriteUncertain, reportUncertain, reported;
  final String? actionMessage;

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
    bool? actionBusy,
    bool? favoriteUncertain,
    bool? reportUncertain,
    bool? reported,
    String? actionMessage,
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
    actionBusy: actionBusy ?? this.actionBusy,
    favoriteUncertain: favoriteUncertain ?? this.favoriteUncertain,
    reportUncertain: reportUncertain ?? this.reportUncertain,
    reported: reported ?? this.reported,
    actionMessage: actionMessage,
  );
}

class DynamicTopicController extends Notifier<DynamicTopicState> {
  DynamicTopicController(this.id);
  static const maximumPosts = 500;
  final String id;
  RequestCancellation? _request, _foldRequest;
  RequestCancellation? _actionRequest;
  int _actionGeneration = 0;
  int _generation = 0;
  String? _cursor;
  final _seenCursors = <String>{};
  bool _foldLoaded = false;
  bool _failedFirst = true, _failedHeader = true;

  @override
  DynamicTopicState build() {
    final repository = ref.watch(dynamicTopicRepositoryProvider);
    ref.watch(
      authControllerProvider.select(
        (value) => (value.status, value.mid, repository?.sessionEpoch ?? 0),
      ),
    );
    ref.onDispose(() {
      _generation++;
      _request?.cancel();
      _foldRequest?.cancel();
      _actionRequest?.cancel();
      _actionGeneration++;
    });
    Future<void>.microtask(refresh);
    return const DynamicTopicState(loading: true);
  }

  Future<void> refresh() =>
      state.actionBusy ? Future.value() : _load(first: true, header: true);
  Future<void> retry() => _load(first: _failedFirst, header: _failedHeader);
  Future<void> loadMore() =>
      !state.loading && state.hasMore ? _load(first: false) : Future.value();
  Future<void> selectSort(int sort) async {
    if (state.actionBusy ||
        sort == state.sort ||
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
    if (!ref.mounted || state.actionBusy) return;
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
        favoriteUncertain: header ? false : null,
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

  Future<bool> toggleFavorite() async {
    final detail = state.detail;
    if (detail == null || state.favoriteUncertain) return false;
    final value = !detail.isFavorite;
    if (!await _action(
      (repository, request) => repository.favorite(id, value, request),
      favorite: true,
    )) {
      return false;
    }
    state = state.copy(detail: state.detail?.withFavorite(value));
    return true;
  }

  Future<bool> report(String reason) async {
    if (state.reported ||
        state.reportUncertain ||
        reason.trim().isEmpty ||
        reason.runes.length > 1000) {
      return false;
    }
    if (!await _action(
      (repository, request) => repository.report(id, reason, request),
      favorite: false,
    )) {
      return false;
    }
    state = state.copy(reported: true);
    return true;
  }

  Future<bool> _action(
    Future<void> Function(DynamicTopicRepository, RequestCancellation)
    operation, {
    required bool favorite,
  }) async {
    if (state.actionBusy ||
        state.loading ||
        !ref.read(authControllerProvider).isSignedIn) {
      return false;
    }
    final repository = ref.read(dynamicTopicRepositoryProvider);
    if (repository == null) return false;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    final generation = ++_actionGeneration;
    final request = _actionRequest = RequestCancellation();
    bool current() =>
        ref.mounted &&
        generation == _actionGeneration &&
        !request.isCancelled &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch;
    state = state.copy(actionBusy: true);
    try {
      await operation(repository, request);
      if (!current()) return false;
      state = state.copy(actionBusy: false);
      return true;
    } catch (error) {
      if (!current()) return false;
      final uncertain = error is DynamicWriteUncertain;
      state = state.copy(
        actionBusy: false,
        favoriteUncertain: favorite && uncertain ? true : null,
        reportUncertain: !favorite && uncertain ? true : null,
        actionMessage: uncertain
            ? favorite
                  ? '收藏结果暂未确认，请刷新话题后核对。'
                  : '举报结果暂未确认，请勿重复提交。'
            : error is AppFailure
            ? error.kind == AppFailureKind.cancelled
                  ? null
                  : error.message
            : '操作失败，请稍后重试',
      );
      return false;
    }
  }
}
