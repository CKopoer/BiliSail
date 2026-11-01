import 'dart:async';

final class SourceSuperseded implements Exception {
  const SourceSuperseded();
}

/// Releases asynchronously created native resources if their owner has left.
Future<T> waitForNativeResource<T>({
  required Future<T> creating,
  required Future<void> Function(T) dispose,
  required bool Function() superseded,
  required List<Stream<Object?>> changes,
  required Duration timeout,
}) async {
  ({T value})? created;
  var abandoned = false, claimed = false;
  final completion = creating.then<void>((value) async {
    if (abandoned) {
      await dispose(value);
    } else {
      created = (value: value);
    }
  });
  try {
    await waitForNativeSignal(
      signal: completion,
      superseded: superseded,
      changes: changes,
      timeout: timeout,
    );
    if (created case final resource?) {
      claimed = true;
      return resource.value;
    }
    throw StateError('Native resource creation completed without a resource.');
  } finally {
    if (!claimed) {
      abandoned = true;
      if (created case final resource?) await dispose(resource.value);
    }
  }
}

/// An output signal is independent of decoder metadata. Keep it inside the
/// source deadline and interrupt it on cancellation without retaining listeners.
Future<void> waitForNativeSignal({
  required Future<void> signal,
  required bool Function() superseded,
  required List<Stream<Object?>> changes,
  required Duration timeout,
  Object? Function()? failure,
}) async {
  var signalled = false;
  (Object, StackTrace)? signalFailure;
  final completion = signal.then<void>(
    (_) => signalled = true,
    onError: (Object error, StackTrace stack) {
      signalFailure = (error, stack);
      signalled = true;
    },
  );
  await waitForNativeState(
    ready: () => signalled,
    superseded: superseded,
    changes: [Stream<void>.fromFuture(completion), ...changes],
    timeout: timeout,
    failure: failure,
  );
  if (signalFailure case final error?) {
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
  Object? Function()? failure,
}) async {
  if (superseded()) throw const SourceSuperseded();
  if (failure?.call() case final error?) throw error;
  if (ready()) return;
  final done = Completer<void>();
  void check() {
    if (done.isCompleted) return;
    if (superseded()) {
      done.completeError(const SourceSuperseded());
    } else if (failure?.call() case final error?) {
      done.completeError(error);
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
