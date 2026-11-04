import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

enum WatchLaterResult {
  added,
  alreadyAdded,
  removed,
  signIn,
  busy,
  uncertain,
  failed,
  cancelled,
}

/// Account-owned membership and explicit removal, supplied by the app root.
abstract interface class VideoCardWatchLaterRepository {
  Future<Map<VideoId, String>> load(RequestCancellation cancellation);
  Future<bool> remove(VideoId id, String aid, RequestCancellation cancellation);
}

abstract interface class VideoCardWatchLaterToggle
    implements VideoCardInteractions {
  Stream<VideoId> get watchLaterChanges;
  bool isWatchLaterBusy(VideoId id);
  Future<bool> refreshWatchLater();
  Future<WatchLaterResult> removeWatchLater(VideoId id);
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
