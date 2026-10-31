import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.video,
    required this.part,
    required this.position,
    required this.watchedAt,
    this.episodeId,
    this.deletionKey,
  });

  final VideoSummary video;
  final VideoPart part;
  final Duration position;
  final DateTime watchedAt;
  final String? episodeId;
  // Server history identity: business + root kid, independent of BVID/cid.
  final String? deletionKey;
  Uri get location => episodeId == null
      ? Uri(
          path: '/video/${video.id.value}',
          queryParameters: part.cid.isEmpty ? null : {'cid': part.cid},
        )
      : Uri(path: '/pgc/episode/$episodeId');
}

abstract interface class WatchHistoryMutations {
  Future<void> deleteHistory(
    String deletionKey, {
    required RequestCancellation cancellation,
  });
  Future<void> clearHistory({required RequestCancellation cancellation});
}

final class HistoryWriteUncertain implements Exception {
  const HistoryWriteUncertain();
}

abstract interface class LibraryRepository {
  String get accountScope;
  Future<WatchHistoryPage> loadHistory({
    String keyword = '',
    String? cursor,
    required RequestCancellation cancellation,
  });
}

final class WatchHistoryPage {
  const WatchHistoryPage(this.items, {required this.hasMore, this.nextCursor});
  final List<WatchHistoryEntry> items;
  final bool hasMore;
  final String? nextCursor;
}
