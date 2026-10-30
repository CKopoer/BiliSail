import '../../../domain/video.dart';
import '../../../domain/user.dart';
import '../../feed/domain/home_repository.dart';

final class HomeQueueSource {
  const HomeQueueSource({
    required this.query,
    required this.title,
    this.cursor,
  });
  final HomeQuery query;
  final String title;
  final String? cursor;
}

/// A captured space query, paged independently of the originating browser.
final class ProfileVideoQueueSource {
  const ProfileVideoQueueSource({
    required this.userId,
    required this.name,
    required this.order,
    this.folderId,
  });

  final UserId userId;
  final String name, order;
  final String? folderId;
}

final class PlaybackQueuePage {
  PlaybackQueuePage({
    required this.page,
    required List<WatchLaterQueueItem> items,
    required this.hasMore,
  }) : items = List.unmodifiable(items);
  final int page;
  final List<WatchLaterQueueItem> items;
  final bool hasMore;
}

/// An account-scoped queue shared by watch-later, favorites and submissions.
final class WatchLaterQueue {
  WatchLaterQueue({
    required this.id,
    required this.scope,
    required this.sessionEpoch,
    required List<WatchLaterQueueItem> items,
    this.profileSource,
    this.homeSource,
    this.favoriteTitle,
    this.truncated = false,
    this.nextPage = 1,
    this.hasMore = false,
    this.offset = 0,
    List<PlaybackQueuePage> pages = const [],
    Map<VideoId, int> pageHints = const {},
  }) : items = List.unmodifiable(items),
       pages = List.unmodifiable(pages),
       pageHints = Map.unmodifiable(pageHints);

  static const maximumInitialItems = 99;
  static const maximumPagedItems = 999;

  final String id;
  final String scope;
  final int sessionEpoch;
  final List<WatchLaterQueueItem> items;
  final ProfileVideoQueueSource? profileSource;
  final HomeQueueSource? homeSource;
  bool get isPaged => profileSource != null || homeSource != null;
  final String? favoriteTitle;
  final bool truncated;
  final int nextPage, offset;
  final bool hasMore;
  final List<PlaybackQueuePage> pages;
  final Map<VideoId, int> pageHints;
  bool get hasPrevious => pages.isNotEmpty && pages.first.page > 1;
  int? pageOf(VideoId id) {
    for (final page in pages) {
      if (page.items.any((item) => item.video.id == id)) return page.page;
    }
    return pageHints[id];
  }

  WatchLaterQueue withPages(
    List<PlaybackQueuePage> pages, {
    VideoId? current,
    bool? truncated,
  }) {
    final hints = {...pageHints};
    final currentPage = current == null
        ? null
        : pageOf(current) ??
              pages
                  .where((p) => p.items.any((item) => item.video.id == current))
                  .firstOrNull
                  ?.page;
    if (current != null && currentPage != null) {
      hints.remove(current);
      hints[current] = currentPage;
    }
    while (hints.length > 64) {
      hints.remove(hints.keys.first);
    }
    return WatchLaterQueue(
      id: id,
      scope: scope,
      sessionEpoch: sessionEpoch,
      items: [for (final page in pages) ...page.items],
      profileSource: profileSource,
      homeSource: homeSource,
      favoriteTitle: favoriteTitle,
      truncated: truncated ?? this.truncated,
      nextPage: pages.last.page + 1,
      hasMore: pages.last.hasMore,
      pages: pages,
      pageHints: hints,
    );
  }

  bool get isWatchLater =>
      profileSource == null && homeSource == null && favoriteTitle == null;
  String get title =>
      homeSource?.title ??
      favoriteTitle ??
      switch (profileSource) {
        final source? => '${source.name}的投稿',
        null => '稍后再看',
      };

  WatchLaterQueue append(
    List<WatchLaterQueueItem> added, {
    required int nextPage,
    required bool hasMore,
    int drop = 0,
  }) => WatchLaterQueue(
    id: id,
    scope: scope,
    sessionEpoch: sessionEpoch,
    items: [...items.skip(drop), ...added],
    profileSource: profileSource,
    homeSource: homeSource,
    favoriteTitle: favoriteTitle,
    truncated: truncated,
    nextPage: nextPage,
    hasMore: hasMore,
    offset: offset + drop,
    pages: pages,
    pageHints: pageHints,
  );

  /// Keep the current source navigable if another page removes it while playing.
  WatchLaterQueue withoutRemoved(Set<String> removed, {VideoId? current}) {
    if (!isWatchLater) return this;
    if (!items.any(
      (item) => item.video.id != current && removed.contains(item.removalId),
    )) {
      return this;
    }
    return WatchLaterQueue(
      id: id,
      scope: scope,
      sessionEpoch: sessionEpoch,
      profileSource: profileSource,
      homeSource: homeSource,
      favoriteTitle: favoriteTitle,
      truncated: truncated,
      nextPage: nextPage,
      hasMore: hasMore,
      offset: offset,
      pageHints: pageHints,
      pages: [
        for (final page in pages)
          PlaybackQueuePage(
            page: page.page,
            hasMore: page.hasMore,
            items: [
              for (final item in page.items)
                if (item.video.id == current ||
                    !removed.contains(item.removalId))
                  item,
            ],
          ),
      ],
      items: [
        for (final item in items)
          if (item.video.id == current || !removed.contains(item.removalId))
            item,
      ],
    );
  }

  int indexOf(VideoId id) => items.indexWhere((item) => item.video.id == id);
  WatchLaterQueueItem? adjacent(VideoId id, int direction) {
    final current = indexOf(id);
    if (current < 0) return null;
    final index = current + direction;
    return index >= 0 && index < items.length ? items[index] : null;
  }
}

final class WatchLaterQueueItem {
  const WatchLaterQueueItem({
    required this.video,
    this.entryId,
    this.aid,
    this.playCountText = '',
    this.danmakuCountText = '',
  });

  final VideoSummary video;
  final String? entryId, aid;
  String get removalId => entryId ?? video.id.value;
  final String playCountText;
  final String danmakuCountText;
}
