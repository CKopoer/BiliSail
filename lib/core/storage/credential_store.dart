import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class CredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

/// Writes a complete encrypted slot before switching the active reference.
/// An explicit signed-out marker prevents orphan slots from restoring a login.
class SystemCredentialStore implements CredentialStore {
  SystemCredentialStore({
    FlutterSecureStorage? storage,
    String keyPrefix = 'bili_lite.web_session.v1',
  }) : _storage = storage ?? const FlutterSecureStorage(),
       _prefix = keyPrefix;

  final FlutterSecureStorage _storage;
  final String _prefix;

  @override
  Future<String?> read() async {
    final reference = await _storage.read(key: '$_prefix.active');
    if (reference != 'a' && reference != 'b') return null;
    final current = await _storage.read(key: '$_prefix.$reference');
    if (current != null) return current;
    return _storage.read(key: '$_prefix.${reference == 'a' ? 'b' : 'a'}');
  }

  @override
  Future<void> write(String value) async {
    final reference = await _storage.read(key: '$_prefix.active');
    final slot = reference == 'a' ? 'b' : 'a';
    await _storage.write(key: '$_prefix.$slot', value: value);
    await _storage.write(key: '$_prefix.active', value: slot);
  }

  @override
  Future<void> delete() async {
    await _storage.write(key: '$_prefix.active', value: 'signed_out');
    await _storage.delete(key: '$_prefix.a');
    await _storage.delete(key: '$_prefix.b');
    await _storage.delete(key: '$_prefix.active');
  }
}
