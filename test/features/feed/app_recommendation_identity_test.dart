import 'dart:async';
import 'dart:convert';

import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/auth/domain/app_session_credentials.dart';
import 'package:bilisail/features/feed/data/app_recommendation_identity_store.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late _Secure secure;
  late _Session session;
  late AppRecommendationIdentityStore store;
  late StreamController<AuthState> changes;
  late String scope;
  final now = DateTime.utc(2026, 10, 28);
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.writeSetting(
      'app-recommendation-device.v1',
      'fixture_device_0123456789',
    );
    secure = _Secure();
    session = _Session();
    scope = 'user:42';
    changes = StreamController.broadcast(sync: true);
    store = AppRecommendationIdentityStore(
      database: database,
      credentials: secure,
      accountScope: () => scope,
      accountChanges: changes.stream,
      sessionCredentials: session,
      clock: () => now,
    );
  });
  tearDown(() async {
    await store.close();
    await changes.close();
    await database.close();
  });
  AppSessionCredentials token({bool invalid = false}) => AppSessionCredentials(
    mid: '42',
    accessToken: 'fixture-unified',
    expiresAt: now.add(const Duration(days: 1)),
    buvid: 'fixture_device_0123456789',
    invalid: invalid,
  );
  test(
    'device load is single flight and never writes token to SQLite',
    () async {
      session.value = token();
      final values = await Future.wait(
        List.generate(5, (_) => store.deviceId()),
      );
      expect(values.toSet(), {'fixture_device_0123456789'});
      expect(secure.reads, 0);
      expect((await store.requestIdentity()).accessToken, 'fixture-unified');
      expect((await store.requestIdentity()).accountMid, '42');
      expect(session.invalidated, 0);
      final rows = await database
          .customSelect('SELECT value FROM settings')
          .get();
      expect(
        rows.any(
          (row) => row.read<String>('value').contains('fixture-unified'),
        ),
        isFalse,
      );
    },
  );
  for (final saved in <String?>[null, 'invalid']) {
    test(
      'missing or invalid device uses the App format and survives reload: $saved',
      () async {
        if (saved == null) {
          await database.customStatement('DELETE FROM settings WHERE key = ?', [
            'app-recommendation-device.v1',
          ]);
        } else {
          await database.writeSetting('app-recommendation-device.v1', saved);
        }
        final devices = await Future.wait(
          List.generate(5, (_) => store.deviceId()),
        );
        final device = devices.first;
        expect(devices.toSet(), {device});
        expect(device, matches(r'^XY[0-9A-F]{35}$'));
        final body = device.substring(5);
        expect(device.substring(2, 5), '${body[2]}${body[12]}${body[22]}');
        expect(
          await database.readSetting('app-recommendation-device.v1'),
          device,
        );
        expect(secure.reads, 0);
        await store.close();
        store = AppRecommendationIdentityStore(
          database: database,
          credentials: secure,
          accountScope: () => scope,
          accountChanges: changes.stream,
          sessionCredentials: session,
          clock: () => now,
        );
        expect(await store.deviceId(), device);
        expect(session.invalidated, 0);
      },
    );
  }
  test(
    'unified session overrides legacy token and invalidity never falls back',
    () async {
      secure.value = jsonEncode({
        'mid': '42',
        'accessToken': 'fixture-legacy',
        'expiresAtMillis': now
            .add(const Duration(days: 1))
            .millisecondsSinceEpoch,
      });
      expect((await store.requestIdentity()).accessToken, 'fixture-legacy');
      session.value = token();
      expect((await store.requestIdentity()).accessToken, 'fixture-unified');
      session.value = token(invalid: true);
      await expectLater(store.requestIdentity(), throwsA(isA<AppFailure>()));
    },
  );
  test('legacy token loaded during Web restoration stays hidden until the matching account returns', () async {
    scope = 'guest';
    secure.value = jsonEncode({
      'mid': '42',
      'accessToken': 'fixture-legacy',
      'expiresAtMillis': now
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
    });
    expect((await store.requestIdentity()).accessToken, isNull);
    expect((await store.requestIdentity()).accountMid, isNull);
    scope = 'user:42';
    changes.add(const AuthState(status: AuthStatus.signedIn, mid: '42'));
    expect((await store.requestIdentity()).accessToken, 'fixture-legacy');
  });
  test(
    'device changes invalidate the session token and preserve Web account',
    () async {
      session.value = token();
      await store.setBuvid('new_device_0123456789');
      expect(session.invalidated, 1);
      expect(scope, 'user:42');
      await expectLater(store.requestIdentity(), throwsA(isA<AppFailure>()));
      expect(
        await database.readSetting('app-recommendation-device.v1'),
        'new_device_0123456789',
      );
      await expectLater(store.setBuvid('bad'), throwsArgumentError);
    },
  );
  test(
    'logout immediately isolates credentials and revokes legacy slot',
    () async {
      session.value = token();
      await store.load();
      scope = 'guest';
      changes.add(const AuthState());
      expect((await store.requestIdentity()).accessToken, isNull);
      await store.close();
      expect(
        await database.readSetting(
          'app-recommendation-authorization-revoked.v1',
        ),
        'true',
      );
      // close is idempotent for the teardown below.
    },
  );
  test(
    'legacy deletion failure cannot prevent a valid unified session being used',
    () async {
      session.value = token();
      secure.failDelete = true;
      changes.add(const AuthState(status: AuthStatus.signedIn, mid: '42'));
      await Future<void>.delayed(Duration.zero);
      expect((await store.requestIdentity()).accessToken, 'fixture-unified');
    },
  );
  test('server rejection invalidates the shared credentials owner', () async {
    session.value = token();
    await store.invalidateAuthorization();
    expect(session.invalidated, 1);
    await expectLater(store.requestIdentity(), throwsA(isA<AppFailure>()));
  });
}

final class _Session implements AppSessionCredentialsPort {
  AppSessionCredentials? value;
  int invalidated = 0;
  @override
  AppSessionCredentials? get appCredentials => value;
  @override
  Future<void> invalidateAppCredentials(AppSessionCredentials expected) async {
    invalidated++;
    value = AppSessionCredentials(
      mid: expected.mid,
      accessToken: expected.accessToken,
      expiresAt: expected.expiresAt,
      buvid: expected.buvid,
      invalid: true,
    );
  }
}

final class _Secure implements CredentialStore {
  String? value;
  int reads = 0;
  bool failDelete = false;
  @override
  Future<String?> read() async {
    reads++;
    return value;
  }

  @override
  Future<void> write(String value) async {
    this.value = value;
  }

  @override
  Future<void> delete() async {
    if (failDelete) throw StateError('fixture delete failed');
    value = null;
  }
}
