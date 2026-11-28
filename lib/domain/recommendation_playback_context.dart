/// Opaque server attribution, kept in memory and bound to one account epoch/video.
final class RecommendationPlaybackContext {
  const RecommendationPlaybackContext({
    this.videoId = '',
    this.episodeId,
    this.fromSpmid = 'tm.recommend.0.0',
    required this.trackId,
    required this.sessionEpoch,
  });
  final String videoId;
  final String? episodeId;
  final String trackId;
  final int sessionEpoch;
  final String? fromSpmid;

  bool matches(String id, int epoch, {String? episode}) =>
      sessionEpoch == epoch &&
      (episodeId != null
          ? episodeId == episode
          : episode == null && videoId.isNotEmpty && videoId == id);
}
