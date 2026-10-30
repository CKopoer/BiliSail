import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../core/network/api_requests.dart';
import '../../auth/application/auth_controller.dart';
import '../../profile/domain/profile_repository.dart';
import '../../profile/application/profile_controller.dart';
import '../../feed/application/home_repository_provider.dart';
import '../../feed/application/favorite_playback_queue.dart';
import '../domain/watch_later_queue.dart';
import 'watch_later_queue_registry.dart';

final playbackQueueProvider = NotifierProvider.autoDispose
    .family<PlaybackQueueController, PlaybackQueueState, String>(
      PlaybackQueueController.new,
    );

final class PlaybackQueueState {
  const PlaybackQueueState({
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
class PlaybackQueueController extends Notifier<PlaybackQueueState> {
  PlaybackQueueController(this.id);
  final String id;
  RequestCancellation? _read;
  Future<void>? _pending;
  final Map<int, int> _emptyPages = {};

  @override
  PlaybackQueueState build() {
    ref.watch(authControllerProvider);
    _read?.cancel();
    _pending = null;
    _emptyPages.clear();
    final original = ref.read(watchLaterQueueRegistryProvider).peek(id);
    if (original == null) return const PlaybackQueueState();
    final scope = original.homeSource != null
        ? ref.read(homeRepositoryProvider).accountScope
        : ref.read(profileRepositoryProvider).accountScope;
    final epoch = original.homeSource != null
        ? ref.read(sessionEpochProvider)()
        : ref.read(profileRepositoryProvider).sessionEpoch;
    ref.onDispose(() => _read?.cancel());
    return PlaybackQueueState(
      queue: ref
          .read(watchLaterQueueRegistryProvider)
          .resolve(id, scope: scope, sessionEpoch: epoch),
    );
  }

  void rememberCurrent(VideoId current) {
    final queue = state.queue;
    if (queue == null || queue.pages.isEmpty) return;
    final updated = queue.withPages(queue.pages, current: current);
    ref.read(watchLaterQueueRegistryProvider).update(updated);
    state = PlaybackQueueState(
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
    return _request(queue.pages.first.page - 1, current, -1);
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
    final home = queue?.homeSource;
    if (queue == null || (source == null && home == null) || page < 1) return;
    final label = home != null || source?.folderId != null ? '收藏夹视频' : '投稿';
    String scope() => home != null
        ? ref.read(homeRepositoryProvider).accountScope
        : ref.read(profileRepositoryProvider).accountScope;
    int epoch() => home != null
        ? ref.read(sessionEpochProvider)()
        : ref.read(profileRepositoryProvider).sessionEpoch;
    final read = _read = RequestCancellation();
    bool valid() =>
        ref.mounted &&
        identical(_read, read) &&
        !read.isCancelled &&
        scope() == queue.scope &&
        epoch() == queue.sessionEpoch &&
        ref
                .read(watchLaterQueueRegistryProvider)
                .resolve(
                  id,
                  scope: queue.scope,
                  sessionEpoch: queue.sessionEpoch,
                ) !=
            null;
    if (!valid()) return;
    state = PlaybackQueueState(
      queue: queue,
      loading: true,
      direction: direction,
    );
    try {
      final result = await _readPage(source, home, page, read).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw AppFailure(AppFailureKind.timeout, '$label加载超时，请重试');
        },
      );
      if (!valid()) return;
      final known = replace
          ? <VideoId>{}
          : queue.items.map((item) => item.video.id).toSet();
      final added = result.items
          .where((item) => known.add(item.video.id))
          .toList();
      if (replace && added.isEmpty) {
        throw AppFailure(AppFailureKind.notFound, '当前视频所在页暂无可播放内容');
      }
      final incoming = PlaybackQueuePage(
        page: page,
        items: added.take(WatchLaterQueue.maximumPagedItems).toList(),
        hasMore: result.hasMore,
      );
      final pages = replace
          ? [incoming]
          : direction > 0
          ? [...queue.pages, incoming]
          : [incoming, ...queue.pages];
      int count() => pages.fold(0, (sum, value) => sum + value.items.length);
      while (pages.length > 1 &&
          (count() > WatchLaterQueue.maximumPagedItems ||
              pages.length > WatchLaterQueue.maximumPagedItems)) {
        pages.removeAt(direction > 0 ? 0 : pages.length - 1);
      }
      final latest = state.queue ?? queue;
      final updated = latest.withPages(
        pages,
        current: current,
        truncated: added.length > WatchLaterQueue.maximumPagedItems,
      );
      final empty = _emptyPages[direction] = added.isEmpty
          ? (_emptyPages[direction] ?? 0) + 1
          : 0;
      ref.read(watchLaterQueueRegistryProvider).update(updated);
      state = PlaybackQueueState(
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
        state = PlaybackQueueState(
          queue: queue,
          direction: direction,
          message: error.kind == AppFailureKind.cancelled
              ? null
              : error.message,
        );
      }
    } catch (_) {
      if (valid()) {
        state = PlaybackQueueState(
          queue: queue,
          direction: direction,
          message: '$label暂时无法加载，请重试',
        );
      }
    } finally {
      read.cancel();
    }
  }

  Future<PlaybackQueuePage> _readPage(
    ProfileVideoQueueSource? profile,
    HomeQueueSource? home,
    int page,
    RequestCancellation cancellation,
  ) async {
    if (home != null) {
      final result = await ref
          .read(homeRepositoryProvider)
          .load(
            home.query,
            page: page,
            cursor: home.cursor,
            cancellation: cancellation,
          );
      return PlaybackQueuePage(
        page: page,
        items: homeQueueItems(result.items),
        hasMore: result.hasMore,
      );
    }
    if (profile == null) {
      throw const AppFailure(AppFailureKind.protocol, '播放列表来源无效');
    }
    final result = await ref
        .read(profileRepositoryProvider)
        .loadEntries(
          profile.userId,
          profile.folderId == null
              ? ProfileSection.videos
              : ProfileSection.folders,
          page: page,
          order: profile.order,
          folderId: profile.folderId,
          cancellation: cancellation,
        );
    return PlaybackQueuePage(
      page: page,
      items: profileQueueItems(result.items),
      hasMore: result.hasMore && !result.isHidden,
    );
  }
}
