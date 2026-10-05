import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/video_actions_repository.dart';

final videoActionsRepositoryProvider = Provider<VideoActionsRepository>(
  (ref) => throw UnimplementedError('VideoActionsRepository'),
);
final videoActionsControllerProvider = NotifierProvider.autoDispose
    .family<VideoActionsController, VideoActionsState, VideoActionTarget>(
      VideoActionsController.new,
    );

final class VideoActionsState {
  const VideoActionsState({
    this.interaction = const VideoInteraction(),
    this.loading = false,
    this.loaded = false,
    this.signedIn = false,
    this.busy = false,
    this.watchLaterAdded = false,
    this.message,
    this.uncertain = const {},
  });
  final VideoInteraction interaction;
  final bool loading, loaded, signedIn, busy, watchLaterAdded;
  final String? message;
  final Set<String> uncertain;
  VideoActionsState copyWith({
    VideoInteraction? interaction,
    bool? loading,
    bool? loaded,
    bool? busy,
    bool? watchLaterAdded,
    String? message,
    Set<String>? uncertain,
  }) => VideoActionsState(
    interaction: interaction ?? this.interaction,
    loading: loading ?? this.loading,
    loaded: loaded ?? this.loaded,
    signedIn: signedIn,
    busy: busy ?? this.busy,
    watchLaterAdded: watchLaterAdded ?? this.watchLaterAdded,
    message: message,
    uncertain: uncertain ?? this.uncertain,
  );
}

class VideoActionsController extends Notifier<VideoActionsState> {
  VideoActionsController(this.target);
  final VideoActionTarget target;
  RequestCancellation _cancellation = RequestCancellation();
  int _generation = 0;
  @override
  VideoActionsState build() {
    final auth = ref.watch(authControllerProvider);
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancellation.cancel();
    });
    if (auth.isSignedIn) Future<void>.microtask(refresh);
    return VideoActionsState(
      signedIn: auth.isSignedIn,
      loading: auth.isSignedIn,
    );
  }

  bool _current(int generation, String scope) =>
      ref.mounted &&
      generation == _generation &&
      ref.read(videoActionsRepositoryProvider).accountScope == scope;
  Future<void> refresh() async {
    if (!ref.mounted || !state.signedIn || state.busy) return;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    final repo = ref.read(videoActionsRepositoryProvider);
    final scope = repo.accountScope;
    state = state.copyWith(loading: true);
    try {
      final value = await repo.load(target, _cancellation);
      if (!_current(generation, scope)) return;
      // Reads reconcile like/coin/favorites; sending cannot be reconciled by these reads.
      state = state.copyWith(
        interaction: value,
        loading: false,
        loaded: true,
        uncertain: Set.unmodifiable(
          state.uncertain.where((a) => a == 'send' || a == 'watchLater'),
        ),
      );
    } catch (e) {
      if (!_current(generation, scope)) return;
      if (_cancelled(e)) {
        state = state.copyWith(loading: false);
        return;
      }
      state = state.copyWith(loading: false, message: _message(e));
    }
  }

  Future<List<FavoriteFolder>> folders() {
    if (!state.signedIn) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    return ref
        .read(videoActionsRepositoryProvider)
        .folders(target, _cancellation);
  }

  Future<bool> _perform(
    String action,
    Future<void> Function(VideoActionsRepository, RequestCancellation)
    operation,
    VideoActionsState Function(VideoActionsState) success,
  ) async {
    if (!state.signedIn || state.busy || state.uncertain.contains(action)) {
      return false;
    }
    final repo = ref.read(videoActionsRepositoryProvider);
    final scope = repo.accountScope;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = state.copyWith(busy: true, loading: false);
    try {
      await operation(repo, _cancellation);
      if (!_current(generation, scope)) return false;
      state = success(state).copyWith(busy: false, message: '操作成功');
      return true;
    } catch (e) {
      if (!_current(generation, scope)) return false;
      if (_cancelled(e)) {
        state = state.copyWith(busy: false, loading: false);
        return false;
      }
      state = state.copyWith(
        busy: false,
        message: e is UnknownWriteOutcome
            ? '结果暂时无法确认，未自动重试。请核对状态后再操作。'
            : _message(e),
        uncertain: e is UnknownWriteOutcome
            ? Set.unmodifiable({...state.uncertain, action})
            : state.uncertain,
      );
      return false;
    }
  }

  Future<bool> toggleLike() {
    if (!state.loaded) return Future.value(false);
    final liked = !state.interaction.liked;
    return _perform(
      'like',
      (r, c) => r.like(target, liked, c),
      (s) => s.copyWith(interaction: s.interaction.copyWith(liked: liked)),
    );
  }

  Future<bool> coin(int count) {
    if (!state.loaded ||
        count < 1 ||
        count > 2 ||
        state.interaction.coins + count > 2) {
      return Future.value(false);
    }
    return _perform(
      'coin',
      (r, c) => r.coin(target, count, c),
      (s) => s.copyWith(
        interaction: s.interaction.copyWith(coins: s.interaction.coins + count),
      ),
    );
  }

  Future<bool> favorite(List<FavoriteFolder> folders, Set<String> selected) {
    final initial = folders
        .where((f) => f.containsVideo)
        .map((f) => f.id)
        .toSet();
    return _perform(
      'favorite',
      (r, c) => r.favorite(
        target,
        selected.difference(initial).toList(),
        initial.difference(selected).toList(),
        c,
      ),
      (s) => s.copyWith(
        interaction: s.interaction.copyWith(favorited: selected.isNotEmpty),
      ),
    );
  }

  Future<bool> watchLater() => _perform(
    'watchLater',
    (r, c) => r.watchLater(target, c),
    (s) => s.copyWith(watchLaterAdded: true),
  );
  Future<bool> send(
    String cid,
    String message,
    Duration position,
    int mode,
    int color,
  ) => _perform(
    'send',
    (r, c) => r.sendDanmaku(target, cid, message, position, mode, color, c),
    (s) => s,
  );
  static bool _cancelled(Object e) =>
      e is AppFailure && e.kind == AppFailureKind.cancelled;
  static String _message(Object e) =>
      e is AppFailure ? e.message : '操作失败，请稍后重试';
}
