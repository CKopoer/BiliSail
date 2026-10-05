import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/video_comments_repository.dart';

final videoCommentsRepositoryProvider = Provider<VideoCommentsRepository>(
  (ref) => throw UnimplementedError('VideoCommentsRepository'),
);
final videoCommentsControllerProvider = NotifierProvider.autoDispose
    .family<VideoCommentsController, VideoCommentsState, String>(
      VideoCommentsController.new,
    );

final class VideoCommentsState {
  const VideoCommentsState({
    this.emotePackages = const [],
    this.emotesLoading = false,
    this.emotesMessage,
    this.items = const [],
    this.sort = CommentSort.hot,
    this.page = 0,
    this.totalCount,
    this.hasMore = true,
    this.loading = false,
    this.signedIn = false,
    this.busy = false,
    this.message,
    this.openRoot,
    this.replyItems = const [],
    this.replyPage = 0,
    this.replyHasMore = false,
    this.replyLoading = false,
    this.replyTarget,
    this.uncertain = const {},
  });
  final List<CommentEmotePackage> emotePackages;
  final bool emotesLoading;
  final String? emotesMessage;
  final List<CommentEntry> items, replyItems;
  final CommentSort sort;
  final int page, replyPage;
  final int? totalCount;
  final bool hasMore, loading, signedIn, busy, replyHasMore, replyLoading;
  final String? message;
  final CommentEntry? openRoot, replyTarget;
  final Set<String> uncertain;
  VideoCommentsState copy({
    List<CommentEmotePackage>? emotePackages,
    bool? emotesLoading,
    String? emotesMessage,
    List<CommentEntry>? items,
    CommentSort? sort,
    int? page,
    int? totalCount,
    bool? hasMore,
    bool? loading,
    bool? busy,
    String? message,
    CommentEntry? openRoot,
    bool closeRoot = false,
    List<CommentEntry>? replyItems,
    int? replyPage,
    bool? replyHasMore,
    bool? replyLoading,
    CommentEntry? replyTarget,
    bool clearTarget = false,
    Set<String>? uncertain,
  }) => VideoCommentsState(
    emotePackages: emotePackages ?? this.emotePackages,
    emotesLoading: emotesLoading ?? this.emotesLoading,
    emotesMessage: emotesMessage,
    items: items ?? this.items,
    sort: sort ?? this.sort,
    page: page ?? this.page,
    totalCount: totalCount ?? this.totalCount,
    hasMore: hasMore ?? this.hasMore,
    loading: loading ?? this.loading,
    signedIn: signedIn,
    busy: busy ?? this.busy,
    message: message,
    openRoot: closeRoot ? null : openRoot ?? this.openRoot,
    replyItems: replyItems ?? this.replyItems,
    replyPage: replyPage ?? this.replyPage,
    replyHasMore: replyHasMore ?? this.replyHasMore,
    replyLoading: replyLoading ?? this.replyLoading,
    replyTarget: clearTarget ? null : replyTarget ?? this.replyTarget,
    uncertain: uncertain ?? this.uncertain,
  );
}

class VideoCommentsController extends Notifier<VideoCommentsState> {
  VideoCommentsController(this.aid);
  final String aid;
  RequestCancellation _read = RequestCancellation(),
      _replies = RequestCancellation(),
      _write = RequestCancellation();
  RequestCancellation _emotes = RequestCancellation();
  int _emoteGeneration = 0;
  int _generation = 0, _replyGeneration = 0;
  @override
  VideoCommentsState build() {
    final auth = ref.watch(authControllerProvider);
    _cancel();
    final generation = ++_generation;
    ++_replyGeneration;
    ref.onDispose(() {
      ++_generation;
      ++_replyGeneration;
      _cancel();
    });
    Future<void>.microtask(() {
      if (ref.mounted && generation == _generation) return load();
    });
    return VideoCommentsState(signedIn: auth.isSignedIn);
  }

  void _cancel() {
    _read.cancel();
    _replies.cancel();
    _write.cancel();
    _emotes.cancel();
    ++_emoteGeneration;
  }

