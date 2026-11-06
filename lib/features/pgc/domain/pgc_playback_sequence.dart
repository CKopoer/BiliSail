import 'pgc_repository.dart';

/// Advance within the selected 正片/SP section, using its original order.
PgcEpisode? adjacentPgcEpisode(
  PgcSeason season,
  PgcEpisode selected,
  int direction, {
  bool loop = false,
}) {
  var next = season.adjacentEpisode(selected, direction);
  if (next == null &&
      loop &&
      (direction == -1 || direction == 1) &&
      season.episode(selected.id) != null) {
    final group = season.episodes.where(
      (episode) => episode.sectionTitle == selected.sectionTitle,
    );
    next = direction > 0 ? group.firstOrNull : group.lastOrNull;
  }
  // Permission restrictions are a stopping point, not a reason to skip ahead.
  return next?.playable == true ? next : null;
}
