import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../core/storage/credential_store.dart';

/// An explicit macOS packaging probe in the shipped application, never enabled
/// by normal launches. Only synthetic values under a fresh random prefix change.
class ReleaseSmokeRequest {
  const ReleaseSmokeRequest._(this.phase, this.runId);

  static const flag = '--bilisail-release-smoke';
  static const phases = {
    'startup',
    'write',
    'read-delete',
    'verify-deleted',
    'cleanup',
  };

  final String phase;
  final String runId;
  String get prefix => 'bilisail.release_smoke.v1.$runId';
  String get successMarker => 'BILISAIL_RELEASE_SMOKE_OK:$phase:$runId';
  String get _value => 'BiliSail synthetic Keychain probe $runId';

  static ReleaseSmokeRequest? parse(List<String> arguments) {
    if (!arguments.contains(flag)) return null;
    if (arguments.length != 3 ||
        arguments.first != flag ||
        !phases.contains(arguments[1]) ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(arguments[2])) {
      throw const FormatException('Invalid release smoke request');
    }
    return ReleaseSmokeRequest._(arguments[1], arguments[2]);
  }

  Future<void> probeCredentials({FlutterSecureStorage? storage}) async {
    final secureStorage = storage ?? SystemCredentialStore.defaultStorage;
    final credentials = SystemCredentialStore(
      storage: secureStorage,
      keyPrefix: prefix,
    );
    switch (phase) {
      case 'startup':
        return;
      case 'write':
        await _expectDeleted(secureStorage);
        await credentials.write('$_value first');
        if (await credentials.read() != '$_value first') {
          throw StateError('Keychain write/read failed');
        }
        // Exercise both snapshot slots and the active-reference switch.
        await credentials.write(_value);
        if (await credentials.read() != _value) {
          throw StateError('Keychain snapshot switch failed');
        }
      case 'read-delete':
        if (await credentials.read() != _value) {
          throw StateError('Keychain read after restart failed');
        }
        await credentials.delete();
        await _expectDeleted(secureStorage);
      case 'verify-deleted':
        await _expectDeleted(secureStorage);
      case 'cleanup':
        await credentials.delete();
        await _expectDeleted(secureStorage);
    }
  }

  Future<void> _expectDeleted(FlutterSecureStorage storage) async {
    for (final suffix in ['active', 'a', 'b']) {
      if (await storage.read(key: '$prefix.$suffix') != null) {
        throw StateError('Keychain probe slot still exists');
      }
    }
  }
}
