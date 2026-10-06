import 'dart:async';

final class SourceSuperseded implements Exception {
  const SourceSuperseded();
}

/// An output signal is independent of decoder metadata. Keep it inside the
/// source deadline and interrupt it on cancellation without retaining listeners.
Future<void> waitForNativeSignal({
  required Future<void> signal,
  required bool Function() superseded,
  required List<Stream<Object?>> changes,
  required Duration timeout,
}) async {
  var signalled = false;
  (Object, StackTrace)? failure;
  final completion = signal.then<void>(
    (_) => signalled = true,
    onError: (Object error, StackTrace stack) {
      failure = (error, stack);
      signalled = true;
    },
  );
  await waitForNativeState(
    ready: () => signalled,
    superseded: superseded,
    changes: [Stream<void>.fromFuture(completion), ...changes],
    timeout: timeout,
  );
  if (failure case final error?) {
    Error.throwWithStackTrace(error.$1, error.$2);
  }
}

/// Waits for a backend state predicate, including events that race with
/// subscription setup. Callers include a generation-change stream so a new
/// source interrupts the wait promptly.
Future<void> waitForNativeState({
  required bool Function() ready,
  required bool Function() superseded,
  required List<Stream<Object?>> changes,
  required Duration timeout,
}) async {
  if (superseded()) throw const SourceSuperseded();
  if (ready()) return;
  final done = Completer<void>();
  void check() {
    if (done.isCompleted) return;
    if (superseded()) {
      done.completeError(const SourceSuperseded());
    } else if (ready()) {
      done.complete();
    }
  }

  final subscriptions = <StreamSubscription<Object?>>[];
  try {
    for (final stream in changes) {
      subscriptions.add(
        stream.listen(
          (_) => check(),
          onError: (Object _, StackTrace stackTrace) => check(),
        ),
      );
    }
    check();
    await done.future.timeout(timeout);
  } finally {
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
  }
}
