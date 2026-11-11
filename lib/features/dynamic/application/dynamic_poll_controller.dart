import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_poll.dart';
import '../domain/dynamic_poll_repository.dart';
import '../domain/dynamic_repository.dart';
import 'dynamic_actions_controller.dart';
import 'dynamic_content_state.dart';

final dynamicPollRepositoryProvider = Provider<DynamicPollRepository?>((ref) {
  final repository = ref.watch(dynamicRepositoryProvider);
  return switch (repository) {
    final DynamicPollRepository polls => polls,
    _ => null,
  };
});
final dynamicPollClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);
final dynamicPollProvider = NotifierProvider.autoDispose
    .family<DynamicPollController, DynamicPollState, String>(
      DynamicPollController.new,
    );

final class DynamicPollState {
  DynamicPollState({
    this.poll,
    this.signedIn = false,
    this.loading = false,
    this.submitting = false,
    this.uncertain = false,
    this.anonymous = false,
    this.showResults = false,
    this.followees = const [],
    this.canConfirmNotVoted = false,
    Set<int> selected = const {},
    this.message,
  }) : selected = Set.unmodifiable(selected);
  final DynamicPoll? poll;
  final bool signedIn, loading, submitting, uncertain, anonymous, showResults;
  final Set<int> selected;
  final String? message;
  final List<DynamicPollFollowee> followees;
  final bool canConfirmNotVoted;
  bool get busy => loading || submitting;
  DynamicPollState copy({
    DynamicPoll? poll,
    bool? loading,
    bool? submitting,
    bool? uncertain,
    bool? anonymous,
    bool? showResults,
    Set<int>? selected,
    String? message,
    List<DynamicPollFollowee>? followees,
    bool? canConfirmNotVoted,
  }) => DynamicPollState(
    poll: poll ?? this.poll,
    signedIn: signedIn,
    loading: loading ?? this.loading,
    submitting: submitting ?? this.submitting,
    uncertain: uncertain ?? this.uncertain,
    anonymous: anonymous ?? this.anonymous,
    showResults: showResults ?? this.showResults,
    selected: selected ?? this.selected,
    message: message,
    followees: followees ?? this.followees,
    canConfirmNotVoted: canConfirmNotVoted ?? this.canConfirmNotVoted,
  );
}

class DynamicPollController extends Notifier<DynamicPollState> {
  DynamicPollController(this.id);
  final String id;
  RequestCancellation _request = RequestCancellation();
  int _generation = 0;
  String? _voterId;
  Timer? _expiry;

