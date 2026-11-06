import 'dart:async';

import 'package:flutter/foundation.dart';

/// A session deadline that survives source changes and time in the background.
class ListeningSleepTimer extends ChangeNotifier {
  ListeningSleepTimer({required this.onElapsed, DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static const maxDuration = Duration(minutes: 1440);

  final VoidCallback onElapsed;
  final DateTime Function() _now;
  DateTime? _deadline;
  Timer? _alarm;
  bool _elapsed = false;

  Duration? get remaining {
    final deadline = _deadline;
    if (deadline == null) return null;
    final value = deadline.difference(_now());
    return value > Duration.zero ? value : Duration.zero;
  }

  // Also gate autoplay when a suspended event loop has not delivered the alarm.
  bool get elapsed => _elapsed || remaining == Duration.zero;

  void start(Duration duration) {
    if (duration <= Duration.zero || duration > maxDuration) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Must be within 24 hours',
      );
    }
    _alarm?.cancel();
    _elapsed = false;
    _deadline = _now().add(duration);
    _alarm = Timer(duration, _onAlarm);
    notifyListeners();
  }

  void checkDeadline() {
    final left = remaining;
    if (left == null) return;
    if (left > Duration.zero) return;
    _alarm?.cancel();
    _alarm = null;
    _deadline = null;
    _elapsed = true;
    // Revoke playback intent before notifying UI or completion listeners.
    onElapsed();
    notifyListeners();
  }

  void _onAlarm() {
    checkDeadline();
    // A system clock adjustment can move the deadline beyond this alarm.
    final left = remaining;
    if (left != null) _alarm = Timer(left, _onAlarm);
  }

  void cancel() {
    _alarm?.cancel();
    _alarm = null;
    _deadline = null;
    _elapsed = false;
    notifyListeners();
  }

  void acknowledgeElapsed() {
    if (!_elapsed) return;
    _elapsed = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _alarm?.cancel();
    super.dispose();
  }
}
