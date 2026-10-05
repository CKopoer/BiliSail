import '../../../domain/video.dart';
import '../domain/playback_repository.dart';

/// The shared SQLite owner supplies operations at the composition root, without
/// making playback import another feature's data implementation.
class LocalProgressStore implements PlaybackProgressStore {
  LocalProgressStore({required this.readProgress, required this.writeProgress});
  final Future<Duration> Function(String, VideoId, String) readProgress;
  final Future<void> Function(
    String,
    VideoSummary,
    VideoPart,
    Duration,
    Duration, {
    String? episodeId,
  })
  writeProgress;

  @override
  Future<Duration> read(String scope, VideoId video, String cid) =>
      readProgress(scope, video, cid);
  @override
  Future<void> write(
    String scope,
    VideoSummary video,
    VideoPart part,
    Duration position,
    Duration duration, {
    String? episodeId,
  }) => writeProgress(
    scope,
    video,
    part,
    position,
    duration,
    episodeId: episodeId,
  );
}
