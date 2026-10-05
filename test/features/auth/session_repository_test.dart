import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/features/auth/data/session_repository.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

final class _FakeTransport implements ApiTransport {
  _FakeTransport(this.handler);
  final Future<ApiHttpResponse> Function(Uri) handler;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => handler(uri);
}

final class _FakeCredentials implements CredentialStore {
  _FakeCredentials(this.value);
  String? value;
  int deletes = 0;
  bool failWrite = false;
  Completer<void>? writeStarted;
  Completer<void>? writeGate;

  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String next) async {
    writeStarted?.complete();
    if (writeGate != null) await writeGate!.future;
    if (failWrite) throw StateError('secure write failed');
    value = next;
  }

  @override
  Future<void> delete() async {
    value = null;
    deletes++;
  }
}

ApiHttpResponse _jsonResponse(
  Object data, {
  Map<String, List<String>> headers = const {},
}) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode(data))),
  headers,
);

String _savedSession() {
  final jar = ApiCookieJar()
    ..receive(Uri.https('passport.bilibili.com', '/'), [
      'SESSDATA=fake; Domain=.bilibili.com; Path=/; Secure',
    ]);
  return jsonEncode({
    'version': 1,
    'mid': '123',
    'name': 'Known user',
    'cookies': jar.exportForSecureStorage(),
  });
}

_FakeTransport _qrTransport() => _FakeTransport((uri) async {
  if (uri.path.endsWith('/generate')) {
    return _jsonResponse({
      'code': 0,
      'data': {
        'url': 'https://passport.bilibili.com/qr',
        'qrcode_key': 'fake-key',
      },
    });
  }
  if (uri.path.endsWith('/poll')) {
    return _jsonResponse(
      {
        'code': 0,
        'data': {'code': 0},
      },
      headers: {
        'set-cookie': ['SESSDATA=fake; Domain=.bilibili.com; Path=/; Secure'],
      },
    );
  }
  return _jsonResponse({
    'code': 0,
    'data': {'isLogin': true, 'mid': 123, 'uname': 'Known user'},
  });
});

