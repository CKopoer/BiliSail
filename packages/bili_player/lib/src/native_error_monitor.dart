import 'dart:async';

import 'player_contract.dart';

/// media_kit's error stream includes mpv log lines, not just terminal failures.
/// Give a running source time to demonstrate recovery through confirmed position.
final class NativeErrorMonitor {
  static const stallTimeout = Duration(seconds: 2);
  static const bufferingTimeout = Duration(seconds: 30);

  NativeErrorMonitor({
    required this.onStalled,
    required this.onRecovered,
    this.gracePeriod = stallTimeout,
    this.bufferingGracePeriod = bufferingTimeout,
  });

  final void Function(int generation) onStalled;
  final void Function(int generation) onRecovered;
  final Duration gracePeriod;
  final Duration bufferingGracePeriod;
  PlaybackSnapshot? _last;
  bool _pending = false;
  Timer? _timer;
  bool _waitingForBuffer = false;

  void report(PlaybackSnapshot snapshot) {
    update(snapshot);
    // Opening has its own bounded track/decoder readiness checks.
    if (_terminal(snapshot) || snapshot.phase == PlaybackPhase.opening) return;
    _pending = true;
    _arm(snapshot);
  }

  void update(PlaybackSnapshot snapshot) {
    final previous = _last;
    _last = snapshot;
    if (previous?.generation != snapshot.generation || _terminal(snapshot)) {
      reset();
      return;
    }
    if (!_pending) return;
    if (!snapshot.desiredPlaying || snapshot.isSeeking) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (previous != null &&
        previous.desiredPlaying &&
        !previous.isSeeking &&
        !snapshot.isBuffering &&
        snapshot.phase == PlaybackPhase.playing &&
        snapshot.position > previous.position) {
      reset();
      onRecovered(snapshot.generation);
      return;
    }
    _arm(snapshot);
  }

  bool _terminal(PlaybackSnapshot snapshot) => const {
    PlaybackPhase.idle,
    PlaybackPhase.ended,
    PlaybackPhase.failed,
    PlaybackPhase.disposed,
  }.contains(snapshot.phase);

  void _arm(PlaybackSnapshot snapshot) {
    if (!snapshot.desiredPlaying || snapshot.isSeeking) {
      return;
    }
    if (_timer != null && _waitingForBuffer == snapshot.isBuffering) return;
    _timer?.cancel();
    _waitingForBuffer = snapshot.isBuffering;
    _timer = Timer(
      snapshot.isBuffering ? bufferingGracePeriod : gracePeriod,
      () {
        reset();
        onStalled(snapshot.generation);
      },
    );
  }

  void reset() {
    _pending = false;
    _timer?.cancel();
    _timer = null;
  }
}
