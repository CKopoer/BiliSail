import 'dart:convert';

import 'package:bilisail/core/network/web_device_store.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('secure device slot persists only device fields', () async {
    final credentials = _Credentials();
    final store = WebDeviceStore(credentials);
    await store.save({
      'buvid3': 'three',
      'buvid4': 'four',
      'SESSDATA': 'secret',
    });
    expect(jsonDecode(credentials.value!), {
      'version': 1,
      'buvid3': 'three',
      'buvid4': 'four',
    });
    expect(await store.load(), {'buvid3': 'three', 'buvid4': 'four'});
  });

  test(
    'missing or invalid saved identity can be obtained from server',
    () async {
      final credentials = _Credentials();
      final store = WebDeviceStore(credentials);
      for (final value in [null, '{', '{"version":2}', '[]']) {
        credentials.value = value;
        expect(await store.load(), isNull);
      }
    },
  );

  test(
    'secure storage failure propagates without plaintext fallback',
    () async {
      final credentials = _Credentials()..fail = true;
      final store = WebDeviceStore(credentials);
      await expectLater(store.save({'buvid3': 'three'}), throwsStateError);
      expect(credentials.value, isNull);
    },
  );
}

class _Credentials implements CredentialStore {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String saved) async {
    if (fail) throw StateError('secure store unavailable');
    value = saved;
  }

  @override
  Future<void> delete() async => value = null;
}
