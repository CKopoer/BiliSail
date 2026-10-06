import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../video/domain/video_actions_repository.dart';
import '../domain/home_repository.dart';
import 'home_repository_provider.dart';

final watchLaterRemovalProvider =
    NotifierProvider.family<
      WatchLaterRemovalController,
      WatchLaterRemovalState,
      String
    >(WatchLaterRemovalController.new);

final class WatchLaterRemovalState {
  const WatchLaterRemovalState({
    this.removed = const {},
    this.pending = const {},
  });
  final Set<String> removed, pending;
}

/// Shared by both account watch-later subtabs, so stale snapshots cannot revive a deletion.
final class WatchLaterRemovalController
    extends Notifier<WatchLaterRemovalState> {
  WatchLaterRemovalController(this.scope);
  final String scope;
  final _writes = <String, RequestCancellation>{};
  final _removed = <String>{};
  final _uncertain = <String>{};
  @override
  WatchLaterRemovalState build() {
    ref.onDispose(() {
      for (final token in _writes.values) {
        token.cancel();
      }
    });
    return const WatchLaterRemovalState();
  }

  void _publish() {
    state = WatchLaterRemovalState(
      removed: Set.unmodifiable(_removed),
      pending: Set.unmodifiable(_writes.keys),
    );
  }

  /// Only a confirmed explicit add may lift a successful deletion tombstone.
  void restore(String bvid) {
    if (!ref.mounted || !_removed.remove(bvid)) return;
    _publish();
  }

  Future<bool> remove(HomeEntry entry) async {
    if (entry.kind != HomeEntryKind.video ||
        !RegExp(r'^[1-9]\d*$').hasMatch(entry.aid ?? '')) {
      throw const AppFailure(AppFailureKind.protocol, '稍后再看条目缺少视频标识，请刷新');
    }
    if (!ref.mounted ||
        _writes.containsKey(entry.id) ||
        _removed.contains(entry.id)) {
      return false;
    }
    if (_uncertain.contains(entry.id)) throw const UnknownWriteOutcome();
    final repository = ref.read(homeRepositoryProvider);
    if (repository.accountScope != scope) return false;
    if (repository is! HomeWatchLaterRepository) {
      throw const AppFailure(AppFailureKind.protocol, '当前无法删除稍后再看');
    }
    if (_writes.length >= 8 || _removed.length + _uncertain.length >= 500) {
      throw const AppFailure(AppFailureKind.protocol, '本次浏览的删除操作已达上限');
    }
    final token = RequestCancellation();
    bool current() =>
        ref.mounted && !token.isCancelled && repository.accountScope == scope;
    _writes[entry.id] = token;
    _publish();
    try {
      await (repository as HomeWatchLaterRepository).removeWatchLater(
        entry,
        scope: scope,
        cancellation: token,
      );
      if (!current()) return false;
      _removed.add(entry.id);
      return true;
    } on UnknownWriteOutcome {
      if (!current()) return false;
      _uncertain.add(entry.id);
      rethrow;
    } on AppFailure catch (failure) {
      if (!current() || failure.kind == AppFailureKind.cancelled) return false;
      rethrow;
    } finally {
      _writes.remove(entry.id);
      if (ref.mounted) _publish();
    }
  }
}
