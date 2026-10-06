import '../../../domain/video.dart';

/// A read-only snapshot of the selected watch-later subtab at navigation time.
final class WatchLaterQueue {
  WatchLaterQueue({
    required this.id,
    required this.scope,
    required this.sessionEpoch,
    required List<WatchLaterQueueItem> items,
  }) : items = List.unmodifiable(items);

  final String id;
  final String scope;
  final int sessionEpoch;
  final List<WatchLaterQueueItem> items;

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
    this.playCountText = '',
    this.danmakuCountText = '',
  });

  final VideoSummary video;
  final String playCountText;
  final String danmakuCountText;
}
