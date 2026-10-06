/// Shared by playback pages for one application run; never persisted.
final class PlaybackRateMemory {
  double? _rate;
  int _revision = 0;

  double rateFor(double defaultRate) => _rate ?? defaultRate;

  int beginChange() => ++_revision;

  /// A slower native command must not replace a newer choice in another tab.
  void remember(double rate, {required int revision}) {
    if (revision == _revision) _rate = rate;
  }
}
