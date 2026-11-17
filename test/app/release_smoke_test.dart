import 'dart:async';
import 'dart:ui' show ViewFocusDirection, ViewFocusEvent, ViewFocusState;

import 'package:bilisail/app/release_smoke.dart';
import 'package:bilisail/core/presentation/window_input_focus.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/data/app_recommendation_identity_store.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const runId = '0123456789abcdef0123456789abcdef';

ReleaseSmokeRequest request(String phase) =>
    ReleaseSmokeRequest.parse([ReleaseSmokeRequest.flag, phase, runId])
        as ReleaseSmokeRequest;

void main() {
  for (final initiallyFocused in [true, false]) {
    testWidgets(
      'playback smoke observes first-frame focus without activation: $initiallyFocused',
      (tester) async {
        const channel = MethodChannel('bilisail/application_window');
        final calls = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call.method);
            return {'viewId': initiallyFocused ? 200 : 100, 'revision': 1};
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final focus = WindowInputFocus();
        var completed = false;
        final pending = waitForReleaseSmokeWindowFocus(
          200,
          focus: focus,
        ).then((_) => completed = true);
        await tester.idle();
        expect(completed, initiallyFocused);
        if (!initiallyFocused) {
          // The native window becomes key only after its content is rendered.
          await tester.pump(const Duration(milliseconds: 200));
          expect(completed, isFalse);
          focus.didChangeViewFocus(
            const ViewFocusEvent(
              viewId: 200,
              state: ViewFocusState.focused,
              direction: ViewFocusDirection.undefined,
            ),
          );
        }
        await pending;
        expect(completed, isTrue);
        expect(calls, ['getWindowFocus']);
      },
    );
  }

  for (final replies in [true, false]) {
    testWidgets('missing playback focus fails within its budget: $replies', (
      tester,
    ) async {
      const channel = MethodChannel('bilisail/application_window');
      final snapshot = Completer<Map<String, Object?>>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) => snapshot.future,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      final focus = WindowInputFocus(
        nativeSnapshotTimeout: releaseSmokeFocusTimeout,
      );
      final pending = expectLater(
        waitForReleaseSmokeWindowFocus(200, focus: focus),
        throwsA(isA<TimeoutException>()),
      );
      if (replies) snapshot.complete({'viewId': 100, 'revision': 1});
      await tester.pump(releaseSmokeFocusTimeout);
      await pending;
      if (!replies) snapshot.complete({'viewId': 200, 'revision': 2});
      await tester.idle();
      // Remove the observer and invalidate late snapshots when the probe ends.
      expect(focus.observed, isFalse);
    });
  }

  for (final responds in [true, false]) {
    testWidgets('smoke focus uses its bounded probe budget: $responds', (
      tester,
    ) async {
      const channel = MethodChannel('bilisail/application_window');
      final focus = WindowInputFocus(
        nativeSnapshotTimeout: releaseSmokeFocusTimeout,
      );
      final reply = Completer<Map<String, Object?>>();
      var reads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        _,
      ) {
        reads++;
        return reply.future;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      var completed = false;
      final pending = focus.synchronizeNativeFocus().then(
        (_) => completed = true,
      );
      final result = responds
          ? expectLater(pending, completes)
          : expectLater(pending, throwsA(isA<TimeoutException>()));
      // Reproduce the failed runner's delayed native reply with virtual time.
      await tester.pump(const Duration(seconds: 16));
      expect(completed, isFalse);
      expect(focus.observed, isFalse);
      if (responds) {
        reply.complete({'viewId': 100, 'revision': 1});
        await tester.pump();
        await result;
        expect(completed, isTrue);
        expect(focus.viewId, 100);
        expect(focus.source, 'native');
      } else {
        await tester.pump(const Duration(seconds: 44));
        await result;
        reply.complete({'viewId': 100, 'revision': 1});
        await tester.pump();
        expect(completed, isFalse);
        expect(focus.observed, isFalse);
      }
      expect(reads, 1);
    });
  }

  test('smoke failure categories never include exception data', () {
    const sensitive = 'private https://example.invalid/?token=private';
    for (final (error, kind) in <(Object, String)>[
      (TimeoutException(sensitive), 'timeout'),
      (PlatformException(code: sensitive, message: sensitive), 'platform'),
      (StateError(sensitive), 'state'),
      (const FormatException(sensitive), 'format'),
      (Exception(sensitive), 'other'),
    ]) {
      expect(
        releaseSmokeErrorMarker(error),
        'BILISAIL_RELEASE_SMOKE_ERROR:$kind',
      );
    }
  });

  test(
    'startup guest cleanup keeps both production credential stores intact',
    () async {
      final storage = MemorySecureStorage();
      await SystemCredentialStore(storage: storage)
          .write('private web session');
      await SystemCredentialStore(
        storage: storage,
        keyPrefix: 'bilisail.app_recommendation.v1',
      ).write('private legacy app session');
      final before = Map<String, String>.of(storage.values);
      final smoke = request('startup');
      expect(await smoke.bootstrapCredentials(storage: storage).read(), isNull);

      final database = AppDatabase(NativeDatabase.memory());
      final changes = StreamController<AuthState>.broadcast(sync: true);
      final identity = AppRecommendationIdentityStore(
        database: database,
        credentials: smoke.recommendationCredentials(storage: storage),
        accountScope: () => 'guest',
        accountChanges: changes.stream,
      );
      try {
        changes.add(const AuthState());
        // close drains the actual guest-triggered legacy deletion queue.
        await identity.close();
        expect(storage.values, before);
      } finally {
        await changes.close();
        await database.close();
      }
    },
  );

  testWidgets(
    'a hung credential write times out without replay or later steps',
    (tester) async {
      final gate = Completer<void>();
      final storage = MemorySecureStorage(writeGate: gate.future);
      final stages = <ReleaseCredentialStep>[];
      final result = expectLater(
        request('write').probeCredentials(storage: storage, onStep: stages.add),
        throwsA(isA<TimeoutException>()),
      );
      await tester.pump();
      expect(stages.last, ReleaseCredentialStep.writeFirst);
      await tester.pump(const Duration(seconds: 10));
      await result;
      expect(storage.writes, hasLength(1));
      expect(stages.last, ReleaseCredentialStep.writeFirst);
    },
  );

  for (final state in [AppLifecycleState.resumed, AppLifecycleState.inactive]) {
    testWidgets('startup requires a normal frame after rasterization: $state', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(state);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final rasterized = Completer<void>();
      var completed = false;
      final pending = request('startup')
          .waitForFirstFrame(rasterized: () => rasterized.future)
          .then((_) => completed = true);
      await tester.idle();
      expect(completed, isFalse);
      rasterized.complete();
      await tester.idle();
      expect(completed, isFalse);
      await tester.pump();
      await pending;
      expect(completed, isTrue);
    });
  }

  for (final state in [AppLifecycleState.resumed, AppLifecycleState.inactive]) {
    testWidgets(
      'startup waits for native visibility after rasterization: $state',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        var completed = false;
        final pending = request('startup')
            .waitForFirstFrame(rasterized: () async {})
            .then((_) => completed = true);
        await tester.idle();
        await tester.pump(const Duration(milliseconds: 100));
        expect(completed, isFalse);
        expect(tester.binding.framesEnabled, isFalse);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        if (state == AppLifecycleState.resumed) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await tester.idle();
        expect(completed, isFalse);
        await tester.pump();
        await pending;
        expect(completed, isTrue);
        expect(tester.binding.lifecycleState, state);
      },
    );
  }

  for (final state in [
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.detached,
  ]) {
    testWidgets('a rasterized warm-up cannot hide disabled frames: $state', (
      tester,
    ) async {
      tester.binding.handleAppLifecycleStateChanged(state);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );
      final pending = expectLater(
        request('startup').waitForFirstFrame(rasterized: () async {}),
        throwsA(isA<TimeoutException>()),
      );
      await tester.idle();
      await tester.pump(const Duration(seconds: 5));
      await pending;
      expect(tester.binding.lifecycleState, state);
      expect(tester.binding.framesEnabled, isFalse);
    });
  }

  test(
    'macOS uses system Keychain without provisioning; other defaults stay',
    () {
      final storage = SystemCredentialStore.defaultStorage;
      expect(storage.mOptions.toMap()['usesDataProtectionKeychain'], 'false');
      expect(storage.mOptions.groupId, isNull);
      expect(storage.aOptions.toMap(), const AndroidOptions().toMap());
      expect(storage.iOptions.toMap(), const IOSOptions().toMap());
      expect(storage.wOptions.toMap(), const WindowsOptions().toMap());
    },
  );

  test('normal launch is inert and malformed probe arguments are rejected', () {
    expect(ReleaseSmokeRequest.parse([]), isNull);
    expect(ReleaseSmokeRequest.parse(['--normal']), isNull);
    for (final arguments in [
      [ReleaseSmokeRequest.flag],
      [ReleaseSmokeRequest.flag, 'delete-all', runId],
      [ReleaseSmokeRequest.flag, 'write', 'bilisail.web_session.v1'],
      [ReleaseSmokeRequest.flag, 'write', runId, '--extra'],
      ['--other', ReleaseSmokeRequest.flag, 'write', runId],
    ]) {
      expect(() => ReleaseSmokeRequest.parse(arguments), throwsFormatException);
    }
  });

  test(
    'new process reads saved snapshot and deletes both slots; user survives',
    () async {
      final storage = MemorySecureStorage();
      final user = SystemCredentialStore(storage: storage);
      await user.write('private user session');
      final before = Map<String, String>.of(storage.values);
      await request('startup').probeCredentials(storage: storage);
      expect(storage.values, before);
      await request('write').probeCredentials(storage: storage);
      expect(storage.values.keys, contains('${request('write').prefix}.a'));
      expect(storage.values.keys, contains('${request('write').prefix}.b'));
      // Each request constructs a fresh credential store, just like a restart.
      await request('read-delete').probeCredentials(storage: storage);
      await request('verify-deleted').probeCredentials(storage: storage);
      expect(storage.values, before);
      expect(await user.read(), 'private user session');
    },
  );

  test(
    'silent writes and missing persisted snapshots fail the probe',
    () async {
      await expectLater(
        request('write')
            .probeCredentials(storage: MemorySecureStorage(dropWrites: true)),
        throwsStateError,
      );
      await expectLater(
        request('read-delete').probeCredentials(storage: MemorySecureStorage()),
        throwsStateError,
      );
    },
  );

  test(
    'orphan slots fail deletion check even when active reference is absent',
    () async {
      final storage = MemorySecureStorage();
      storage.values['${request('verify-deleted').prefix}.b'] = 'orphan';
      await expectLater(
        request('verify-deleted').probeCredentials(storage: storage),
        throwsStateError,
      );
      await request('cleanup').probeCredentials(storage: storage);
      expect(storage.values, isEmpty);
    },
  );

  test('cleanup only removes its isolated prefix', () async {
    final storage = MemorySecureStorage();
    await request('write').probeCredentials(storage: storage);
    await request('startup')
        .bootstrapCredentials(storage: storage)
        .write('bootstrap');
    await request('startup')
        .recommendationCredentials(storage: storage)
        .write('legacy');
    storage.values['bilisail.web_session.v1.active'] = 'a';
    storage.values['another.probe.b'] = 'keep';
    await request('cleanup').probeCredentials(storage: storage);
    expect(storage.values, {
      'bilisail.web_session.v1.active': 'a',
      'another.probe.b': 'keep',
    });
  });
}

class MemorySecureStorage extends FlutterSecureStorage {
  MemorySecureStorage({this.dropWrites = false, this.writeGate});
  final bool dropWrites;
  final Future<void>? writeGate;
  final writes = <String>[];
  final values = <String, String>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    writes.add(key);
    await writeGate;
    if (dropWrites) return;
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}
