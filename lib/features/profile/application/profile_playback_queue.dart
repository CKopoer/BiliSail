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
    this.direction = 1,
  });
  final WatchLaterQueue? queue;
  final bool loading;
  final String? message;
  final int direction;
  String? get nextMessage => direction > 0 ? message : null;
  String? get previousMessage => direction < 0 ? message : null;
}

/// The playback page owns the bounded window and its independent requests.
class ProfilePlaybackQueueController
    extends Notifier<ProfilePlaybackQueueState> {
  ProfilePlaybackQueueController(this.id);
  final String id;
  RequestCancellation? _read;
  Future<void>? _pending;
  final Map<int, int> _emptyPages = {};

  @override
  ProfilePlaybackQueueState build() {
    ref.watch(authControllerProvider);
    _read?.cancel();
    _pending = null;
    _emptyPages.clear();
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

  void rememberCurrent(VideoId current) {
    final queue = state.queue;
    if (queue == null || queue.profilePages.isEmpty) return;
    final updated = queue.withProfilePages(
      queue.profilePages,
      current: current,
    );
    ref.read(watchLaterQueueRegistryProvider).update(updated);
    state = ProfilePlaybackQueueState(
      queue: updated,
      loading: state.loading,
      message: state.message,
      direction: state.direction,
    );
  }

  Future<void> loadMore(VideoId current) {
    final queue = state.queue;
    if (queue == null || !queue.hasMore) return Future.value();
    return _request(queue.nextPage, current, 1);
  }

  Future<void> loadPrevious(VideoId current) {
    final queue = state.queue;
    if (queue == null || !queue.hasPrevious) return Future.value();
    return _request(queue.profilePages.first.page - 1, current, -1);
  }

  Future<void> prepareAdjacent(VideoId current, int direction) async {
    final pending = _pending;
    if (pending != null) await pending;
    if (!ref.mounted) return;
    var queue = state.queue;
    if (queue == null) return;
    if (queue.indexOf(current) < 0) {
      final page = queue.pageOf(current);
      if (page == null) return;
      await _request(page, current, direction, replace: true);
      if (!ref.mounted || state.message != null) return;
    }
    for (var attempt = 0; attempt < 3 && ref.mounted; attempt++) {
      queue = state.queue;
      if (queue == null || queue.adjacent(current, direction) != null) return;
      if (direction > 0 ? !queue.hasMore : !queue.hasPrevious) return;
      await (direction > 0 ? loadMore(current) : loadPrevious(current));
      if (!ref.mounted || state.message != null) return;
    }
  }

  Future<void> _request(
    int page,
    VideoId current,
    int direction, {
    bool replace = false,
  }) {
    final pending = _pending;
    if (pending != null) return pending;
    late final Future<void> next;
    next = _loadPage(page, current, direction, replace: replace).whenComplete(
      () {
        if (identical(_pending, next)) _pending = null;
      },
    );
    return _pending = next;
  }

  Future<void> _loadPage(
    int page,
    VideoId current,
    int direction, {
    required bool replace,
  }) async {
    final queue = state.queue;
    final source = queue?.profileSource;
    if (queue == null || source == null || page < 1) return;
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
    state = ProfilePlaybackQueueState(
      queue: queue,
      loading: true,
      direction: direction,
    );
    try {
      final result = await repository
          .loadEntries(
            source.userId,
            source.folderId == null
                ? ProfileSection.videos
                : ProfileSection.folders,
            page: page,
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
      final known = replace
          ? <VideoId>{}
          : queue.items.map((item) => item.video.id).toSet();
      final added = profileQueueItems(result.items)
          .where((item) => known.add(item.video.id))
          .toList();
      if (replace && added.isEmpty) {
        throw AppFailure(AppFailureKind.notFound, '当前视频所在页暂无可播放内容');
      }
      final incoming = ProfileQueuePage(
        page: page,
        items: added.take(WatchLaterQueue.maximumProfileItems).toList(),
        hasMore: result.hasMore && !result.isHidden,
      );
      final pages = replace
          ? [incoming]
          : direction > 0
          ? [...queue.profilePages, incoming]
          : [incoming, ...queue.profilePages];
      int count() => pages.fold(0, (sum, value) => sum + value.items.length);
      while (pages.length > 1 &&
          (count() > WatchLaterQueue.maximumProfileItems ||
              pages.length > WatchLaterQueue.maximumProfileItems)) {
        pages.removeAt(direction > 0 ? 0 : pages.length - 1);
      }
      final latest = state.queue ?? queue;
      final updated = latest.withProfilePages(
        pages,
        current: current,
        truncated: added.length > WatchLaterQueue.maximumProfileItems,
      );
      final empty = _emptyPages[direction] = added.isEmpty
          ? (_emptyPages[direction] ?? 0) + 1
          : 0;
      ref.read(watchLaterQueueRegistryProvider).update(updated);
      state = ProfilePlaybackQueueState(
        queue: updated,
        direction: direction,
        message:
            empty >= 3 &&
                (direction > 0 ? updated.hasMore : updated.hasPrevious)
            ? '连续多页没有新$label，请重试继续加载'
            : null,
      );
    } on AppFailure catch (error) {
      if (valid()) {
        state = ProfilePlaybackQueueState(
          queue: queue,
          direction: direction,
          message: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (valid()) {
        state = ProfilePlaybackQueueState(
          queue: queue,
          direction: direction,
          message: '$label暂时无法加载，请重试',
        );
      }
    } finally {
      read.cancel();
    }
  }
}
