/// Shared by formal playback sessions for one application run.
final class PlaybackListeningMode {
  bool _enabled = false;
  bool get enabled => _enabled;
  final _listeners = <Future<void> Function()>{};
  Future<void> _applying = Future.value();

  void addListener(Future<void> Function() listener) =>
      _listeners.add(listener);
  void removeListener(Future<void> Function() listener) =>
      _listeners.remove(listener);

  Future<void> select(bool enabled) {
    if (_enabled == enabled) return _applying;
    _enabled = enabled;
    // Publish the choice before reopening any source. New sessions and late
    // navigation results must observe the latest choice immediately.
    return _applying = Future.wait([
      for (final listener in _listeners.toList()) Future<void>.sync(listener),
    ]).then((_) {});
  }
}
