import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/pgc_follow_repository.dart';
import '../domain/pgc_repository.dart';

final pgcFollowRepositoryProvider = Provider<PgcFollowRepository>(
  (ref) =>
      throw UnimplementedError('PgcFollowRepository must be provided by app'),
);

// Season and episode routes share one mutation owner for the same season.
final pgcFollowControllerProvider = NotifierProvider.autoDispose
    .family<PgcFollowController, PgcFollowState, PgcSeasonId>(
      PgcFollowController.new,
    );

final class PgcFollowState {
  const PgcFollowState({
    required this.signedIn,
    this.followed,
    this.loading = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
  });

  final bool signedIn;
  final bool? followed;
  final bool loading, busy, uncertain;
  final String? message;
}

class PgcFollowController extends Notifier<PgcFollowState> {
  PgcFollowController(this.id);
  final PgcSeasonId id;
  RequestCancellation _cancellation = RequestCancellation();
  int _generation = 0;
  String? _loadedScope;
  int? _loadedEpoch;

  @override
  PgcFollowState build() {
    final signedIn = ref.watch(authControllerProvider).isSignedIn;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    _loadedScope = null;
    _loadedEpoch = null;
    final generation = ++_generation;
    ref.onDispose(() {
      ++_generation;
      _cancellation.cancel();
    });
    if (signedIn) {
      Future<void>.microtask(() {
        if (ref.mounted && generation == _generation) refresh();
      });
    }
    return PgcFollowState(signedIn: signedIn, loading: signedIn);
  }

  bool _current(int generation, String scope, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final repository = ref.read(pgcFollowRepositoryProvider);
    if (repository.accountScope != scope || repository.sessionEpoch != epoch) {
      ref.invalidateSelf();
      return false;
    }
    return true;
  }

  Future<void> refresh() async {
    if (!ref.mounted || !state.signedIn || state.busy) return;
    final repository = ref.read(pgcFollowRepositoryProvider);
    final scope = repository.accountScope;
    final epoch = repository.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    _loadedScope = null;
    _loadedEpoch = null;
    state = PgcFollowState(signedIn: true, loading: true);
    try {
      final followed = await repository.isFollowed(id, _cancellation);
      if (!_current(generation, scope, epoch)) return;
      _loadedScope = scope;
      _loadedEpoch = epoch;
      state = PgcFollowState(signedIn: true, followed: followed);
    } catch (error) {
      if (!_current(generation, scope, epoch)) return;
      state = PgcFollowState(signedIn: true, message: _message(error));
    }
  }

  Future<bool> toggle() async {
    if (!ref.mounted) return false;
    final followed = state.followed;
    if (!state.signedIn ||
        followed == null ||
        state.loading ||
        state.busy ||
        state.uncertain) {
      return false;
    }
    final repository = ref.read(pgcFollowRepositoryProvider);
    final scope = repository.accountScope;
    final epoch = repository.sessionEpoch;
    if (_loadedScope != scope || _loadedEpoch != epoch) {
      await refresh();
      return false;
    }
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = PgcFollowState(signedIn: true, followed: followed, busy: true);
    try {
      await repository.setFollowed(id, !followed, _cancellation);
      if (!_current(generation, scope, epoch)) return false;
      state = PgcFollowState(signedIn: true, followed: !followed);
      return true;
    } catch (error) {
      if (!_current(generation, scope, epoch)) return false;
      final uncertain = error is PgcFollowWriteUncertain;
      if (uncertain) {
        _loadedScope = null;
        _loadedEpoch = null;
      }
      state = PgcFollowState(
        signedIn: true,
        followed: uncertain ? null : followed,
        uncertain: uncertain,
        message: uncertain ? '追番结果暂时无法确认，请刷新状态后再操作' : _message(error),
      );
      return false;
    }
  }

  static String? _message(Object error) => error is AppFailure
      ? error.kind == AppFailureKind.cancelled
            ? null
            : error.message
      : '追番操作失败，请稍后重试';
}
