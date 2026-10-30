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

/// Explicit playback reads independently of the retained browser's page limit.
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

  Future<WatchLaterQueue?> capture() async {
    if (state.isLoading) return null;
    final query = request.query;
    if (query.channel != HomeChannel.favorites ||
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
    final timer = Timer(const Duration(seconds: 60), () {
      timedOut = true;
      read.cancel();
    });
    try {
      final items = <WatchLaterQueueItem>[];
      final known = <VideoId>{};
      final seenEntries = <String>{};
      String? cursor;
      var emptyPages = 0;
      var scanned = 0;
      var truncated = false;
      for (var page = 1; page <= 100; page++) {
        final result = await Future.any([
          repository.load(
            query,
            page: page,
            cursor: cursor,
            cancellation: read,
          ),
          cancelled.future.then<HomePage>((_) {
            throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
          }),
        ]);
        if (!current()) return null;
        var newEntries = 0;
        for (final entry in result.items) {
          if (scanned >= WatchLaterQueueRegistry.maximumItems) {
            truncated = true;
            break;
          }
          scanned++;
          if (seenEntries.add(entry.id)) newEntries++;
          final id = VideoId(entry.bvid ?? '');
          if (entry.kind != HomeEntryKind.video ||
              !id.isValid ||
              !known.add(id)) {
            continue;
          }
          items.add(
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
          );
        }
        truncated |=
            result.hasMore && scanned >= WatchLaterQueueRegistry.maximumItems;
        if (!result.hasMore || truncated) break;
        emptyPages = newEntries == 0 ? emptyPages + 1 : 0;
        if (emptyPages >= 3 || page == 100) {
          throw const AppFailure(AppFailureKind.protocol, '收藏夹分页没有前进，请重试');
        }
        cursor = result.nextCursor;
      }
      if (!current()) return null;
      if (items.isEmpty) {
        throw const AppFailure(AppFailureKind.notFound, '收藏夹内暂无可播放的视频');
      }
      final queue = ref
          .read(watchLaterQueueRegistryProvider)
          .capture(
            scope: query.scope,
            sessionEpoch: epoch,
            items: items,
            favoriteTitle: request.title,
            truncated: truncated,
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
      if (ref.mounted && identical(_read, read) && state.isLoading) {
        state = const AsyncData(null);
      }
    }
  }
}
