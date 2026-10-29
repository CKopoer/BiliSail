import 'dart:async';

import 'package:bilisail/app/release_smoke.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/data/app_recommendation_identity_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

const runId = '0123456789abcdef0123456789abcdef';

ReleaseSmokeRequest request(String phase) =>
    ReleaseSmokeRequest.parse([ReleaseSmokeRequest.flag, phase, runId])
        as ReleaseSmokeRequest;

void main() {
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

  test('background smoke gets a first frame after window activation', () async {
    final frame = Completer<void>();
    var completed = false;
    unawaited(
      request('startup')
          .waitForFirstFrame(
            activate: () async => frame.complete(),
            rasterized: () => frame.future,
          )
          .then((_) => completed = true),
    );
    await Future<void>.delayed(Duration.zero);
    expect(completed, isTrue);
  });

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
