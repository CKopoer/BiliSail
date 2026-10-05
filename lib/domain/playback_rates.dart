/// Shared speed choices for playback controls and persisted preferences.
abstract final class PlaybackRates {
  static const values = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];

  static double faster(double current) => values.firstWhere(
    (rate) => rate > (current.isFinite ? current : 1),
    orElse: () => values.last,
  );

  static double slower(double current) => values.reversed.firstWhere(
    (rate) => rate < (current.isFinite ? current : 1),
    orElse: () => values.first,
  );

  /// Migrate speeds produced by the old continuous settings slider to a step.
  static double nearest(double current) {
    if (!current.isFinite) return 1;
    return values.reduce(
      (nearest, rate) =>
          (rate - current).abs() < (nearest - current).abs() ? rate : nearest,
    );
  }
}
