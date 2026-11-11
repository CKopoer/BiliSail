import 'dart:convert';

import '../storage/credential_store.dart';

/// Separate secure slot: logout clears account credentials, not device identity.
final class WebDeviceStore {
  const WebDeviceStore(this.credentials);
  final CredentialStore credentials;

  Future<Map<String, String>?> load() async {
    final saved = await credentials.read();
    if (saved == null) return null;
    try {
      final root = jsonDecode(saved);
      if (root is! Map<String, Object?> || root['version'] != 1) return null;
      return {
        for (final key in ['buvid3', 'buvid4', 'b_nut'])
          if (root[key] case final String value) key: value,
      };
    } on FormatException {
      return null;
    }
  }

  Future<void> save(Map<String, String> device) => credentials.write(
    jsonEncode({
      'version': 1,
      for (final key in ['buvid3', 'buvid4', 'b_nut']) key: ?device[key],
    }),
  );
}
