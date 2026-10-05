import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class WatchHistoryEntry {
  const WatchHistoryEntry({
    required this.video,
    required this.part,
    required this.position,
    required this.watchedAt,
    this.episodeId,
  });

  final VideoSummary video;
  final VideoPart part;
  final Duration position;
  final DateTime watchedAt;
  final String? episodeId;
  Uri get location => episodeId == null
      ? Uri(
          path: '/video/${video.id.value}',
          queryParameters: {'cid': part.cid},
        )
      : Uri(path: '/pgc/episode/$episodeId');
}

abstract interface class LibraryRepository {
  Future<List<WatchHistoryEntry>> loadHistory({
    required RequestCancellation cancellation,
  });
}
