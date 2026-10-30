import '../../../domain/video.dart';
import '../../../domain/user.dart';

/// Public submissions are read lazily, independently of the space's filters.
final class ProfileVideoQueueSource {
  const ProfileVideoQueueSource({
    required this.userId,
    required this.name,
    required this.order,
  });

  final UserId userId;
  final String name, order;
}

/// An account-scoped queue shared by watch-later and public submissions.
final class WatchLaterQueue {
  WatchLaterQueue({
    required this.id,
    required this.scope,
    required this.sessionEpoch,
    required List<WatchLaterQueueItem> items,
    this.profileSource,
    this.nextPage = 1,
    this.hasMore = false,
    this.offset = 0,
  }) : items = List.unmodifiable(items);

  final String id;
  final String scope;
  final int sessionEpoch;
  final List<WatchLaterQueueItem> items;
  final ProfileVideoQueueSource? profileSource;
  final int nextPage, offset;
  final bool hasMore;
  bool get isWatchLater => profileSource == null;
  String get title => switch (profileSource) {
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
    nextPage: nextPage,
    hasMore: hasMore,
    offset: offset + drop,
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
