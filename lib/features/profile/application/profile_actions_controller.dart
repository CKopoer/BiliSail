import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../auth/application/auth_controller.dart';
import '../../video/application/video_author_controller.dart';
import '../../video/domain/video_author_repository.dart';
import '../domain/profile_repository.dart';
import 'profile_controller.dart';

final profileActionsControllerProvider = NotifierProvider.autoDispose
    .family<ProfileActionsController, ProfileActionsState, UserId>(
      ProfileActionsController.new,
    );

final class ProfileActionsState {
  const ProfileActionsState({this.blocked, this.busy = false, this.message});
  final bool? blocked;
  final bool busy;
  final String? message;
}

class ProfileActionsController extends Notifier<ProfileActionsState> {
  ProfileActionsController(this.id);
  final UserId id;
  int _generation = 0;
  RequestCancellation? _operation;

  @override
  ProfileActionsState build() {
    ref.watch(authControllerProvider);
    final generation = ++_generation;
    _operation?.cancel();
    ref.onDispose(() {
      ++_generation;
      _operation?.cancel();
    });
    Future<void>.microtask(() {
      if (ref.mounted && generation == _generation) refresh();
    });
    return const ProfileActionsState();
  }

  bool _current(int generation, String scope, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final repo = ref.read(profileRepositoryProvider);
    return repo.accountScope == scope && repo.sessionEpoch == epoch;
  }

  Future<void> refresh() => _run(null);

  Future<void> setBlocked(bool blocked) async {
    // A failed or uncertain write clears the known state; reconcile it before
    // another explicit write instead of replaying a possibly completed action.
    if (state.blocked == null || state.blocked == blocked) return;
    await _run(blocked);
  }

  Future<void> _run(bool? blocked) async {
    if (state.busy) return;
    final repository = ref.read(profileRepositoryProvider);
    final auth = ref.read(authControllerProvider);
    if (!auth.isSignedIn ||
        auth.mid == id.value ||
        repository.accountScope != 'user:${auth.mid}' ||
        repository is! ProfileActionsRepository) {
      return;
    }
    final port = repository as ProfileActionsRepository;
    final generation = _generation,
        scope = repository.accountScope,
        epoch = repository.sessionEpoch;
    final cancellation = _operation = RequestCancellation();
    state = ProfileActionsState(blocked: state.blocked, busy: true);
    try {
      final bool value;
      if (blocked == null) {
        value = await port.loadBlocked(id, cancellation: cancellation);
      } else {
        await port.setBlocked(id, blocked, cancellation: cancellation);
        value = blocked;
      }
      if (!_current(generation, scope, epoch)) return;
      state = ProfileActionsState(blocked: value);
      if (blocked != null) {
        ref.invalidate(videoAuthorControllerProvider(VideoAuthorId(id.value)));
      }
    } on AppFailure catch (error) {
      if (!_current(generation, scope, epoch)) return;
      state = ProfileActionsState(
        message: error.kind == AppFailureKind.cancelled
            ? null
            : blocked == null
            ? error.message
            : '操作未确认，请刷新黑名单状态后重试',
      );
    } catch (_) {
      if (_current(generation, scope, epoch)) {
        state = ProfileActionsState(
          message: blocked == null ? '黑名单状态暂时无法加载，请重试' : '操作未确认，请刷新黑名单状态后重试',
        );
      }
    }
  }
}
