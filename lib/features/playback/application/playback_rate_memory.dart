/// Shared by playback pages for one application run; never persisted.
final class PlaybackRateMemory {
  bool _enabled = true;
  double? _rate;
  int _revision = 0;

  double rateFor(double defaultRate) =>
      _enabled ? _rate ?? defaultRate : defaultRate;

  void configure({required bool enabled}) {
    if (_enabled == enabled) return;
    _enabled = enabled;
    _rate = null;
    // Commands started before a toggle must not restore a discarded choice.
    ++_revision;
  }

  int beginChange() => ++_revision;

  /// A slower native command must not replace a newer choice in another tab.
  void remember(double rate, {required int revision}) {
    if (_enabled && revision == _revision) _rate = rate;
  }
}
