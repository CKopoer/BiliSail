/// Shared speed choices for playback controls and persisted preferences.
abstract final class PlaybackRates {
  static const values = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0, 3.0];
  static const requiredValues = [0.5, 1.0, 2.0];
  static const maxOptions = 9;
  static const min = 0.25;
  static const max = 5.0;

  static bool isValid(double rate) =>
      rate.isFinite &&
      rate >= min &&
      rate <= max &&
      (rate * 100 - (rate * 100).round()).abs() < 0.000001;

  static List<double> normalize(Iterable<double> rates) {
    final result = <double>{...requiredValues};
    for (final rate in rates) {
      if (isValid(rate)) result.add((rate * 100).round() / 100);
      if (result.length == maxOptions) break;
    }
    return List.unmodifiable(result.toList()..sort());
  }

  static List<double> fromJson(Object? value) => value is List
      ? normalize(value.whereType<num>().map((rate) => rate.toDouble()))
      : values;

  static double faster(double current, [List<double> options = values]) =>
      options.firstWhere(
        (rate) => rate > (current.isFinite ? current : 1),
        orElse: () => options.last,
      );

  static double slower(double current, [List<double> options = values]) =>
      options.reversed.firstWhere(
        (rate) => rate < (current.isFinite ? current : 1),
        orElse: () => options.first,
      );

  /// Migrate speeds produced by the old continuous settings slider to a step.
  static double nearest(double current, [List<double> options = values]) {
    if (!current.isFinite) return 1;
    return options.reduce(
      (nearest, rate) =>
          (rate - current).abs() < (nearest - current).abs() ? rate : nearest,
    );
  }
}