  bool _current(int generation, String scope, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final r = ref.read(videoCommentsRepositoryProvider);
    return r.accountScope == scope && r.sessionEpoch == epoch;
  }

  static List<CommentEntry> _merge(
    List<CommentEntry> old,
    List<CommentEntry> next,
  ) => List.unmodifiable(
    {
      for (final c in [...old, ...next]) c.id: c,
    }.values.take(500),
  );
  static String? _error(Object e) => e is AppFailure
      ? e.kind == AppFailureKind.cancelled
            ? null
            : e.message
      : '评论加载失败，请稍后重试';
  Future<void> load({CommentSort? sort, bool refresh = false}) async {
    if (!ref.mounted || state.busy) return;
    final reset = refresh || sort != null;
    if (!reset &&
        (state.loading || !state.hasMore || state.items.length >= 500)) {
      return;
    }
    _read.cancel();
    _read = RequestCancellation();
    final generation = ++_generation;
    final r = ref.read(videoCommentsRepositoryProvider),
        selected = sort ?? state.sort;
    final scope = r.accountScope, epoch = r.sessionEpoch;
    final page = reset ? 1 : state.page + 1;
    state = state.copy(
      sort: selected,
      loading: true,
      items: reset ? [] : null,
      page: reset ? 0 : null,
      closeRoot: reset,
      clearTarget: reset,
    );
    try {
      final p = await r.load(aid, page, selected, _read);
      if (!_current(generation, scope, epoch)) return;
      final items = _merge(reset ? [] : state.items, p.items);
      state = state.copy(
        items: items,
        page: page,
        totalCount: p.totalCount,
        hasMore: p.hasMore && p.items.isNotEmpty && items.length < 500,
        loading: false,
        uncertain: Set.unmodifiable(
          state.uncertain.where(
            (v) => !p.items.any((c) => v == 'like:${c.id}'),
          ),
        ),
      );
    } catch (e) {
      if (_current(generation, scope, epoch)) {
        state = state.copy(loading: false, message: _error(e));
      }
    }
  }

  Future<void> openReplies(CommentEntry root) async {
    if (state.busy) return;
    _replies.cancel();
    ++_replyGeneration;
    state = state.copy(
      openRoot: root,
      replyItems: [],
      replyPage: 0,
      replyHasMore: true,
      replyLoading: false,
      clearTarget: true,
    );
    await loadReplies();
  }

  void closeReplies() {
    _replies.cancel();
    ++_replyGeneration;
    state = state.copy(closeRoot: true, clearTarget: true, replyLoading: false);
  }

  Future<void> loadReplies() async {
    final root = state.openRoot;
    if (root == null ||
        state.replyLoading ||
        !state.replyHasMore ||
        state.busy) {
      return;
    }
    _replies = RequestCancellation();
    final generation = _generation, replyGeneration = ++_replyGeneration;
    final r = ref.read(videoCommentsRepositoryProvider),
        scope = r.accountScope,
        epoch = r.sessionEpoch;
    final page = state.replyPage + 1;
    state = state.copy(replyLoading: true);
    try {
      final p = await r.replies(aid, root.id, page, _replies);
      if (!_current(generation, scope, epoch) ||
          replyGeneration != _replyGeneration) {
        return;
      }
      final items = _merge(state.replyItems, p.items);
      state = state.copy(
        replyItems: items,
        replyPage: page,
        replyHasMore: p.hasMore && p.items.isNotEmpty && items.length < 500,
        replyLoading: false,
        uncertain: Set.unmodifiable(
          state.uncertain.where(
            (v) => !p.items.any((c) => v == 'like:${c.id}'),
          ),
        ),
      );
    } catch (e) {
      if (_current(generation, scope, epoch) &&
          replyGeneration == _replyGeneration) {
        state = state.copy(replyLoading: false, message: _error(e));
      }
    }
  }

