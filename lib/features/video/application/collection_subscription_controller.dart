import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/application/auth_controller.dart';
import '../domain/collection_subscription_repository.dart';
import '../domain/video_actions_repository.dart';

final collectionSubscriptionRepositoryProvider =
    Provider<CollectionSubscriptionRepository>(
      (ref) => throw UnimplementedError('CollectionSubscriptionRepository'),
    );

final collectionSubscriptionControllerProvider = NotifierProvider.autoDispose
    .family<
      CollectionSubscriptionController,
      CollectionSubscriptionState,
      CollectionId
    >(CollectionSubscriptionController.new);

final class CollectionSubscriptionState {
  const CollectionSubscriptionState({
    required this.signedIn,
    this.subscribed,
    this.loading = false,
    this.busy = false,
    this.uncertain = false,
    this.message,
  });

  final bool signedIn;
  final bool? subscribed;
  final bool loading, busy, uncertain;
  final String? message;
}

class CollectionSubscriptionController
    extends Notifier<CollectionSubscriptionState> {
  CollectionSubscriptionController(this.id);
  final CollectionId id;
  RequestCancellation _cancellation = RequestCancellation();
  int _generation = 0;
  String? _loadedScope;
  int? _loadedEpoch;

  @override
  CollectionSubscriptionState build() {
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
    return CollectionSubscriptionState(signedIn: signedIn, loading: signedIn);
  }

  bool _current(int generation, String scope, int epoch) {
    if (!ref.mounted || generation != _generation) return false;
    final repository = ref.read(collectionSubscriptionRepositoryProvider);
    if (repository.accountScope != scope || repository.sessionEpoch != epoch) {
      ref.invalidateSelf();
      return false;
    }
    return true;
  }

  Future<void> refresh() async {
    if (!ref.mounted || !state.signedIn || state.busy) return;
    final repository = ref.read(collectionSubscriptionRepositoryProvider);
    final scope = repository.accountScope;
    final epoch = repository.sessionEpoch;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    _loadedScope = null;
    _loadedEpoch = null;
    state = CollectionSubscriptionState(
      signedIn: true,
      subscribed: state.subscribed,
      loading: true,
    );
    try {
      final subscribed = await repository.isSubscribed(id, _cancellation);
      if (!_current(generation, scope, epoch)) return;
      _loadedScope = scope;
      _loadedEpoch = epoch;
      state = CollectionSubscriptionState(
        signedIn: true,
        subscribed: subscribed,
      );
    } catch (error) {
      if (!_current(generation, scope, epoch)) return;
      state = CollectionSubscriptionState(
        signedIn: true,
        subscribed: null,
        message: _message(error) ?? '订阅状态加载失败，请刷新',
      );
    }
  }

  Future<bool> toggle() async {
    if (!ref.mounted) return false;
    final currentSubscription = state.subscribed;
    if (!state.signedIn ||
        currentSubscription == null ||
        state.loading ||
        state.busy ||
        state.uncertain) {
      return false;
    }
    final repository = ref.read(collectionSubscriptionRepositoryProvider);
    final scope = repository.accountScope;
    final epoch = repository.sessionEpoch;
    if (_loadedScope != scope || _loadedEpoch != epoch) {
      await refresh();
      return false;
    }
    final subscribed = !currentSubscription;
    final generation = ++_generation;
    _cancellation.cancel();
    _cancellation = RequestCancellation();
    state = CollectionSubscriptionState(
      signedIn: true,
      subscribed: !subscribed,
      busy: true,
    );
    try {
      await repository.setSubscribed(id, subscribed, _cancellation);
      if (!_current(generation, scope, epoch)) return false;
      state = CollectionSubscriptionState(
        signedIn: true,
        subscribed: subscribed,
      );
      return true;
    } catch (error) {
      if (!_current(generation, scope, epoch)) return false;
      final uncertain = error is UnknownWriteOutcome;
      if (uncertain) {
        _loadedScope = null;
        _loadedEpoch = null;
      }
      state = CollectionSubscriptionState(
        signedIn: true,
        subscribed: uncertain ? null : !subscribed,
        uncertain: uncertain,
        message: uncertain ? '订阅结果暂时无法确认，请刷新状态后再操作' : _message(error),
      );
      return false;
    }
  }

  static String? _message(Object error) => error is AppFailure
      ? error.kind == AppFailureKind.cancelled
            ? null
            : error.message
      : '合集订阅操作失败，请稍后重试';
}
