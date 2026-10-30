import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../video/application/watch_later_queue_registry.dart';
import '../../video/domain/watch_later_queue.dart';
import '../domain/home_repository.dart';
import '../domain/home_channel.dart';
import 'home_repository_provider.dart';

typedef FavoriteQueueRequest = ({HomeQuery query, String title});

final favoritePlaybackQueueProvider = NotifierProvider.autoDispose
    .family<
      FavoritePlaybackQueueController,
      AsyncValue<WatchLaterQueue?>,
      FavoriteQueueRequest
    >(FavoritePlaybackQueueController.new);

/// Capture one source page; the playback page owns subsequent requests.
final class FavoritePlaybackQueueController
    extends Notifier<AsyncValue<WatchLaterQueue?>> {
  FavoritePlaybackQueueController(this.request);
  final FavoriteQueueRequest request;
  RequestCancellation? _read;

  @override
  AsyncValue<WatchLaterQueue?> build() {
    ref.onDispose(() => _read?.cancel());
    return const AsyncData(null);
  }

  Future<WatchLaterQueue?> capture({
    int page = 1,
    String? cursor,
    VideoId? initial,
  }) async {
    if (state.isLoading) return null;
    final query = request.query;
    if (page < 1 ||
        query.channel != HomeChannel.favorites ||
        (query.folderId == null && query.section != '默认收藏夹')) {
      return null;
    }
    final repository = ref.read(homeRepositoryProvider);
    final epoch = ref.read(sessionEpochProvider)();
    final read = _read = RequestCancellation();
    final cancelled = Completer<void>();
    read.onCancel(cancelled.complete);
    bool current() =>
        ref.mounted &&
        identical(_read, read) &&
        !read.isCancelled &&
        repository.accountScope == query.scope &&
        ref.read(sessionEpochProvider)() == epoch;
    if (!current()) return null;
    state = const AsyncLoading();
    var timedOut = false;
    final timer = Timer(const Duration(seconds: 30), () {
      timedOut = true;
      read.cancel();
    });
    try {
      final result = await Future.any([
        repository.load(query, page: page, cursor: cursor, cancellation: read),
        cancelled.future.then<HomePage>((_) {
          throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
        }),
      ]);
      if (!current()) return null;
      final items = homeQueueItems(result.items);
      if (items.isEmpty) {
        throw const AppFailure(AppFailureKind.notFound, '当前收藏页暂无可播放的视频');
      }
      final index = initial == null
          ? 0
          : items.indexWhere((item) => item.video.id == initial);
      if (index < 0) {
        throw const AppFailure(AppFailureKind.notFound, '该视频已不在当前收藏页，请刷新后重试');
      }
      final start = items.length > WatchLaterQueue.maximumInitialItems
          ? (index - 49).clamp(
              0,
              items.length - WatchLaterQueue.maximumInitialItems,
            )
          : 0;
      final queue = ref
          .read(watchLaterQueueRegistryProvider)
          .capture(
            scope: query.scope,
            sessionEpoch: epoch,
            items: items
                .skip(start)
                .take(WatchLaterQueue.maximumInitialItems)
                .toList(),
            homeSource: HomeQueueSource(
              query: query,
              title: request.title,
              cursor: result.nextCursor ?? cursor,
            ),
            favoriteTitle: request.title,
            current: initial ?? items.first.video.id,
            hasMore: result.hasMore,
            nextPage: page + 1,
            truncated: items.length > WatchLaterQueue.maximumInitialItems,
          );
      state = AsyncData(queue);
      return queue;
    } catch (error, stack) {
      if (ref.mounted &&
          identical(_read, read) &&
          repository.accountScope == query.scope &&
          ref.read(sessionEpochProvider)() == epoch) {
        state = AsyncError(
          timedOut
              ? const AppFailure(AppFailureKind.timeout, '加载收藏夹超时，请重试')
              : error,
          stack,
        );
      }
      return null;
    } finally {
      timer.cancel();
      read.cancel();
      if (ref.mounted && identical(_read, read) && state.isLoading) {
        state = const AsyncData(null);
      }
    }
  }
}

List<WatchLaterQueueItem> homeQueueItems(List<HomeEntry> entries) {
  final known = <VideoId>{};
  return [
    for (final entry in entries)
      if (VideoId(entry.bvid ?? '') case final id
          when entry.kind == HomeEntryKind.video && id.isValid && known.add(id))
        WatchLaterQueueItem(
          entryId: entry.id,
          aid: entry.aid,
          video: VideoSummary(
            id: id,
            access: entry.access,
            title: entry.title,
            coverUrl: entry.coverUrl?.toString() ?? '',
            author: entry.authorName,
            authorId: UserId.tryParse(entry.authorMid),
            duration: entry.duration ?? Duration.zero,
          ),
          playCountText: entry.playCountText,
          danmakuCountText: entry.danmakuCountText,
        ),
  ];
}
