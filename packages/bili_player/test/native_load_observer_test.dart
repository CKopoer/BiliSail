import 'dart:async';

import 'package:bili_player/src/native_load_observer.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preparation failure interrupts readiness and is not revived', () async {
    final state = NativeLoadState();
    final waiting = waitForNativeState(
      ready: () => false,
      superseded: () => false,
      changes: [state.changes],
      timeout: const Duration(seconds: 6),
      failure: () => state.preparationFailed ? StateError('preparation') : null,
    );
    state.failPreparation();
    await expectLater(
      waiting.timeout(const Duration(milliseconds: 100)),
      throwsStateError,
    );
    await state.dispose();
    state.failPreparation();
    expect(state.preparationFailed, isTrue);
  });

  test('matching error end interrupts readiness before its deadline', () async {
    final state = NativeLoadState()..started(7);
    addTearDown(state.dispose);
    final waiting = waitForNativeState(
      ready: () => false,
      superseded: () => false,
      changes: [state.changes],
      timeout: const Duration(seconds: 6),
      failure: () => state.errorCode == null ? null : StateError('terminal'),
    );
    state.ended(entryId: 7, reason: 4, error: -13);
    await expectLater(
      waiting.timeout(const Duration(milliseconds: 100)),
      throwsA(isA<StateError>()),
    );
    expect(state.errorCode, -13);
  });

  for (final reason in [0, 2, 3, 5, 100]) {
    test('end reason $reason does not abort readiness', () async {
      final state = NativeLoadState()..started(7);
      addTearDown(state.dispose);
      var ready = false;
      final changes = StreamController<void>.broadcast(sync: true);
      addTearDown(changes.close);
      final waiting = waitForNativeState(
        ready: () => ready,
        superseded: () => false,
        changes: [state.changes, changes.stream],
        timeout: const Duration(seconds: 1),
        failure: () => state.errorCode,
      );
      expect(state.ended(entryId: 7, reason: reason, error: -13), false);
      ready = true;
      changes.add(null);
      await waiting;
      expect(state.errorCode, isNull);
    });
  }

  test('unknown, replaced and duplicate file ends are ignored', () async {
    final state = NativeLoadState();
    addTearDown(state.dispose);
    expect(state.ended(entryId: 7, reason: 4, error: -13), false);
    state.started(7);
    state.started(8);
    expect(state.ended(entryId: 7, reason: 4, error: -13), false);
    expect(state.ended(entryId: 8, reason: 4, error: 0), false);
    expect(state.ended(entryId: 8, reason: 4, error: -13), true);
    expect(state.ended(entryId: 8, reason: 4, error: -14), false);
    expect(state.errorCode, -13);
  });

  test('already received termination beats a ready predicate', () async {
    final state = NativeLoadState()..started(7);
    addTearDown(state.dispose);
    state.ended(entryId: 7, reason: 4, error: -13);
    await expectLater(
      waitForNativeState(
        ready: () => true,
        superseded: () => false,
        changes: [state.changes],
        timeout: const Duration(seconds: 1),
        failure: () => state.errorCode,
      ),
      throwsA(-13),
    );
  });

  test('superseding wins over a simultaneous terminal failure', () async {
    final state = NativeLoadState()..started(7);
    addTearDown(state.dispose);
    var superseded = false;
    final waiting = waitForNativeSignal(
      signal: Completer<void>().future,
      superseded: () => superseded,
      changes: [state.changes],
      timeout: const Duration(seconds: 1),
      failure: () => state.errorCode,
    );
    superseded = true;
    state.ended(entryId: 7, reason: 4, error: -13);
    await expectLater(waiting, throwsA(isA<SourceSuperseded>()));
  });

  test('late ends after disposal never revive the old failure', () async {
    final state = NativeLoadState()..started(7);
    await state.dispose();
    state.started(8);
    expect(state.ended(entryId: 7, reason: 4, error: -13), false);
    expect(state.ended(entryId: 8, reason: 4, error: -13), false);
    expect(state.errorCode, isNull);
  });
}
