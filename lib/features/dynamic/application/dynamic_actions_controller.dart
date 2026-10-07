import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_repository.dart';

final dynamicRepositoryProvider = Provider<DynamicRepository?>((ref) => null);
final dynamicActionsProvider = NotifierProvider.autoDispose
    .family<DynamicActionsController, DynamicActionsState, String>(
      DynamicActionsController.new,
    );

final class DynamicActionsState {
  const DynamicActionsState({
    this.signedIn = false,
    this.accountScope = 'guest',
    this.sessionEpoch = 0,
    this.busy = false,
    this.liked,
    this.likeCount,
    this.repostCount,
    this.detail,
    this.likeUncertain = false,
    this.repostUncertain = false,
    this.message,
  });
  final String accountScope;
  final int sessionEpoch;
  final bool signedIn, busy, likeUncertain, repostUncertain;
  final bool? liked;
  final int? likeCount, repostCount;
  final DynamicPost? detail;
  final String? message;
  DynamicActionsState copy({
    bool? busy,
    bool? liked,
    int? likeCount,
    int? repostCount,
    DynamicPost? detail,
    bool? likeUncertain,
    bool? repostUncertain,
    String? message,
  }) => DynamicActionsState(
    signedIn: signedIn,
    accountScope: accountScope,
    sessionEpoch: sessionEpoch,
    busy: busy ?? this.busy,
    liked: liked ?? this.liked,
    likeCount: likeCount ?? this.likeCount,
    repostCount: repostCount ?? this.repostCount,
    detail: detail ?? this.detail,
    likeUncertain: likeUncertain ?? this.likeUncertain,
    repostUncertain: repostUncertain ?? this.repostUncertain,
    message: message,
  );
}

class DynamicActionsController extends Notifier<DynamicActionsState> {
  DynamicActionsController(this.id);
  final String id;
  RequestCancellation _request = RequestCancellation();
  int _generation = 0;

  @override
  DynamicActionsState build() {
    final repository = ref.watch(dynamicRepositoryProvider);
    final signedIn =
        repository != null && ref.watch(authControllerProvider).isSignedIn;
    _request.cancel();
    ++_generation;
    ref.onDispose(() {
      ++_generation;
      _request.cancel();
    });
    return DynamicActionsState(
      signedIn: signedIn,
      accountScope: repository?.accountScope ?? 'guest',
      sessionEpoch: repository?.sessionEpoch ?? 0,
    );
  }

  bool _current(
    int generation,
    DynamicRepository repository,
    String scope,
    int epoch,
  ) =>
      ref.mounted &&
      generation == _generation &&
      repository.accountScope == scope &&
      repository.sessionEpoch == epoch;

  Future<bool> _perform(
    String action,
    Future<void> Function(DynamicRepository, RequestCancellation) operation, {
    bool write = true,
  }) async {
    if (state.busy ||
        (write && !state.signedIn) ||
        (action == 'like' && state.likeUncertain) ||
        (action == 'repost' && state.repostUncertain)) {
      return false;
    }
    final repository = ref.read(dynamicRepositoryProvider);
    if (repository == null) {
      state = state.copy(message: '动态服务暂不可用');
      return false;
    }
    final generation = ++_generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    _request.cancel();
    _request = RequestCancellation();
    state = state.copy(busy: true);
    try {
      await operation(repository, _request);
      if (!_current(generation, repository, scope, epoch)) return false;
      state = state.copy(busy: false);
      return true;
    } catch (error) {
      if (!_current(generation, repository, scope, epoch)) return false;
      final uncertain = error is DynamicWriteUncertain;
      state = state.copy(
        busy: false,
        likeUncertain: uncertain && action == 'like' ? true : null,
        repostUncertain: uncertain && action == 'repost' ? true : null,
        message: uncertain
            ? '结果暂时无法确认，请核对后再操作，未自动重试。'
            : error is AppFailure
            ? error.kind == AppFailureKind.cancelled
                  ? null
                  : error.message
            : '动态操作失败，请稍后重试',
      );
      return false;
    }
  }

  Future<bool> toggleLike(DynamicPost post) async {
    if (post.unavailable || post.likeForbidden || post.id != id) return false;
    final liked = !(state.liked ?? post.liked);
    final count = state.likeCount ?? post.likeCount;
    if (!await _perform(
      'like',
      (repository, cancellation) => repository.like(id, liked, cancellation),
    )) {
      return false;
    }
    state = state.copy(
      liked: liked,
      likeCount: count == null
          ? null
          : (count + (liked ? 1 : -1)).clamp(0, 0x7fffffffffffffff),
    );
    return true;
  }

  Future<bool> refresh() async {
    DynamicPost? post;
    if (!await _perform('read', (repository, cancellation) async {
      post = await repository.detail(id, cancellation);
    }, write: false)) {
      return false;
    }
    final value = post;
    if (value == null || value.id != id) return false;
    state = DynamicActionsState(
      signedIn: state.signedIn,
      accountScope: state.accountScope,
      sessionEpoch: state.sessionEpoch,
      detail: value,
      liked: value.liked,
      likeCount: value.likeCount,
      repostCount: value.repostCount,
      repostUncertain: state.repostUncertain,
    );
    return true;
  }

  Future<bool> repost(DynamicPost post, String text) async {
    if (post.unavailable ||
        post.repostForbidden ||
        post.id != id ||
        text.runes.length > 1000) {
      return false;
    }
    if (!await _perform('repost', (repository, cancellation) async {
      await repository.repost(id, text, cancellation);
    })) {
      return false;
    }
    final count = state.repostCount ?? post.repostCount;
    state = state.copy(
      repostCount: count == null ? null : count + 1,
      message: '动态已转发',
    );
    return true;
  }

  void acknowledgeRepost() => state = state.copy(repostUncertain: false);
}
