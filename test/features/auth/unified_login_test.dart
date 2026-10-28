import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/core/storage/app_database.dart';
import 'package:bilisail/core/storage/credential_store.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/auth/data/session_repository.dart';
import 'package:bilisail/features/auth/domain/auth_repository.dart';
import 'package:bilisail/features/feed/data/app_recommendation_identity_store.dart';
import 'package:bilisail/features/feed/data/api_feed_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

const _device = 'fixture_device_0123456789';
void main() {
  late _Transport transport;
  late _Secure secure;
  late SessionRepository session;
  late AppDatabase database;
  late AppRecommendationIdentityStore identity;
  var appDeviceLoads = 0;
  setUp(() async {
    transport = _Transport();
    secure = _Secure();
    appDeviceLoads = 0;
    final requests = ApiRequests();
    database = AppDatabase(NativeDatabase.memory());
    await database.writeSetting('app-recommendation-device.v1', _device);
    session = SessionRepository(
      api: BiliApiClient(transport: transport, sessionProvider: requests),
      requests: requests,
      credentials: secure,
      onSessionChanged: (_) async {},
      loginClientFactory: () => BiliApiClient(transport: transport),
      loadAppDevice: () async {
        appDeviceLoads++;
        return _device;
      },
      pollInterval: Duration.zero,
    );
    identity = AppRecommendationIdentityStore(
      database: database,
      credentials: _Secure(),
      sessionCredentials: session,
      accountScope: () => session.accountScope,
      accountChanges: session.changes,
    );
  });
  tearDown(() async {
    await identity.close();
    await session.dispose();
    session.api.close();
    await database.close();
  });
  Future<void> oldSession() async {
    final jar = ApiCookieJar()
      ..receive(Uri.https('passport.bilibili.com', '/'), [
        'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
        'bili_jct=fixture-csrf; Domain=.bilibili.com; Path=/; Secure',
      ]);
    secure.value = jsonEncode({
      'version': 1,
      'mid': '42',
      'name': 'fixture',
      'cookies': jar.exportForSecureStorage(),
    });
    await session.restore();
  }

  test('one HD scan commits Cookie and token together and immediately enables App recommendation', () async {
    await session.signIn();
    expect(session.current.isSignedIn, isTrue);
    expect(session.current.appSessionAvailable, isTrue);
    expect((await identity.requestIdentity()).accessToken, 'fixture-app');
    expect(
      session.api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')),
      contains('SESSDATA=fixture'),
    );
    final snapshot = jsonDecode(secure.value!);
    expect(snapshot['version'], 2);
    expect(snapshot['app']['accessToken'], 'fixture-app');
    expect(snapshot['app']['refreshToken'], 'fixture-refresh');
    expect(transport.paths, [
      '/x/passport-tv-login/qrcode/auth_code',
      '/x/passport-tv-login/qrcode/poll',
      '/x/web-interface/nav',
    ]);
    expect(secure.writes, 1);
    final rows = await database
        .customSelect('SELECT value FROM settings')
        .get();
    expect(
      rows.any((row) => row.read<String>('value').contains('fixture-app')),
      isFalse,
    );
  });
  test('unified secure snapshot restores both identities', () async {
    await session.signIn();
    final saved = secure.value;
    await session.restore();
    expect(session.current.appSessionAvailable, isTrue);
    expect(session.appCredentials?.accessToken, 'fixture-app');
    expect(secure.value, saved);
  });
  test(
    'old Web session remains usable and does not obtain a token automatically',
    () async {
      await oldSession();
      final previous = secure.value;
      await session.signIn();
      expect(session.current.isSignedIn, isTrue);
      expect(session.current.appSessionAvailable, isFalse);
      expect(secure.value, previous);
      expect(transport.paths, ['/x/web-interface/nav']);
    },
  );
  test(
    'password or SMS Web login commits without App authorization requests',
    () async {
      await session.completeWebLogin(session.beginWebLogin()!, const [
        LoginCookie(
          name: 'SESSDATA',
          value: 'fixture',
          domain: 'bilibili.com',
          path: '/',
          hostOnly: false,
          secure: true,
        ),
      ]);
      expect(session.current.isSignedIn, isTrue);
      expect(session.current.appSessionAvailable, isFalse);
      expect(session.appCredentials, isNull);
      expect(secure.writes, 1);
      expect((await identity.requestIdentity()).accessToken, isNull);
      expect(jsonDecode(secure.value!).containsKey('app'), isFalse);
      expect(appDeviceLoads, 0);
      expect(transport.paths, ['/x/web-interface/nav']);
    },
  );
  test('nav mismatch rejects both new credentials before storing', () async {
    transport.navMid = 7;
    await session.signIn();
    expect(session.current.status, AuthStatus.failed);
    expect(secure.value, isNull);
    expect(session.appCredentials, isNull);
  });
  test('missing HD Cookies cannot become a token-only login', () async {
    transport.includeCookies = false;
    await session.signIn();
    expect(session.current.status, AuthStatus.failed);
    expect(secure.value, isNull);
    expect(transport.paths, hasLength(2));
  });
  Future<void> browserLogin() =>
      session.completeWebLogin(session.beginWebLogin()!, const [
        LoginCookie(
          name: 'SESSDATA',
          value: 'fixture',
          domain: 'bilibili.com',
          path: '/',
          hostOnly: false,
          secure: true,
        ),
        LoginCookie(
          name: 'bili_jct',
          value: 'fixture-csrf',
          domain: 'bilibili.com',
          path: '/',
          hostOnly: false,
          secure: true,
        ),
      ]);
  test('Web login restores without App credentials and can load guest App recommendations', () async {
    await browserLogin();
    final saved = secure.value;
    await session.restore();
    expect(session.current.isSignedIn, isTrue);
    expect(session.current.appSessionAvailable, isFalse);
    expect(secure.value, saved);
    final page = await ApiFeedRepository(
      session.api,
      session.requests,
      appIdentity: identity,
    ).loadAppRecommendations(page: 1, cancellation: RequestCancellation());
    expect(page.items.single.id.value, 'BV17x411w7KC');
    expect(transport.paths, [
      '/x/web-interface/nav',
      '/x/web-interface/nav',
      '/x/v2/feed/index',
    ]);
  });
  test('logout during paired secure write removes both credentials and rejects late promotion', () async {
    secure.gate = Completer<void>();
    final operation = session.signIn();
    await secure.started.future;
    final logout = session.signOut();
    secure.gate!.complete();
    await Future.wait([operation, logout]);
    expect(session.current.status, AuthStatus.guest);
    expect(secure.value, isNull);
    expect(session.appCredentials, isNull);
    expect((await identity.requestIdentity()).accessToken, isNull);
  });
  test(
    'partial secure write failure rolls back Cookie and App token together',
    () async {
      secure.failWrite = true;
      await session.signIn();
      expect(session.current.status, AuthStatus.failed);
      expect(secure.value, isNull);
      expect(session.appCredentials, isNull);
    },
  );
  test(
    'device mutation persists token invalidity without losing Web login',
    () async {
      await session.signIn();
      await identity.setBuvid('new_device_0123456789');
      expect(session.current.isSignedIn, isTrue);
      expect(session.current.appSessionAvailable, isFalse);
      expect(jsonDecode(secure.value!)['app']['invalid'], isTrue);
      await expectLater(identity.requestIdentity(), throwsA(isA<AppFailure>()));
      await session.restore();
      expect(session.current.appSessionAvailable, isFalse);
    },
  );
}

