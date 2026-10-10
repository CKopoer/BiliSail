import 'package:bili_api/bili_api.dart';

import '../../../shared/data/video_access_mapper.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../domain/library_repository.dart';

final class ApiLibraryRepository implements LibraryRepository {
  ApiLibraryRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
    // Keep the public callback name descriptive.
    // ignore: prefer_initializing_formals
  }) : _accountScope = accountScope;
  final WatchHistoryClient client;
  final ApiRequests requests;
  final String Function() _accountScope;
  @override
  String get accountScope => _accountScope();

  @override
  Future<WatchHistoryPage> loadHistory({
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final scope = accountScope;
    return requests.run((context) async {
      if (!scope.startsWith('user:')) {
        throw const AppFailure(AppFailureKind.authentication, '请先登录后查看云端观看历史');
      }
      void checkCurrent() {
        if (cancellation.isCancelled ||
            scope != accountScope ||
            context.sessionEpoch != requests.sessionEpoch) {
          throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
        }
      }

      checkCurrent();
      final page = await client.load(cursor: cursor, context: context);
      checkCurrent();
      // At most three reads in flight and one read per BVID in this page.
      // Detail failures affect optional metadata only, never the history list.
      final details = <String, ApiVideoDetail>{};
      final ids = page.items
          .map((item) => item.bvid)
          .where((id) => VideoId(id).isValid)
          .toSet()
          .toList();
      var next = 0;
      var stopDetails = false;
      Future<void> worker() async {
        while (next < ids.length && !stopDetails) {
          checkCurrent();
          final id = ids[next++];
          try {
            details[id] = await client.api.getVideoDetail(id, context: context);
          } on ApiFailure catch (failure) {
            if (failure.category == ApiFailureCategory.cancelled) rethrow;
            // Avoid amplifying authentication, risk-control or network failures.
            if (failure.category != ApiFailureCategory.notFound &&
                failure.category != ApiFailureCategory.unavailable &&
                failure.category != ApiFailureCategory.protocol) {
              stopDetails = true;
            }
          }
          checkCurrent();
        }
      }

      await Future.wait([for (var i = 0; i < 3; i++) worker()]);
      checkCurrent();
      return WatchHistoryPage(
        List.unmodifiable(
          page.items.map((item) {
            final detail = details[item.bvid];
            return WatchHistoryEntry(
              video: VideoSummary(
                id: VideoId(item.bvid),
                access: mapVideoAccess(
                  detail?.access ?? const ApiVideoAccess(),
                ),
                title: item.title,
                coverUrl: item.coverUrl?.toString() ?? '',
                author: item.author,
                authorId: UserId.tryParse(item.authorMid),
                authorAvatarUrl: item.authorAvatarUrl,
                duration: item.duration,
                previewCid: item.cid.isEmpty ? null : item.cid,
                playCount: detail?.playCount,
                danmakuCount: detail?.danmakuCount,
                // The history card displays watchedAt, not a publication date.
              ),
              part: VideoPart(
                cid: item.cid,
                page: item.page,
                title: item.partTitle,
                duration: item.duration,
              ),
              position: item.position,
              watchedAt: item.watchedAt,
              episodeId: item.episodeId,
            );
          }),
        ),
        hasMore: page.hasMore,
        nextCursor: page.nextCursor,
      );
    }, cancellation: cancellation);
  }
}
