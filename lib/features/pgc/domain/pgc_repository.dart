import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

final class PgcSeasonId {
  const PgcSeasonId(this.value);
  final String value;
  @override
  bool operator ==(Object other) =>
      other is PgcSeasonId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

final class PgcEpisodeId {
  const PgcEpisodeId(this.value);
  final String value;
  @override
  bool operator ==(Object other) =>
      other is PgcEpisodeId && other.value == value;
  @override
  int get hashCode => value.hashCode;
}

/// A season link or an episode link can identify the same detail page.
final class PgcLocator {
  const PgcLocator({this.seasonId, this.episodeId});
  final PgcSeasonId? seasonId;
  final PgcEpisodeId? episodeId;

  @override
  bool operator ==(Object other) =>
      other is PgcLocator &&
      other.seasonId == seasonId &&
      other.episodeId == episodeId;
  @override
  int get hashCode => Object.hash(seasonId, episodeId);
}

final class PgcEpisode {
  const PgcEpisode({
    required this.id,
    required this.title,
    this.longTitle = '',
    this.aid,
    this.bvid,
    this.cid,
    this.coverUrl,
    this.duration,
    this.badge,
    this.sectionTitle,
    this.available = true,
    this.permissionText,
  });
  final PgcEpisodeId id;
  final String title, longTitle;
  final String? aid, bvid, cid;
  final Uri? coverUrl;
  final Duration? duration;
  final String? badge, sectionTitle, permissionText;
  final bool available;

  String get episodeId => id.value;
  String get displayTitle => longTitle.trim().isEmpty
      ? title
      : title.trim().isEmpty
      ? longTitle
      : '$title $longTitle';
  bool get playable =>
      available &&
      VideoId(bvid ?? '').isValid &&
      RegExp(r'^[1-9][0-9]*$').hasMatch(cid ?? '');
  String get unavailableReason {
    if (!available) return permissionText ?? '当前剧集暂无观看权限';
    if (!playable) return '当前剧集缺少有效的播放标识，暂时无法播放';
    return '';
  }
}

final class PgcSeasonSummary {
  const PgcSeasonSummary({
    required this.id,
    required this.title,
    this.coverUrl,
  });

  final PgcSeasonId id;
  final String title;
  final Uri? coverUrl;

  String get seasonId => id.value;
}

final class PgcSeason {
  PgcSeason({
    required this.id,
    required this.title,
    required List<PgcEpisode> episodes,
    List<PgcSeasonSummary> relatedSeasons = const [],
    this.coverUrl,
    this.description = '',
    this.type,
    this.rating,
    this.playCount,
    this.danmakuCount,
    this.followCount,
    this.publishText,
  }) : episodes = List.unmodifiable(episodes),
       relatedSeasons = List.unmodifiable(relatedSeasons);
  final PgcSeasonId id;
  final String title, description;
  final Uri? coverUrl;
  final int? type, playCount, danmakuCount, followCount;
  final double? rating;
  final String? publishText;
  final List<PgcEpisode> episodes;
  final List<PgcSeasonSummary> relatedSeasons;

  String get seasonId => id.value;
  PgcEpisode? episode(PgcEpisodeId? id) {
    if (id == null) return null;
    for (final episode in episodes) {
      if (episode.id == id) return episode;
    }
    return null;
  }
}

abstract interface class PgcRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    required RequestCancellation cancellation,
  });
}
