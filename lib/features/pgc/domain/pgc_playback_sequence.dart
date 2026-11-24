import 'pgc_repository.dart';

/// Advance within the selected 正片/SP section, using its original order.
PgcEpisode? adjacentPgcEpisode(
  PgcSeason season,
  PgcEpisode selected,
  int direction, {
  bool loop = false,
}) {
  if (season.course) {
    final index = season.episodePosition(selected.id);
    if (index < 0 || direction.abs() != 1) return null;
    final count = season.episodes.length;
    final next = loop ? (index + direction) % count : index + direction;
    if (next < 0 || next >= count) return null;
    final lesson = season.episodes[next];
    return lesson.playable ? lesson : null;
  }
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
