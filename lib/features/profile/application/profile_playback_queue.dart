import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../auth/application/auth_controller.dart';
import '../../video/application/watch_later_queue_registry.dart';
import '../../video/domain/watch_later_queue.dart';
import '../domain/profile_repository.dart';
import 'profile_controller.dart';

final profilePlaybackQueueProvider = NotifierProvider.autoDispose
    .family<ProfilePlaybackQueueController, ProfilePlaybackQueueState, String>(
      ProfilePlaybackQueueController.new,
    );

final class ProfilePlaybackQueueState {
  const ProfilePlaybackQueueState({
    this.queue,
    this.loading = false,
    this.message,
    this.capacityBlocked = false,
  });
  final WatchLaterQueue? queue;
  final bool loading;
  final String? message;
  final bool capacityBlocked;

  bool canPrefetch(VideoId current) {
    final value = queue;
    if (value == null || loading || !value.hasMore) return false;
    final index = value.indexOf(current);
    if (index < 0) return false;
    return message == null ||
        (capacityBlocked &&
            WatchLaterQueueRegistry.maximumItems - value.items.length + index >=
                50);
  }
}

/// The playback page owns paging; closing the originating space cannot stop it.
class ProfilePlaybackQueueController
    extends Notifier<ProfilePlaybackQueueState> {
  ProfilePlaybackQueueController(this.id);
  final String id;
  RequestCancellation? _read;
  Future<void>? _pending;
  int _emptyPages = 0;

  @override
  ProfilePlaybackQueueState build() {
    ref.watch(authControllerProvider);
    _read?.cancel();
    _pending = null;
    final repository = ref.read(profileRepositoryProvider);
    ref.onDispose(() => _read?.cancel());
    return ProfilePlaybackQueueState(
      queue: ref
          .read(watchLaterQueueRegistryProvider)
          .resolve(
            id,
            scope: repository.accountScope,
            sessionEpoch: repository.sessionEpoch,
          ),
    );
  }

  Future<void> loadMore(VideoId current) {
    final pending = _pending;
    if (pending != null) return pending;
    late final Future<void> next;
    next = _loadMore(current).whenComplete(() {
      if (identical(_pending, next)) _pending = null;
    });
    return _pending = next;
  }

  Future<void> _loadMore(VideoId current) async {
    final queue = state.queue;
    final source = queue?.profileSource;
    if (queue == null || source == null || !queue.hasMore) return;
    final label = source.folderId == null ? '投稿' : '收藏夹视频';
    final repository = ref.read(profileRepositoryProvider);
    final read = _read = RequestCancellation();
    bool valid() =>
        ref.mounted &&
        identical(_read, read) &&
        !read.isCancelled &&
        repository.accountScope == queue.scope &&
        repository.sessionEpoch == queue.sessionEpoch &&
        ref
                .read(watchLaterQueueRegistryProvider)
                .resolve(
                  id,
                  scope: queue.scope,
                  sessionEpoch: queue.sessionEpoch,
                ) !=
            null;
    if (!valid()) return;
    // Retain a bounded window. Only already passed entries may be evicted.
    final index = queue.indexOf(current);
    if (index < 0) return;
    final capacity =
        WatchLaterQueueRegistry.maximumItems -
        queue.items.length +
        index.clamp(0, queue.items.length);
    if (capacity < 50) {
      state = ProfilePlaybackQueueState(
        queue: queue,
        message: '继续播放后可加载更多$label',
        capacityBlocked: true,
      );
      return;
    }
    state = ProfilePlaybackQueueState(queue: queue, loading: true);
    try {
      final result = await repository
          .loadEntries(
            source.userId,
            source.folderId == null
                ? ProfileSection.videos
                : ProfileSection.folders,
            page: queue.nextPage,
            order: source.order,
            folderId: source.folderId,
            cancellation: read,
          )
          .timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              throw AppFailure(AppFailureKind.timeout, '$label加载超时，请重试');
            },
          );
      if (!valid()) return;
      final known = queue.items.map((item) => item.video.id).toSet();
      final added = profileQueueItems(result.items)
          .where((item) => known.add(item.video.id))
          .toList();
      if (added.length > capacity) {
        throw AppFailure(AppFailureKind.protocol, '$label分页超出队列容量，请继续播放后重试');
      }
      final drop =
          (queue.items.length +
                  added.length -
                  WatchLaterQueueRegistry.maximumItems)
              .clamp(0, index.clamp(0, queue.items.length));
      final updated = queue.append(
        added,
        nextPage: queue.nextPage + 1,
        hasMore: result.hasMore && !result.isHidden,
        drop: drop,
      );
      _emptyPages = added.isEmpty ? _emptyPages + 1 : 0;
      ref.read(watchLaterQueueRegistryProvider).update(updated);
      state = ProfilePlaybackQueueState(
        queue: updated,
        message: updated.hasMore && _emptyPages >= 3
            ? '连续多页没有新$label，请重试继续加载'
            : null,
      );
    } on AppFailure catch (error) {
      if (valid()) {
        state = ProfilePlaybackQueueState(
          queue: queue,
          message: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (valid()) {
        state = ProfilePlaybackQueueState(
          queue: queue,
          message: '$label暂时无法加载，请重试',
        );
      }
    } finally {
      read.cancel();
    }
  }
}