void main() {
  test('restore clears explicitly rejected authentication', () async {
    final requests = ApiRequests();
    final credentials = _FakeCredentials(_savedSession());
    final api = BiliApiClient(
      sessionProvider: requests,
      transport: _FakeTransport(
        (_) async => ApiHttpResponse(401, Uint8List(0), const {}),
      ),
    );
    final cleanedScopes = <String>[];
    final repository = SessionRepository(
      api: api,
      requests: requests,
      credentials: credentials,
      onSessionChanged: (scope) async {
        cleanedScopes.add(scope);
      },
    );
    await repository.restore();
    expect(repository.current.status, AuthStatus.guest);
    expect(credentials.value, isNull);
    expect(credentials.deletes, 1);
    expect(cleanedScopes, ['user:123']);
    expect(api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')), isNull);
    await repository.dispose();
  });

  test(
    'restore retains encrypted offline session for network failure',
    () async {
      final requests = ApiRequests();
      final credentials = _FakeCredentials(_savedSession());
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _FakeTransport(
          (_) async =>
              throw const ApiFailure(ApiFailureCategory.network, 'fake'),
        ),
      );
      final repository = SessionRepository(
        api: api,
        requests: requests,
        credentials: credentials,
        onSessionChanged: (_) async {},
      );
      await repository.restore();
      expect(repository.current.status, AuthStatus.signedIn);
      expect(repository.accountScope, 'user:123');
      expect(credentials.deletes, 0);
      await repository.dispose();
    },
  );

  test('unexpected nav HTTP response does not claim offline sign-in', () async {
    final requests = ApiRequests();
    final credentials = _FakeCredentials(_savedSession());
    final api = BiliApiClient(
      sessionProvider: requests,
      transport: _FakeTransport(
        (_) async => ApiHttpResponse(302, Uint8List(0), const {}),
      ),
    );
    final repository = SessionRepository(
      api: api,
      requests: requests,
      credentials: credentials,
      onSessionChanged: (_) async {},
    );
    await repository.restore();
    expect(repository.current.status, AuthStatus.guest);
    expect(credentials.value, isNotNull);
    expect(api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')), isNull);
    await repository.dispose();
  });

  test('QR secure-store failure never promotes main session', () async {
    final requests = ApiRequests();
    final credentials = _FakeCredentials(null)..failWrite = true;
    final api = BiliApiClient(
      sessionProvider: requests,
      transport: _FakeTransport(
        (_) async => throw StateError('main API must not be used during QR'),
      ),
    );
    final repository = SessionRepository(
      api: api,
      requests: requests,
      credentials: credentials,
      onSessionChanged: (_) async {},
      loginClientFactory: () => BiliApiClient(transport: _qrTransport()),
      pollInterval: Duration.zero,
    );
    await repository.signIn();
    expect(repository.current.status, AuthStatus.failed);
    expect(repository.accountScope, 'guest');
    expect(api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')), isNull);
    await repository.dispose();
  });

  test(
    'sign out during secure write cancels QR promotion and clears secret',
    () async {
      final requests = ApiRequests();
      final credentials = _FakeCredentials(null)
        ..writeStarted = Completer<void>()
        ..writeGate = Completer<void>();
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _FakeTransport(
          (_) async => throw StateError('main API must not be used during QR'),
        ),
      );
      var cleanupCalls = 0;
      final repository = SessionRepository(
        api: api,
        requests: requests,
        credentials: credentials,
        onSessionChanged: (_) async {
          cleanupCalls++;
        },
        loginClientFactory: () => BiliApiClient(transport: _qrTransport()),
        pollInterval: Duration.zero,
      );
      final login = repository.signIn();
      await credentials.writeStarted!.future;
      final logout = repository.signOut();
      credentials.writeGate!.complete();
      await Future.wait([login, logout]);
      expect(repository.current.status, AuthStatus.guest);
      expect(repository.accountScope, 'guest');
      expect(credentials.value, isNull);
      expect(cleanupCalls, 1);
      expect(
        api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')),
        isNull,
      );
      await repository.dispose();
    },
  );

  test('QR cleanup failure removes newly saved credentials', () async {
    final requests = ApiRequests();
    final credentials = _FakeCredentials(null);
    final api = BiliApiClient(
      sessionProvider: requests,
      transport: _FakeTransport(
        (_) async => throw StateError('main API must not be used during QR'),
      ),
    );
    final repository = SessionRepository(
      api: api,
      requests: requests,
      credentials: credentials,
      onSessionChanged: (_) async {
        throw StateError('player cleanup failed');
      },
      loginClientFactory: () => BiliApiClient(transport: _qrTransport()),
      pollInterval: Duration.zero,
    );
    await repository.signIn();
    expect(repository.current.status, AuthStatus.failed);
    expect(repository.accountScope, 'guest');
    expect(credentials.value, isNull);
    expect(credentials.deletes, 1);
    expect(api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')), isNull);
    await repository.dispose();
  });

  test(
    'sign out still deletes credentials if cleanup callback fails',
    () async {
      final requests = ApiRequests();
      final credentials = _FakeCredentials(_savedSession());
      final api = BiliApiClient(
        sessionProvider: requests,
        transport: _FakeTransport(
          (_) async => _jsonResponse({
            'code': 0,
            'data': {'isLogin': true, 'mid': 123, 'uname': 'Known user'},
          }),
        ),
      );
      var cleanupAttempted = false;
      final repository = SessionRepository(
        api: api,
        requests: requests,
        credentials: credentials,
        onSessionChanged: (_) async {
          cleanupAttempted = true;
          throw StateError('player cleanup failed');
        },
      );
      await repository.restore();
      await repository.signOut();
      expect(cleanupAttempted, isTrue);
      expect(repository.current.status, AuthStatus.guest);
      expect(credentials.value, isNull);
      expect(credentials.deletes, 1);
      await repository.dispose();
    },
  );
}
