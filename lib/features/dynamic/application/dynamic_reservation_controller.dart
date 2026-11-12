import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/dynamic_post.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/dynamic_repository.dart';
import '../domain/dynamic_reservation_repository.dart';
import 'dynamic_actions_controller.dart';
import 'dynamic_content_state.dart';

final dynamicReservationProvider = NotifierProvider.autoDispose
    .family<DynamicReservationController, DynamicReservationState, String>(
      DynamicReservationController.new,
    );

final class DynamicReservationState {
  const DynamicReservationState({
    this.signedIn = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
  });
  final bool signedIn, busy, uncertain;
  final String? message;
}

class DynamicReservationController extends Notifier<DynamicReservationState> {
  DynamicReservationController(this.id);
  final String id;
  RequestCancellation _request = RequestCancellation();
  int _generation = 0;
  String? _mid;

  @override
  DynamicReservationState build() {
    final repository = ref.watch(dynamicRepositoryProvider);
    final auth = ref.watch(
      authControllerProvider.select(
        (a) => (a.isSignedIn, a.mid, repository?.sessionEpoch),
      ),
    );
    _mid = auth.$1 ? auth.$2 : null;
    _request.cancel();
    ++_generation;
    ref.onDispose(() {
      ++_generation;
      _request.cancel();
    });
    return DynamicReservationState(
      signedIn: _mid != null && repository is DynamicReservationRepository,
      uncertain:
          ref
              .read(dynamicContentProvider)
              .locked['reserve:$id']
              ?.contains('reserve') ==
          true,
    );
  }

  Future<bool> toggle(String dynamicId, DynamicReservation seed) =>
      _perform(dynamicId, seed, write: true);

  Future<bool> refresh(String dynamicId, DynamicReservation seed) =>
      _perform(dynamicId, seed, write: false);

  Future<bool> _perform(
    String dynamicId,
    DynamicReservation seed, {
    required bool write,
  }) async {
    final reservation = seed.withCachedState(
      ref.read(dynamicContentProvider).reservations[id],
    );
    final repository = ref.read(dynamicRepositoryProvider);
    if (state.busy ||
        seed.id != id ||
        repository == null ||
        (write &&
            (!state.signedIn ||
                state.uncertain ||
                repository is! DynamicReservationRepository ||
                !reservation.canToggle ||
                repository.accountScope != 'user:$_mid'))) {
      return false;
    }
    final generation = ++_generation;
    final scope = repository.accountScope, epoch = repository.sessionEpoch;
    bool current() =>
        ref.mounted &&
        generation == _generation &&
        repository.accountScope == scope &&
        repository.sessionEpoch == epoch;
    _request.cancel();
    _request = RequestCancellation();
    state = DynamicReservationState(
      signedIn: state.signedIn,
      busy: true,
      uncertain: state.uncertain,
    );
    // Keep a lock if the view closes before the write result can be observed.
    if (write) {
      ref.read(dynamicContentProvider.notifier).lock('reserve:$id', 'reserve');
    }
    try {
      final DynamicReservation result;
      if (write) {
        result = await (repository as DynamicReservationRepository).reserve(
          dynamicId,
          reservation,
          _request,
        );
      } else {
        final post = await repository.detail(dynamicId, _request);
        if (!current()) return false;
        final found = post.id == dynamicId ? _find(post) : null;
        if (found == null) {
          throw const AppFailure(AppFailureKind.protocol, '暂时无法确认预约状态，请稍后刷新');
        }
        result = found;
      }
      if (!current()) return false;
      if (result.id != id) {
        throw const DynamicWriteUncertain();
      }
      final content = ref.read(dynamicContentProvider.notifier);
      content.updateReservation(result);
      content.unlock('reserve:$id', {'reserve'});
      state = DynamicReservationState(signedIn: state.signedIn);
      return true;
    } catch (error) {
      if (!current()) return false;
      final uncertain = error is DynamicWriteUncertain;
      if (write && !uncertain) {
        ref.read(dynamicContentProvider.notifier).unlock('reserve:$id', {
          'reserve',
        });
      }
      state = DynamicReservationState(
        signedIn: state.signedIn,
        uncertain: state.uncertain || uncertain,
        message: uncertain
            ? '预约结果暂时无法确认，请刷新状态后再操作，未自动重试。'
            : error is AppFailure
            ? error.kind == AppFailureKind.cancelled
                  ? null
                  : error.message
            : '预约操作失败，请稍后重试',
      );
      return false;
    }
  }

  DynamicReservation? _find(DynamicPost post) {
    for (final card in post.contentCards) {
      if (card.reservation?.id == id) return card.reservation;
    }
    final original = post.original;
    return original == null ? null : _find(original);
  }
}
