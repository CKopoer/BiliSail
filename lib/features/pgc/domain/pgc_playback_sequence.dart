import 'pgc_repository.dart';

/// Advance within the selected 正片/SP section, using its original order.
PgcEpisode? adjacentPgcEpisode(
  PgcSeason season,
  PgcEpisode selected,
  int direction,
) {
  if (direction != -1 && direction != 1) return null;
  final episodes = season.episodes
      .where((episode) => episode.sectionTitle == selected.sectionTitle)
      .toList();
  final index = episodes.indexWhere((episode) => episode.id == selected.id);
  final next = index + direction;
  if (index < 0 || next < 0 || next >= episodes.length) return null;
  // Permission restrictions are a stopping point, not a reason to skip ahead.
  return episodes[next].playable ? episodes[next] : null;
}
