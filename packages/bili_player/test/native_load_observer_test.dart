import 'dart:async';

import 'package:bili_player/src/native_load_observer.dart';
import 'package:bili_player/src/native_readiness.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paused track readiness belongs to the current load and seek', () async {
    final state = NativeLoadState();
    addTearDown(state.dispose);
    expect(state.tracksReady, false);
    state.started(1);
    expect(state.tracksReady, false);
    state.playbackRestarted();
    expect(state.tracksReady, true);
    state.seekStarted();
    expect(state.tracksReady, false);
    state.clockChanged(seconds: 20);
    expect(state.tracksReady, false);
    state.playbackRestarted();
    expect(state.tracksReady, true);
    state.started(2);
    expect(state.tracksReady, false);
  });
  test('replacement loads require their own playback restart', () async {
    final state = NativeLoadState();
    addTearDown(state.dispose);
    state.started(1);
    state.playbackRestarted();
    final previous = state.loadCount;
    state.started(2);
    expect(state.loadCount, greaterThan(previous));
    expect(state.restartedLoadCount, lessThan(state.loadCount));
    state.playbackRestarted();
    expect(state.restartedLoadCount, state.loadCount);
    await state.dispose();
    state.started(3);
    expect(state.loadCount, 2);
  });
  test('seek readiness requires a new seek and its playback restart', () async {
    final state = NativeLoadState();
    addTearDown(state.dispose);
    state.playbackRestarted();
    final before = state.seekCount;
    var ready = false;
    final waiting = waitForNativeState(
      ready: () =>
          state.seekCount > before &&
          state.restartedSeekCount == state.seekCount,
      superseded: () => false,
      changes: [state.changes],
      timeout: const Duration(seconds: 1),
    ).then((_) => ready = true);
    state.playbackRestarted();
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    state.seekStarted();
    state.clockChanged(seconds: 9);
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    state.playbackRestarted();
    await waiting;
    expect(ready, isTrue);
    state.seekStarted();
    expect(state.restartedSeekCount, lessThan(state.seekCount));
  });

  test(
    'seek restarts invalidate clocks and cannot cross source disposal',
    () async {
      final state = NativeLoadState();
      state.clockChanged(seconds: 1, epoch: 0);
      state.seekStarted();
      state.clockChanged(seconds: 1, epoch: 0);
      expect(state.audioPosition, isNull);
      state.playbackRestarted();
      await state.dispose();
      state.seekStarted();
      state.playbackRestarted();
      expect(state.seekCount, 1);
      expect(state.restartedSeekCount, 1);
      final replacement = NativeLoadState();
      addTearDown(replacement.dispose);
      expect(replacement.seekCount, 0);
      expect(replacement.restartedSeekCount, 0);
    },
  );

  test('output color confirmation can follow decoded dimensions', () async {
    final state = NativeLoadState();
    addTearDown(state.dispose);
    var ready = false;
    final waiting = waitForNativeState(
      ready: () => state.videoOutputMatrix == 'bt.709',
      superseded: () => false,
      changes: [state.changes],
      timeout: const Duration(seconds: 1),
    ).then((_) => ready = true);
    state.outputChanged(NativeOutputProperty.colorMatrix, 'dolbyvision');
    await Future<void>.delayed(Duration.zero);
    expect(ready, isFalse);
    state.outputChanged(NativeOutputProperty.colorMatrix, 'bt.709');
    await waiting;
    expect(ready, isTrue);
  });

  test(
    'source replacement and disposal cannot inherit output confirmation',
    () async {
      final old = NativeLoadState();
      old.outputChanged(NativeOutputProperty.driver, 'gpu-next');
      final next = NativeLoadState();
      addTearDown(next.dispose);
      expect(next.videoOutputDriver, isNull);
      expect(next.videoOutputMatrix, isNull);
      await old.dispose();
      old.outputChanged(NativeOutputProperty.driver, 'gpu');
      expect(old.videoOutputDriver, 'gpu-next');
    },
  );
  test('seek and pause invalidate pending clock replies', () async {
    final state = NativeLoadState();
    state.clockChanged(seconds: 10, epoch: 0);
    state.resetClocks();
    state.clockChanged(seconds: 10, epoch: 0);
    expect(state.audioPosition, isNull);
    state.clockChanged(seconds: 40, epoch: 1);
    expect(state.audioPosition, const Duration(seconds: 40));
    await state.dispose();
  });

  test(
    'clock cache validates native samples and ignores disposed replies',
    () async {
      final state = NativeLoadState();
      state.clockChanged(seconds: 12.25);
      expect(state.audioPosition, const Duration(milliseconds: 12250));
      for (final invalid in [null, double.nan, double.infinity, -0.1]) {
        state.clockChanged(seconds: invalid);
        expect(state.audioPosition, isNull);
      }
      state.clockChanged(seconds: 12.25);
      await state.dispose();
      state.clockChanged(seconds: 50);
      expect(state.audioPosition, const Duration(milliseconds: 12250));
    },
  );

  test(
    'preparation keeps the original failure and ignores late errors',
    () async {
      final state = NativeLoadState();
      final outputFailure = StateError('surface unavailable');
      state.failPreparation(error: outputFailure);
      state.failPreparation(error: StateError('late reply'));
      expect(state.preparationFailed, isTrue);
      expect(state.preparationError, same(outputFailure));
      await state.dispose();
      state.failPreparation(error: StateError('disposed'));
      expect(state.preparationError, same(outputFailure));
    },
  );

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