  Future<void> loadEmotes() async {
    if (state.emotesLoading || state.emotePackages.isNotEmpty) return;
    final r = ref.read(videoCommentsRepositoryProvider);
    if (r is! CommentEmotesRepository) {
      state = state.copy(emotesMessage: '表情服务暂不可用');
      return;
    }
    final scope = r.accountScope,
        epoch = r.sessionEpoch,
        generation = ++_emoteGeneration;
    _emotes.cancel();
    _emotes = RequestCancellation();
    state = state.copy(emotesLoading: true);
    bool current() =>
        ref.mounted &&
        generation == _emoteGeneration &&
        r.accountScope == scope &&
        r.sessionEpoch == epoch;
    try {
      final packages = await (r as CommentEmotesRepository).emotes(_emotes);
      if (current()) {
        state = state.copy(
          emotePackages: packages,
          emotesLoading: false,
          emotesMessage: packages.isEmpty ? '暂无可用表情' : null,
        );
      }
    } catch (e) {
      if (current()) {
        state = state.copy(emotesLoading: false, emotesMessage: _error(e));
      }
    }
  }

  void target(CommentEntry entry) => state = state.copy(replyTarget: entry);
  void cancelTarget() => state = state.copy(clearTarget: true);
  void acknowledgeSend() => state = state.copy(
    uncertain: Set.unmodifiable(state.uncertain.where((v) => v != 'send')),
  );
  Future<bool> _perform(
    String key,
    Future<void> Function(VideoCommentsRepository) operation,
  ) async {
    if (!state.signedIn ||
        state.busy ||
        state.loading ||
        state.replyLoading ||
        state.uncertain.contains(key)) {
      return false;
    }
    final r = ref.read(videoCommentsRepositoryProvider),
        scope = r.accountScope,
        epoch = r.sessionEpoch,
        generation = _generation;
    _write = RequestCancellation();
    state = state.copy(busy: true);
    try {
      await operation(r);
      if (!_current(generation, scope, epoch)) return false;
      state = state.copy(busy: false);
      return true;
    } catch (e) {
      if (!_current(generation, scope, epoch)) return false;
      state = state.copy(
        busy: false,
        message: e is CommentWriteUncertain
            ? '结果暂时无法确认，请核对评论后再操作，未自动重试。'
            : _error(e),
        uncertain: e is CommentWriteUncertain
            ? Set.unmodifiable({...state.uncertain, key})
            : null,
      );
      return false;
    }
  }

  Future<bool> toggleLike(CommentEntry comment) async {
    final liked = !comment.liked;
    final result = await _perform(
      'like:${comment.id}',
      (r) => r.like(aid, comment.id, liked, _write),
    );
    if (!result) return false;
    CommentEntry update(CommentEntry c) => c.id == comment.id
        ? c.withLike(liked)
        : c.withReplies(c.replies.map(update).toList());
    state = state.copy(
      items: state.items.map(update).toList(),
      replyItems: state.replyItems.map(update).toList(),
      openRoot: state.openRoot == null ? null : update(state.openRoot!),
    );
    return true;
  }

  Future<bool> send(String message) async {
    final text = message.trim();
    if (text.isEmpty || text.length > 1000) return false;
    final target = state.replyTarget;
    final rootId =
        state.openRoot?.id ??
        (target == null ? null : target.rootId ?? target.id);
    final parentId = target?.id ?? rootId;
    CommentEntry? sent;
    final ok = await _perform('send', (r) async {
      sent = await r.send(
        aid,
        text,
        rootId: rootId,
        parentId: parentId,
        cancellation: _write,
      );
    });
    final entry = sent;
    if (!ok || entry == null) return false;
    if (rootId == null) {
      state = state.copy(
        items: _merge([entry], state.items),
        totalCount: (state.totalCount ?? state.items.length) + 1,
        clearTarget: true,
        message: '评论已发送',
      );
    } else {
      CommentEntry update(CommentEntry c) => c.id == rootId
          ? c.withReplies(_merge(c.replies, [entry]), count: c.replyCount + 1)
          : c;
      state = state.copy(
        items: state.items.map(update).toList(),
        openRoot: state.openRoot == null ? null : update(state.openRoot!),
        replyItems: _merge(state.replyItems, [entry]),
        clearTarget: true,
        message: '回复已发送',
      );
    }
    return true;
  }
}
