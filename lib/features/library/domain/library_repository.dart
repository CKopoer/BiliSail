import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../../domain/user.dart';

enum HistoryContentType {
  video('视频'),
  pgc('影视'),
  live('直播'),
  article('专栏'),
  articleList('文集'),
  course('课程');

  const HistoryContentType(this.label);
  final String label;
}

final class WatchHistoryEntry {
  const WatchHistoryEntry({
    required VideoSummary this.video,
    required VideoPart this.part,
    required this.position,
    required this.watchedAt,
    this.episodeId,
    this.deletionKey,
  }) : contentType = null,
       contentId = null,
       contentTitle = '',
       contentCoverUrl = '',
       contentAuthor = '',
       contentAuthorId = null,
       courseSeason = false,
       isLive = false;

  const WatchHistoryEntry.content({
    required HistoryContentType type,
    required String id,
    required String title,
    required String coverUrl,
    required String author,
    UserId? authorId,
    required this.watchedAt,
    this.deletionKey,
    this.isLive = false,
    this.courseSeason = false,
  }) : contentType = type,
       contentId = id,
       contentTitle = title,
       contentCoverUrl = coverUrl,
       contentAuthor = author,
       contentAuthorId = authorId,
       video = null,
       part = null,
       episodeId = null,
       position = Duration.zero,
       assert(
         type != HistoryContentType.video && type != HistoryContentType.pgc,
       );

  final VideoSummary? video;
  final VideoPart? part;
  final HistoryContentType? contentType;
  final String? contentId;
  final String contentTitle, contentCoverUrl, contentAuthor;
  final UserId? contentAuthorId;
  final bool isLive;
  final bool courseSeason;
  HistoryContentType get type =>
      contentType ??
      (episodeId == null ? HistoryContentType.video : HistoryContentType.pgc);
  String get title => video?.title ?? contentTitle;
  String get coverUrl => video?.coverUrl ?? contentCoverUrl;
  String get author => video?.author ?? contentAuthor;
  UserId? get authorId => video?.authorId ?? contentAuthorId;
  (HistoryContentType, String, String?) get identity => (
    type,
    contentId ?? episodeId ?? video?.id.value ?? '',
    contentType == HistoryContentType.course
        ? (courseSeason ? 'season' : 'episode')
        : part?.cid,
  );
  final Duration position;
  final DateTime watchedAt;
  final String? episodeId;
  // Server history identity: business + root kid, independent of BVID/cid.
  final String? deletionKey;
  Uri get location => switch (type) {
    HistoryContentType.live => Uri(path: '/live/$contentId'),
    HistoryContentType.article => Uri.https(
      'www.bilibili.com',
      '/read/cv$contentId',
    ),
    HistoryContentType.articleList => Uri.https(
      'www.bilibili.com',
      '/read/readlist/rl$contentId',
    ),
    HistoryContentType.course => Uri.https(
      'www.bilibili.com',
      '/cheese/play/${courseSeason ? 'ss' : 'ep'}$contentId',
    ),
    _ =>
      episodeId == null
          ? Uri(
              path: '/video/${video?.id.value}',
              queryParameters: part?.cid.isNotEmpty == true
                  ? {'cid': part?.cid ?? ''}
                  : null,
            )
          : Uri(path: '/pgc/episode/$episodeId'),
  };
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