final class _Secure implements CredentialStore {
  String? value;
  bool failWrite = false;
  int writes = 0;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String value) async {
    writes++;
    if (!started.isCompleted) started.complete();
    await gate?.future;
    this.value = value;
    if (failWrite) throw StateError('fixture secure write failed');
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

final class _Transport implements ApiTransport, ApiFormTransport {
  final paths = <String>[];
  int navMid = 42, tokenMid = 42;
  bool includeCookies = true;
  ApiHttpResponse response(Object data, {int status = 200}) => ApiHttpResponse(
    status,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
    const {},
  );
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    paths.add(uri.path);
    if (uri.path == '/x/v2/feed/index') {
      expect(uri.host, 'app.bilibili.com');
      expect(headers.containsKey('Cookie'), isFalse);
      expect(uri.queryParameters.containsKey('access_key'), isFalse);
      return response({
        'items': [
          {
            'card_goto': 'av',
            'can_play': 1,
            'param': '170001',
            'title': 'Fixture recommendation',
          },
        ],
      });
    }
    expect(uri.host, 'api.bilibili.com');
    expect(headers['Cookie'], contains('SESSDATA=fixture'));
    return response({'isLogin': true, 'mid': navMid, 'uname': 'fixture'});
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    paths.add(uri.path);
    expect(uri.host, 'passport.bilibili.com');
    expect(
      uri.path,
      isIn([
        '/x/passport-tv-login/qrcode/auth_code',
        '/x/passport-tv-login/qrcode/poll',
      ]),
    );
    expect(headers.containsKey('Cookie'), isFalse);
    expect(fields['sign'], isNotEmpty);
    if (uri.path.endsWith('/auth_code')) {
      return response({
        'auth_code': 'fixture-code',
        'url': 'https://passport.bilibili.com/fixture',
      });
    }
    return response({
      'mid': tokenMid,
      'access_token': 'fixture-app',
      'refresh_token': 'fixture-refresh',
      'expires_in': 86400,
      if (includeCookies)
        'cookie_info': {
          'cookies': [
            {'name': 'SESSDATA', 'value': 'fixture'},
            {'name': 'bili_jct', 'value': 'fixture-csrf'},
          ],
        },
    });
  }
}
