import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 10, 5);
  test('cookie domain, path, secure, expiry and restore', () {
    final jar = ApiCookieJar();
    jar.receive(Uri.https('passport.bilibili.com', '/x/login'), [
      'SESSDATA=abc; Domain=.bilibili.com; Path=/x; Secure; Max-Age=60',
      'host=one; Path=/x/login; Secure',
      'bad=no; Domain=example.com; Path=/',
    ], now: now);
    expect(
      jar.headerFor(Uri.https('api.bilibili.com', '/x/y'), now: now),
      'SESSDATA=abc',
    );
    expect(
      jar.headerFor(Uri.https('passport.bilibili.com', '/x/login/y'), now: now),
      'host=one; SESSDATA=abc',
    );
    expect(
      jar.headerFor(Uri.http('api.bilibili.com', '/x/y'), now: now),
      isNull,
    );
    final restored = ApiCookieJar()
      ..restoreFromSecureStorage(jar.exportForSecureStorage(), now: now);
    expect(
      restored.headerFor(Uri.https('api.bilibili.com', '/x/y'), now: now),
      'SESSDATA=abc',
    );
    expect(
      restored.headerFor(Uri.https('api.bilibili.com', '/x/login'), now: now),
      'SESSDATA=abc',
    );
    expect(
      restored.headerFor(
        Uri.https('api.bilibili.com', '/x/y'),
        now: now.add(const Duration(minutes: 2)),
      ),
      isNull,
    );
  });
}