  @override
  DynamicPollState build() {
    final repository = ref.watch(dynamicPollRepositoryProvider);
    final auth = ref.watch(
      authControllerProvider.select(
        (s) => (s.isSignedIn, s.mid, repository?.sessionEpoch),
      ),
    );
    _voterId = auth.$1 ? auth.$2 : null;
    _request.cancel();
    _expiry?.cancel();
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _request.cancel();
      _expiry?.cancel();
    });
    scheduleMicrotask(() {
      if (ref.mounted && generation == _generation) unawaited(load());
    });
    return DynamicPollState(
      signedIn: repository != null && _voterId != null,
      uncertain:
          ref
              .read(dynamicContentProvider)
              .locked['poll:$id']
              ?.contains('vote') ==
          true,
    );
  }

  bool _current(
    int generation,
    DynamicPollRepository repository,
    String scope,
    int epoch,
  ) =>
      ref.mounted &&
      generation == _generation &&
      repository.accountScope == scope &&
      repository.sessionEpoch == epoch;

  Future<bool> _perform(
    bool write,
    Future<DynamicPoll> Function(DynamicPollRepository, RequestCancellation)
    action,
  ) async {
    if (state.busy || (write && (!state.signedIn || state.uncertain))) {
      return false;
    }
    final repository = ref.read(dynamicPollRepositoryProvider);
    if (repository == null) {
      state = state.copy(message: '投票服务暂不可用');
      return false;
    }
    final generation = ++_generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    if (write && scope != 'user:$_voterId') return false;
    _request.cancel();
    _request = RequestCancellation();
    state = state.copy(loading: !write, submitting: write);
    try {
      final poll = await action(repository, _request);
      if (!_current(generation, repository, scope, epoch)) return false;
      if (poll.id != id) {
        throw const AppFailure(AppFailureKind.protocol, '投票信息不匹配');
      }
      state = state.copy(
        poll: poll,
        loading: false,
        submitting: false,
        uncertain: state.uncertain && !poll.hasVoted,
        canConfirmNotVoted: !write && state.uncertain && !poll.hasVoted,
        selected: poll.myVotes,
        showResults:
            write ||
            poll.hasVoted ||
            poll.endedAt(ref.read(dynamicPollClockProvider)()),
        message: write ? '投票成功' : null,
      );
      if (poll.hasVoted) {
        ref.read(dynamicContentProvider.notifier).unlock('poll:$id', {'vote'});
      }
      _expiry?.cancel();
      final remaining = poll.endsAt.difference(
        ref.read(dynamicPollClockProvider)(),
      );
      if (remaining > Duration.zero && !poll.hasVoted) {
        _expiry = Timer(remaining, () {
          if (ref.mounted &&
              repository.accountScope == scope &&
              repository.sessionEpoch == epoch &&
              identical(state.poll, poll)) {
            state = state.copy(
              showResults: true,
              selected: state.poll?.myVotes,
            );
          }
        });
      }
      if (!write &&
          state.signedIn &&
          repository is DynamicPollSocialRepository) {
        try {
          final followees = await (repository as DynamicPollSocialRepository)
              .followees(id, _request);
          if (_current(generation, repository, scope, epoch)) {
            state = state.copy(followees: followees);
          }
        } on AppFailure {
          // Social context is optional and must not block poll participation.
        }
      }
      return _current(generation, repository, scope, epoch);
    } catch (error) {
      if (!_current(generation, repository, scope, epoch)) return false;
      final uncertain = write && error is DynamicWriteUncertain;
      if (uncertain) {
        ref.read(dynamicContentProvider.notifier).lock('poll:$id', 'vote');
      }
      state = state.copy(
        loading: false,
        submitting: false,
        uncertain: uncertain ? true : null,
        canConfirmNotVoted: false,
        message: uncertain
            ? '投票结果暂时无法确认，请刷新核对后再操作。'
            : error is AppFailure
            ? error.kind == AppFailureKind.cancelled
                  ? null
                  : error.message
            : '投票加载或提交失败，请稍后重试',
      );
      return false;
    }
  }

  Future<bool> load() => _perform(
    false,
    (repository, cancellation) => repository.poll(id, cancellation),
  );

  void confirmNotVoted() {
    if (!state.busy &&
        state.canConfirmNotVoted &&
        state.poll?.hasVoted == false) {
      ref.read(dynamicContentProvider.notifier).unlock('poll:$id', {'vote'});
      state = state.copy(uncertain: false, canConfirmNotVoted: false);
    }
  }

  bool get canChoose {
    final poll = state.poll;
    return poll != null &&
        !state.busy &&
        !state.uncertain &&
        !poll.hasVoted &&
        !poll.endedAt(ref.read(dynamicPollClockProvider)());
  }

  void select(int index) {
    final poll = state.poll;
    if (poll == null ||
        !canChoose ||
        !poll.options.any((o) => o.index == index)) {
      return;
    }
    final selected = {...state.selected};
    if (!selected.remove(index)) {
      if (poll.maxChoices == 1) selected.clear();
      if (selected.length >= poll.maxChoices) {
        state = state.copy(message: '最多选择${poll.maxChoices}项');
        return;
      }
      selected.add(index);
    }
    state = state.copy(selected: selected);
  }

  void setAnonymous(bool value) {
    if (canChoose) state = state.copy(anonymous: value);
  }

  void setShowResults(bool value) => state = state.copy(showResults: value);

  Future<bool> submit({String? dynamicId}) async {
    final voterId = _voterId;
    final poll = state.poll;
    if (!canChoose ||
        voterId == null ||
        poll == null ||
        state.selected.isEmpty ||
        state.selected.length > poll.maxChoices) {
      return false;
    }
    final choices = state.selected.toList()..sort();
    final anonymous = state.anonymous;
    return _perform(
      true,
      (repository, cancellation) => repository.vote(
        id,
        voterId,
        choices,
        anonymous,
        cancellation,
        dynamicId: dynamicId,
      ),
    );
  }
}
