import 'dart:collection';

import 'player_contract.dart';

/// Detect repeated, error-associated pauses without retiring recoverable frames.
final class NativeVideoBufferMonitor {
  NativeVideoBufferMonitor({
    required this.onStalled,
    Duration Function()? now,
  }) {
    final clock = Stopwatch()..start();
    _now = now ?? () => clock.elapsed;
  }

  final void Function(Duration blockedFor) onStalled;
  late final Duration Function() _now;
  final _episodes = Queue<({Duration at, Duration blocked})>();
  int? _generation;
  Duration? _errorAt, _startedAt, _healthyAt;
  Duration _startedPosition = Duration.zero;
  bool _episodeHasError = false, _failed = false;

  void report(PlaybackSnapshot snapshot) {
    update(snapshot);
    if (!_active(snapshot) || _failed) return;
    _errorAt = _now();
    if (snapshot.isBuffering) _episodeHasError = true;
  }

  bool _active(PlaybackSnapshot snapshot) =>
      snapshot.desiredPlaying &&
      !snapshot.isSeeking &&
      const {
        PlaybackPhase.playing,
        PlaybackPhase.buffering,
      }.contains(snapshot.phase);

  void update(PlaybackSnapshot snapshot) {
    if (_generation != snapshot.generation || !_active(snapshot)) {
      reset();
      _generation = snapshot.generation;
      if (!_active(snapshot)) return;
    }
    if (_failed) return;
    final now = _now();
    while (_episodes.isNotEmpty &&
        now - _episodes.first.at > const Duration(seconds: 30)) {
      _episodes.removeFirst();
    }
    if (_healthyAt case final healthy?) {
      if (now - healthy >= const Duration(seconds: 10)) {
        _episodes.clear();
        _errorAt = null;
      }
    }
    if (snapshot.isBuffering) {
      if (_startedAt == null) {
        _startedAt = now;
        _startedPosition = snapshot.position;
        _episodeHasError =
            _errorAt != null && now - _errorAt! <= const Duration(seconds: 2);
      }
      _healthyAt = null;
      return;
    }
    _healthyAt ??= now;
    final started = _startedAt;
    _startedAt = null;
    if (started == null || !_episodeHasError) return;
    // Native buffering can pulse while queued audio/video still advances.
    // Count only wall time not explained by confirmed media-time progress.
    final progress = snapshot.position - _startedPosition;
    final rate = snapshot.rate.isFinite && snapshot.rate > 0
        ? snapshot.rate
        : 1;
    final advancing = progress > Duration.zero
        ? Duration(microseconds: (progress.inMicroseconds / rate).round())
        : Duration.zero;
    final blocked = now - started - advancing;
    if (blocked < const Duration(seconds: 1)) return;
    if (_episodes.length == 8) _episodes.removeFirst();
    _episodes.add((at: now, blocked: blocked));
    final total = _episodes.fold(
      Duration.zero,
      (sum, episode) => sum + episode.blocked,
    );
    if (_episodes.length >= 3 && total >= const Duration(seconds: 6)) {
      _failed = true;
      onStalled(total);
    }
  }

  void reset() {
    _episodes.clear();
    _errorAt = _startedAt = _healthyAt = null;
    _episodeHasError = _failed = false;
  }
}
