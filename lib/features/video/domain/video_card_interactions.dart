import '../../../domain/video.dart';

enum WatchLaterResult {
  added,
  alreadyAdded,
  signIn,
  busy,
  uncertain,
  failed,
  cancelled,
}

abstract interface class VideoCardInteractions {
  Future<WatchLaterResult> addWatchLater(VideoId id);
  bool isAdded(VideoId id);
  bool isUncertain(VideoId id);
}

/// Optional synchronization port for explicit deletion from the watch-later list.
abstract interface class VideoCardWatchLaterRemovalSync {
  bool beginWatchLaterRemoval(VideoId id);
  void finishWatchLaterRemoval(
    VideoId id, {
    bool removed = false,
    bool uncertain = false,
  });
}
