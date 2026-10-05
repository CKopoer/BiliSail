/// Public PGC metadata. IDs stay as decimal strings to avoid precision loss.
final class ApiPgcSeason {
  const ApiPgcSeason({
    required this.seasonId,
    required this.title,
    required this.coverUrl,
    required this.description,
    required this.type,
    required this.episodes,
    required this.relatedSeasons,
    this.rating,
    this.playCount,
    this.danmakuCount,
    this.followCount,
    this.publishText,
  });

  final String seasonId;
  final String title;
  final Uri? coverUrl;
  final String description;
  final int? type;
  final List<ApiPgcEpisode> episodes;
  final double? rating;
  final int? playCount;
  final int? danmakuCount;
  final int? followCount;
  final String? publishText;
  final List<ApiPgcSeasonSummary> relatedSeasons;
}

final class ApiPgcEpisode {
  const ApiPgcEpisode({
    required this.episodeId,
    required this.aid,
    required this.bvid,
    required this.cid,
    required this.title,
    required this.longTitle,
    required this.coverUrl,
    required this.duration,
    required this.badge,
    required this.sectionTitle,
    required this.playable,
    required this.permissionText,
  });

  final String episodeId;
  final String? aid;
  final String? bvid;
  final String? cid;
  final String title;
  final String longTitle;
  final Uri? coverUrl;
  final Duration? duration;
  final String? badge;
  final String? sectionTitle;

  /// The listing says this episode is published; final rights come from playurl.
  final bool playable;
  final String? permissionText;
}

final class ApiPgcSeasonSummary {
  const ApiPgcSeasonSummary({
    required this.seasonId,
    required this.title,
    required this.coverUrl,
  });

  final String seasonId;
  final String title;
  final Uri? coverUrl;
}
