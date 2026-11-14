import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import '../../playback/application/card_preview_playback.dart';
import '../domain/video_card_interactions.dart';

abstract interface class VideoCardOperations implements VideoCardInteractions {
  Future<VideoCardPreviewSession?> preview(
    VideoId id,
    RequestCancellation cancellation, {
    String? cid,
  });
}

// Compatibility names for video card operations and existing callers.
typedef VideoCardPreviewSession = CardPreviewSession;
typedef VideoCardPreviewPlayback = CardPreviewPlayback;
