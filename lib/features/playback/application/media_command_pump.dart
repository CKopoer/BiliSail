import 'dart:async';

/// At most one native call and one latest pending target, even with key repeats.
final class MediaCommandPump {
  Future<void> Function()? _pending;
  Completer<void>? _completion;
  bool _running = false;
  Future<void> submit(Future<void> Function() action) {
    _pending = action;
    final completion = _completion ??= Completer<void>();
    if (!_running) {
      _running = true;
      unawaited(_drain());
    }
    return completion.future;
  }

  void discardPending() {
    _pending = null;
    _completion?.complete();
    _completion = null;
  }

  Future<void> _drain() async {
    while (true) {
      final action = _pending;
      if (action == null) {
        break;
      }
      final completion = _completion;
      _pending = null;
      _completion = null;
      try {
        await action();
        completion?.complete();
      } catch (error, stack) {
        completion?.completeError(error, stack);
        discardPending();
      }
    }
    _running = false;
  }
}
