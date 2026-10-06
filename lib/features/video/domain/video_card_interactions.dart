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
