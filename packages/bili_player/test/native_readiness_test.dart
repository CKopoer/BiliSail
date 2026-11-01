import 'dart:async';

import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final cancel in [true, false]) {
    test(
      'late native creation is released after ${cancel ? 'cancel' : 'timeout'}',
      () async {
        final creating = Completer<int>();
        final changes = StreamController<Object?>.broadcast(sync: true);
        var superseded = false;
        final released = <int>[];
        final waiting = waitForNativeResource(
          creating: creating.future,
          dispose: (value) async => released.add(value),
          superseded: () => superseded,
          changes: [changes.stream],
          timeout: const Duration(milliseconds: 10),
        );
        final assertion = expectLater(
          waiting,
          throwsA(cancel ? isA<SourceSuperseded>() : isA<TimeoutException>()),
        );
        if (cancel) {
          superseded = true;
          changes.add(null);
        }
        await assertion;
        expect(changes.hasListener, false);
        creating.complete(42);
        await Future<void>.delayed(Duration.zero);
        expect(released, [42]);
        await changes.close();
      },
    );
  }

  test('created native resource transfers to the current owner once', () async {
    final released = <int>[];
    final value = await waitForNativeResource(
      creating: Future.value(42),
      dispose: (value) async => released.add(value),
      superseded: () => false,
      changes: const [],
      timeout: const Duration(seconds: 1),
    );
    expect(value, 42);
    expect(released, isEmpty);
  });

  test(
    'first output signal is required even after decoder metadata is ready',
    () async {
      final signal = Completer<void>();
      var completed = false;
      final waiting = waitForNativeSignal(
        signal: signal.future,
        superseded: () => false,
        changes: const [],
        timeout: const Duration(seconds: 1),
      ).then((_) => completed = true);
      await Future<void>.delayed(Duration.zero);
      expect(completed, false);
      signal.complete();
      await waiting;
      expect(completed, true);
    },
  );

  test(
    'already rendered output does not wait for another notification',
    () async {
      await waitForNativeSignal(
        signal: Future<void>.value(),
        superseded: () => false,
        changes: const [],
        timeout: const Duration(seconds: 1),
      );
    },
  );

  test(
    'leaving before first output interrupts waiting and ignores late rendering',
    () async {
      final signal = Completer<void>();
      final changes = StreamController<Object?>.broadcast(sync: true);
      var superseded = false;
      final waiting = waitForNativeSignal(
        signal: signal.future,
        superseded: () => superseded,
        changes: [changes.stream],
        timeout: const Duration(seconds: 1),
      );
      superseded = true;
      changes.add(null);
      await expectLater(waiting, throwsA(isA<SourceSuperseded>()));
      expect(changes.hasListener, false);
      signal.completeError(StateError('late disposed output'));
      await Future<void>.delayed(Duration.zero);
      await changes.close();
    },
  );

  test('first output deadline releases generation listeners', () async {
    final signal = Completer<void>();
    final changes = StreamController<Object?>.broadcast(sync: true);
    await expectLater(
      waitForNativeSignal(
        signal: signal.future,
        superseded: () => false,
        changes: [changes.stream],
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(changes.hasListener, false);
    signal.complete();
    await changes.close();
  });

  test(
    'output initialization error is preserved without waiting for the deadline',
    () async {
      final signal = Completer<void>();
      final changes = StreamController<Object?>.broadcast(sync: true);
      final failure = StateError('output unavailable');
      final waiting = waitForNativeSignal(
        signal: signal.future,
        superseded: () => false,
        changes: [changes.stream],
        timeout: const Duration(seconds: 1),
      );
      signal.completeError(failure);
      await expectLater(waiting, throwsA(same(failure)));
      expect(changes.hasListener, false);
      await changes.close();
    },
  );

  test('waits for a later native state update', () async {
    final changes = StreamController<Object?>.broadcast(sync: true);
    var ready = false;
    final waiting = waitForNativeState(
      ready: () => ready,
      superseded: () => false,
      changes: [changes.stream],
      timeout: const Duration(seconds: 1),
    );
    ready = true;
    changes.add(null);
    await waiting;
    expect(changes.hasListener, isFalse);
    await changes.close();
  });

  test(
    'checks again after subscribing so a raced update is not lost',
    () async {
      final changes = StreamController<Object?>.broadcast(sync: true);
      var checks = 0;
      await waitForNativeState(
        ready: () => ++checks >= 2,
        superseded: () => false,
        changes: [changes.stream],
        timeout: const Duration(seconds: 1),
      );
      expect(checks, 2);
      expect(changes.hasListener, isFalse);
      await changes.close();
    },
  );

  test('new generation interrupts the native wait', () async {
    final changes = StreamController<Object?>.broadcast(sync: true);
    var superseded = false;
    final waiting = waitForNativeState(
      ready: () => false,
      superseded: () => superseded,
      changes: [changes.stream],
      timeout: const Duration(seconds: 1),
    );
    superseded = true;
    changes.add(null);
    await expectLater(waiting, throwsA(isA<SourceSuperseded>()));
    expect(changes.hasListener, isFalse);
    await changes.close();
  });

  test('timeout releases native subscriptions', () async {
    final changes = StreamController<Object?>.broadcast(sync: true);
    await expectLater(
      waitForNativeState(
        ready: () => false,
        superseded: () => false,
        changes: [changes.stream],
        timeout: const Duration(milliseconds: 20),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(changes.hasListener, isFalse);
    await changes.close();
  });
}
