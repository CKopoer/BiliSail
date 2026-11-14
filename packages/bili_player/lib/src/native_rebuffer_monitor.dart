import 'dart:async';
import 'dart:collection';

import 'player_contract.dart';

/// Detects repeated native cache underruns even when small reads keep arriving.
final class NativeRebufferMonitor {
  NativeRebufferMonitor({
    required this.snapshot,
    required this.onStalled,
    Duration Function()? now,
  }) {
    final clock = Stopwatch()..start();
    _now = now ?? () => clock.elapsed;
  }

  static const window = Duration(seconds: 90);
  static const blockedBudget = Duration(seconds: 12);
  static const healthyPeriod = Duration(seconds: 10);
  final PlaybackSnapshot Function() snapshot;
  final void Function(Duration) onStalled;
  late final Duration Function() _now;
  final _episodes = Queue<({Duration at, Duration blocked})>();
  Timer? _deadline;
  int? _generation;
  Duration? _startedAt, _healthyAt;
  Duration _startedPosition = Duration.zero, _healthyPosition = Duration.zero;
  bool _failed = false, _disposed = false;

  bool get _active =>
      !_disposed &&
      snapshot().desiredPlaying &&
      !snapshot().isSeeking &&
      const {
        PlaybackPhase.playing,
        PlaybackPhase.buffering,
      }.contains(snapshot().phase);

  void cachePauseChanged(bool paused) {
    update();
    if (!_active || _failed) return;
    final now = _now();
    if (paused) {
      if (_startedAt != null) return;
      _startedAt = now;
      _startedPosition = snapshot().position;
      _healthyAt = null;
      _check();
    } else if (_startedAt case final started?) {
      final blocked = _blocked(now - started);
      _startedAt = null;
      _deadline?.cancel();
      _deadline = null;
      if (blocked >= const Duration(seconds: 1)) {
        if (_episodes.length == 8) _episodes.removeFirst();
        _episodes.add((at: now, blocked: blocked));
      }
      _healthyAt = now;
      _healthyPosition = snapshot().position;
      _check();
    }
  }

  Duration _blocked(Duration elapsed) {
    final progress = snapshot().position - _startedPosition;
    final rate = snapshot().rate;
    final advancing = progress > Duration.zero && rate.isFinite && rate > 0
        ? Duration(microseconds: (progress.inMicroseconds / rate).round())
        : Duration.zero;
    return elapsed > advancing ? elapsed - advancing : Duration.zero;
  }

  void update() {
    if (_disposed) return;
    if (_generation != snapshot().generation || !_active) {
      reset();
      _generation = snapshot().generation;
      return;
    }
    final now = _now();
    while (_episodes.isNotEmpty && now - _episodes.first.at > window) {
      _episodes.removeFirst();
    }
    if (_healthyAt case final healthy?) {
      // A quiet event stream or a false buffering flag is not healthy playback.
      final progress = snapshot().position - _healthyPosition;
      final rate = snapshot().rate;
      if (now - healthy >= healthyPeriod &&
          rate.isFinite &&
          rate > 0 &&
          progress.inMicroseconds / rate >= healthyPeriod.inMicroseconds) {
        reset();
      }
    }
  }

  void _check() {
    update();
    if (!_active || _failed) return;
    final started = _startedAt;
    final current = started == null
        ? Duration.zero
        : _blocked(_now() - started);
    final total =
        _episodes.fold(Duration.zero, (sum, e) => sum + e.blocked) + current;
    final count =
        _episodes.length + (current >= const Duration(seconds: 1) ? 1 : 0);
    if (count >= 2 && total >= blockedBudget) {
      _failed = true;
      _deadline?.cancel();
      _deadline = null;
      onStalled(total);
    } else if (started != null && _episodes.isNotEmpty) {
      final remaining = blockedBudget - total;
      final minimum = const Duration(seconds: 1) - current;
      var delay = remaining > minimum ? remaining : minimum;
      if (delay <= Duration.zero) delay = const Duration(milliseconds: 100);
      _deadline?.cancel();
      _deadline = Timer(delay, () {
        _deadline = null;
        _check();
      });
    }
  }

  void reset() {
    _deadline?.cancel();
    _deadline = null;
    _episodes.clear();
    _startedAt = _healthyAt = null;
    _failed = false;
  }

  void dispose() {
    _disposed = true;
    reset();
  }
}
