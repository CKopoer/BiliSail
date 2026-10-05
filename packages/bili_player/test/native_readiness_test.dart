import 'dart:async';

import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
