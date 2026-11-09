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
    this.lastEpisodeId,
  }) : episodes = List.unmodifiable(episodes),
       relatedSeasons = List.unmodifiable(relatedSeasons);
  final PgcSeasonId id;
  final String title, description;
  final Uri? coverUrl;
  final int? type, playCount, danmakuCount, followCount;
  final double? rating;
  final String? publishText;
  final PgcEpisodeId? lastEpisodeId;
  final List<PgcEpisode> episodes;
  final List<PgcSeasonSummary> relatedSeasons;
  // The immutable season owns all episode derivations. A refreshed season gets
  // a new index; panel rebuilds and playback sequencing share this one instance.
  late final _episodeIndex = _PgcEpisodeIndex(episodes);

  String get seasonId => id.value;
  Map<String, List<PgcEpisode>> get episodeGroups => _episodeIndex.groups;
  PgcEpisode? get firstPlayableEpisode => _episodeIndex.firstPlayable;
  PgcEpisode? episode(PgcEpisodeId? id) => _episodeIndex.locations[id]?.episode;
  int episodePosition(PgcEpisodeId? id) =>
      _episodeIndex.locations[id]?.position ?? -1;
  int episodeGroupPosition(PgcEpisodeId? id, {String? section}) =>
      _episodeIndex.groupPositions[(
        section ?? pgcEpisodeSection(episode(id)),
        id,
      )] ??
      -1;

  PgcEpisode? adjacentEpisode(PgcEpisode selected, int direction) {
    if (direction != -1 && direction != 1) return null;
    final position =
        _episodeIndex.sequencePositions[(selected.sectionTitle, selected.id)];
    if (position == null) return null;
    final group = _episodeIndex.sequenceGroups[selected.sectionTitle]!;
    final next = position + direction;
    if (next < 0 || next >= group.length) return null;
    return group[next];
  }
}

String pgcEpisodeSection(PgcEpisode? episode) {
  final title = episode?.sectionTitle?.trim();
  return title == null || title.isEmpty ? '正片' : title;
}

final class _PgcEpisodeIndex {
  _PgcEpisodeIndex(List<PgcEpisode> episodes) {
    final grouped = <String, List<PgcEpisode>>{};
    for (var i = 0; i < episodes.length; i++) {
      final episode = episodes[i];
      final section = pgcEpisodeSection(episode);
      final group = grouped.putIfAbsent(section, () => []);
      // Display labels normalize whitespace; continuous playback retains the
      // original section identity, including the null/empty distinction.
      final sequence = sequenceGroups.putIfAbsent(
        episode.sectionTitle,
        () => [],
      );
      locations.putIfAbsent(episode.id, () => (episode: episode, position: i));
      groupPositions.putIfAbsent((section, episode.id), () => group.length);
      sequencePositions.putIfAbsent((
        episode.sectionTitle,
        episode.id,
      ), () => sequence.length);
      group.add(episode);
      sequence.add(episode);
      if (firstPlayable == null && episode.playable) firstPlayable = episode;
    }
    groups = Map.unmodifiable(
      grouped.map(
        (key, value) => MapEntry(key, List<PgcEpisode>.unmodifiable(value)),
      ),
    );
  }

  late final Map<String, List<PgcEpisode>> groups;
  final locations = <PgcEpisodeId, ({PgcEpisode episode, int position})>{};
  final groupPositions = <(String, PgcEpisodeId?), int>{};
  final sequencePositions = <(String?, PgcEpisodeId), int>{};
  final sequenceGroups = <String?, List<PgcEpisode>>{};
  PgcEpisode? firstPlayable;
}

abstract interface class PgcRepository {
  String get accountScope;
  int get sessionEpoch;
  Future<PgcSeason> detail({
    PgcSeasonId? seasonId,
    PgcEpisodeId? episodeId,
    bool refresh = false,
    required RequestCancellation cancellation,
  });
}
