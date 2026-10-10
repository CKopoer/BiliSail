import '../../../domain/video.dart';
import 'watch_later_queue.dart';

typedef VideoSequenceTarget = ({VideoId id, String? cid});

/// Playback order follows metadata, independently of the sidebar's sorting.
VideoSequenceTarget? adjacentVideoSource(
  VideoDetail video,
  String cid,
  int direction, {
  WatchLaterQueue? queue,
}) {
  final index = video.parts.indexWhere((part) => part.cid == cid);
  if (index < 0 || (direction != -1 && direction != 1)) return null;
  final nextPart = index + direction;
  if (nextPart >= 0 && nextPart < video.parts.length) {
    return (id: video.summary.id, cid: video.parts[nextPart].cid);
  }
  // A watch-later entry retains its originating queue as the outer sequence.
  if (queue != null) {
    final next = queue.adjacent(video.summary.id, direction);
    return next == null ? null : (id: next.video.id, cid: null);
  }
  final entries = video.collection?.entries;
  if (entries == null) return null;
  final current = entries.indexWhere((entry) => entry.id == video.summary.id);
  final next = current + direction;
  if (current < 0 || next < 0 || next >= entries.length) return null;
  final entry = entries[next];
  return (id: entry.id, cid: entry.parts.firstOrNull?.cid);
}
