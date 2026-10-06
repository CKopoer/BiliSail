import 'package:bili_player/bili_player.dart';

import '../../../domain/video.dart';
import '../../playback/application/playback_session.dart';
import '../domain/watch_later_queue.dart';

/// Chooses the next source while leaving engine ownership with PlaybackSession.
final class WatchLaterQueuePlayback {
  int? _handledEndGeneration;

  void reset() => _handledEndGeneration = null;

  bool _valid(WatchLaterQueue queue, PlaybackSession session) =>
      queue.scope == session.accountScope() &&
      queue.sessionEpoch == session.sessionEpoch();

  /// Explicit selection preserves play/pause intent; completion resumes.
  bool select(WatchLaterQueue queue, PlaybackSession session, VideoId nextId) {
    if (!_valid(queue, session) || queue.indexOf(nextId) < 0) return false;
    final currentId = session.detail?.summary.id;
    final currentCid = session.part?.cid;
    if (currentId != null && currentCid != null) {
      session.prepareNextVideo(currentId, currentCid, nextId: nextId);
    }
    return true;
  }

  VideoId? adjacent(
    WatchLaterQueue queue,
    PlaybackSession session,
    VideoId current,
    int direction,
  ) => _valid(queue, session)
      ? queue.adjacent(current, direction)?.video.id
      : null;

  ({VideoPart? part, VideoId? video})? completed(
    WatchLaterQueue queue,
    PlaybackSession session,
    VideoId current,
  ) {
    final generation = session.sourceGeneration;
    if (!_valid(queue, session) ||
        session.sourceAccountScope != queue.scope ||
        session.media == null ||
        session.snapshots.value.phase != PlaybackPhase.ended ||
        session.detail?.summary.id != current ||
        queue.indexOf(current) < 0 ||
        _handledEndGeneration == generation) {
      return null;
    }
    _handledEndGeneration = generation;
    final detail = session.detail;
    final selected = session.part;
    if (detail == null || selected == null) return null;
    final index = detail.parts.indexWhere((part) => part.cid == selected.cid);
    if (index >= 0 && index + 1 < detail.parts.length) {
      final next = detail.parts[index + 1];
      if (!session.prepareNextVideo(
        detail.summary.id,
        selected.cid,
        nextId: detail.summary.id,
        nextCid: next.cid,
        completed: true,
      )) {
        return null;
      }
      return (part: next, video: null);
    }
    final next = queue.adjacent(current, 1)?.video.id;
    if (next == null ||
        !session.prepareNextVideo(
          detail.summary.id,
          selected.cid,
          nextId: next,
          completed: true,
        )) {
      return null;
    }
    return (part: null, video: next);
  }
}
