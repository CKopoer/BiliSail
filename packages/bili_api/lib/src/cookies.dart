import 'dart:io';

final class ApiCookieJar {
  final List<_StoredCookie> _cookies = [];

  void clear() => _cookies.clear();

  /// Serialize only into a platform credential store, never ordinary settings.
  Map<String, Object?> exportForSecureStorage() => {
    'version': 1,
    'cookies':
        _cookies
            .map(
              (entry) => <String, Object?>{
                'name': entry.cookie.name,
                'value': entry.cookie.value,
                'domain': entry.domain,
                'path': entry.path,
                'hostOnly': entry.hostOnly,
                'secure': entry.secure,
                'expiresUtc': entry.expiry?.toUtc().toIso8601String(),
              },
            )
            .toList(),
  };

  void restoreFromSecureStorage(
    Map<String, Object?> snapshot, {
    DateTime? now,
  }) {
    if (snapshot['version'] != 1 || snapshot['cookies'] is! List) {
      throw const FormatException('Unsupported cookie snapshot');
    }
    final clock = now ?? DateTime.now().toUtc();
    final restored = <_StoredCookie>[];
    for (final raw in snapshot['cookies'] as List) {
      if (raw is! Map<String, Object?>) {
        throw const FormatException('Invalid cookie');
      }
      final name = raw['name'], value = raw['value'], domain = raw['domain'];
      final path = raw['path'],
          hostOnly = raw['hostOnly'],
          secure = raw['secure'];
      if (name is! String ||
          name.isEmpty ||
          value is! String ||
          domain is! String ||
          !_isBilibiliHost(domain) ||
          path is! String ||
          !path.startsWith('/') ||
          hostOnly is! bool ||
          secure is! bool) {
        throw const FormatException('Invalid cookie');
      }
      final expiryRaw = raw['expiresUtc'];
      if (expiryRaw != null && expiryRaw is! String) {
        throw const FormatException('Invalid cookie expiry');
      }
      final expiry =
          expiryRaw is String ? DateTime.tryParse(expiryRaw)?.toUtc() : null;
      if (expiryRaw != null && expiry == null) {
        throw const FormatException('Invalid cookie expiry');
      }
      if (expiry != null && !expiry.isAfter(clock)) continue;
      restored.add(
        _StoredCookie(
          Cookie(name, value),
          domain,
          path,
          hostOnly,
          secure,
          expiry,
        ),
      );
    }
    _cookies
      ..clear()
      ..addAll(restored);
  }

  void receive(Uri origin, Iterable<String> setCookieHeaders, {DateTime? now}) {
    if (origin.scheme != 'https' || !_isBilibiliHost(origin.host)) return;
    final clock = now ?? DateTime.now().toUtc();
    for (final line in setCookieHeaders) {
      Cookie cookie;
      try {
        cookie = Cookie.fromSetCookieValue(line);
      } on FormatException {
        continue;
      }
      final domain = (cookie.domain ?? origin.host).toLowerCase().replaceFirst(
        RegExp(r'^\.'),
        '',
      );
      final host = origin.host.toLowerCase();
      if (!_isBilibiliHost(domain) ||
          (host != domain && !host.endsWith('.$domain'))) {
        continue;
      }
      final path = cookie.path ?? _defaultPath(origin.path);
      final expiry =
          cookie.maxAge == null
              ? cookie.expires?.toUtc()
              : clock.add(Duration(seconds: cookie.maxAge!));
      _cookies.removeWhere(
        (entry) =>
            entry.cookie.name == cookie.name &&
            entry.domain == domain &&
            entry.path == path,
      );
      if (cookie.value.isEmpty || (expiry != null && !expiry.isAfter(clock))) {
        continue;
      }
      _cookies.add(
        _StoredCookie(
          cookie,
          domain,
          path,
          cookie.domain == null,
          cookie.secure,
          expiry,
        ),
      );
    }
  }

  String? headerFor(Uri target, {DateTime? now}) {
    if (target.scheme != 'https' || !_isBilibiliHost(target.host)) return null;
    final clock = now ?? DateTime.now().toUtc();
    _cookies.removeWhere(
      (entry) => entry.expiry != null && !entry.expiry!.isAfter(clock),
    );
    final matching =
        _cookies.where((entry) {
            final host = target.host.toLowerCase();
            final domainMatches =
                entry.hostOnly
                    ? host == entry.domain
                    : host == entry.domain || host.endsWith('.${entry.domain}');
            final pathMatches =
                target.path == entry.path ||
                target.path.startsWith(
                  entry.path.endsWith('/') ? entry.path : '${entry.path}/',
                );
            return domainMatches &&
                pathMatches &&
                (!entry.secure || target.scheme == 'https');
          }).toList()
          ..sort((a, b) => b.path.length.compareTo(a.path.length));
    if (matching.isEmpty) return null;
    return matching
        .map((entry) => '${entry.cookie.name}=${entry.cookie.value}')
        .join('; ');
  }

  static bool _isBilibiliHost(String host) =>
      host == 'bilibili.com' || host.endsWith('.bilibili.com');

  static String _defaultPath(String path) {
    final slash = path.lastIndexOf('/');
    return slash <= 0 ? '/' : path.substring(0, slash);
  }
}

final class _StoredCookie {
  const _StoredCookie(
    this.cookie,
    this.domain,
    this.path,
    this.hostOnly,
    this.secure,
    this.expiry,
  );
  final Cookie cookie;
  final String domain;
  final String path;
  final bool hostOnly;
  final bool secure;
  final DateTime? expiry;
}
