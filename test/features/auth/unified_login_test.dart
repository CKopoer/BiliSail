import 'package:bilisail/features/feed/domain/feed_repository.dart';

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
import 'package:bilisail/features/auth/domain/password_sms_auth_repository.dart';
import 'package:pointycastle/asn1.dart';
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

  test(
    'password captcha cannot refresh into an unrelated SMS registration',
    () async {
      transport.passwordCaptcha = true;
      final attempt = session.beginPasswordSmsLogin()!;
      final step = await session.loginWithPassword(
        attempt,
        'fixture',
        'fixture',
      );
      expect(step.stage, PasswordSmsLoginStage.captcha);
      expect(step.canRefreshCaptcha, isFalse);
      await expectLater(
        session.refreshLoginCaptcha(attempt),
        throwsA(isA<AppFailure>()),
      );
      expect(transport.preCaptchas, 0);
    },
  );

  test(
    'SMS captcha refresh is bounded and replaces the entire registration',
    () async {
      transport.smsCaptcha = true;
      final attempt = session.beginPasswordSmsLogin()!;
      final first = await session.sendLoginSms(attempt, '86', '13800000000');
      expect(first.canRefreshCaptcha, isTrue);
      final fresh = await session.refreshLoginCaptcha(attempt);
      expect(fresh.gt, 'refreshed-gt');
      expect(fresh.challenge, 'refreshed-challenge');
      expect(fresh.canRefreshCaptcha, isFalse);
      await expectLater(
        session.refreshLoginCaptcha(attempt),
        throwsA(isA<AppFailure>()),
      );
      expect(transport.preCaptchas, 1);
      transport.smsCaptcha = false;
      await session.sendLoginSms(
        attempt,
        '86',
        '13800000000',
        proof: const LoginCaptchaProof(
          'returned-challenge',
          'passed',
          'passed|jordan',
        ),
      );
      expect(transport.lastRecaptchaToken, 'refreshed-token');
    },
  );

  test('cancelled captcha refresh cannot issue a new registration', () async {
    transport.smsCaptcha = true;
    final attempt = session.beginPasswordSmsLogin()!;
    await session.sendLoginSms(attempt, '86', '13800000000');
    session.cancelSignIn();
    await expectLater(
      session.refreshLoginCaptcha(attempt),
      throwsA(isA<AppFailure>()),
    );
    expect(transport.preCaptchas, 0);
  });

  for (final refresh in [false, true]) {
    test(
      'password risk SMS keeps its own registration and commits App credentials: refresh=$refresh',
      () async {
        transport.passwordCaptcha = true;
        transport.passwordVerification = true;
        final attempt = session.beginPasswordSmsLogin()!;
        final first = await session.loginWithPassword(
          attempt,
          'fixture',
          'fixture',
        );
        expect(first.stage, PasswordSmsLoginStage.captcha);
        transport.passwordCaptcha = false;
        final phone = await session.loginWithPassword(
          attempt,
          'fixture',
          'fixture',
          proof: const LoginCaptchaProof(
            'password-proof',
            'passed',
            'passed|jordan',
          ),
        );
        expect(phone.stage, PasswordSmsLoginStage.verifyPhone);
        expect(phone.maskedPhone, '138****0000');
        expect(transport.preCaptchas, 0);
        final registration = await session.sendVerificationSms(attempt);
        expect(registration.stage, PasswordSmsLoginStage.captcha);
        expect(registration.canRefreshCaptcha, isTrue);
        expect(
          transport.paths,
          isNot(contains('/x/safecenter/common/sms/send')),
        );
        if (refresh) {
          final fresh = await session.refreshLoginCaptcha(attempt);
          expect(fresh.canRefreshCaptcha, isFalse);
        }
        expect(transport.preCaptchas, refresh ? 2 : 1);
        final sent = await session.sendVerificationSms(
          attempt,
          proof: const LoginCaptchaProof(
            'sms-proof',
            'passed',
            'passed|jordan',
          ),
        );
        expect(sent.stage, PasswordSmsLoginStage.smsSent);
        expect(transport.lastRecaptchaToken, 'refreshed-token');
        expect(transport.verificationSmsForm!['gee_challenge'], 'sms-proof');
        expect(transport.verificationSmsForm!['tmp_code'], 'fixture-temp');
        expect(transport.verificationSmsForm!['sms_type'], 'loginTelCheck');
        expect(transport.verificationSmsHeaders!['app-key'], 'android_hd');
        expect(transport.verificationSmsHeaders!['buvid'], _device);
        expect(transport.verificationSmsHeaders!['Referer'], _verificationUrl);
        final complete = await session.verifyLoginPhone(attempt, '123456');
        expect(complete.stage, PasswordSmsLoginStage.completed);
        expect(session.current.isSignedIn, isTrue);
        expect(session.appCredentials?.accessToken, 'fixture-app');
        expect(
          transport.paths.where((p) => p == '/x/safecenter/common/sms/send'),
          hasLength(1),
        );
        expect(
          transport.paths,
          contains('/x/passport-login/oauth2/access_token'),
        );
      },
    );
  }

  test(
    'unsupported risk captcha reports its type without sending SMS',
    () async {
      transport.passwordVerification = true;
      transport.preCaptchaType = 'geetest4';
      final attempt = session.beginPasswordSmsLogin()!;
      await session.loginWithPassword(attempt, 'fixture', 'fixture');
      await expectLater(
        session.sendVerificationSms(attempt),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.message,
            'message',
            '当前人机验证类型暂不可用，请使用扫码登录或官网登录',
          ),
        ),
      );
      expect(transport.preCaptchas, 1);
      expect(transport.paths, isNot(contains('/x/safecenter/common/sms/send')));
    },
  );

  for (final sms in [false, true]) {
    test(
      'App ${sms ? 'SMS' : 'password'} commits both identities and restores them',
      () async {
        final attempt = session.beginPasswordSmsLogin()!;
        if (sms) {
          expect(
            (await session.sendLoginSms(attempt, '86', '13800000000')).stage,
            PasswordSmsLoginStage.smsSent,
          );
          await session.loginWithSms(attempt, '123456');
        } else {
          await session.loginWithPassword(
            attempt,
            'fixture',
            'fixture-password',
          );
        }
        expect(session.current.isSignedIn, isTrue);
        expect(session.current.appSessionAvailable, isTrue);
        expect((await identity.requestIdentity()).accessToken, 'fixture-app');
        expect(
          jsonDecode(secure.value!)['app']['refreshToken'],
          'fixture-refresh',
        );
        expect(secure.value, isNot(contains('fixture-password')));
        final snapshot = secure.value;
        await session.restore();
        expect(session.current.appSessionAvailable, isTrue);
        expect(secure.value, snapshot);
        transport.feedAccessToken = 'fixture-app';
        transport.feedAccountMid = '42';
        await ApiFeedRepository(
          session.api,
          session.requests,
          appIdentity: identity,
        ).loadAppRecommendations(
          request: const AppRecommendationRequest(),
          cancellation: RequestCancellation(),
        );
      },
    );
  }

  test('App login rejects mismatched token and Cookie identities', () async {
    transport.tokenMid = 7;
    final attempt = session.beginPasswordSmsLogin()!;
    await expectLater(
      session.loginWithPassword(attempt, 'fixture', 'fixture'),
      throwsA(isA<AppFailure>()),
    );
    expect(session.current.isSignedIn, isFalse);
    expect(secure.value, isNull);
    expect(session.appCredentials, isNull);
  });

  test(
    'cancelled or forged App attempts cannot submit or promote credentials',
    () async {
      final attempt = session.beginPasswordSmsLogin()!;
      session.cancelSignIn();
      for (final old in [attempt, PasswordSmsLoginAttempt()]) {
        await expectLater(
          session.loginWithPassword(old, 'fixture', 'fixture'),
          throwsA(
            isA<AppFailure>().having(
              (e) => e.kind,
              'kind',
              AppFailureKind.cancelled,
            ),
          ),
        );
      }
      expect(transport.paths, isEmpty);
      expect(secure.value, isNull);
    },
  );

  test(
    'App login cancellation during secure write rolls back both identities',
    () async {
      secure.gate = Completer<void>();
      final attempt = session.beginPasswordSmsLogin()!;
      final checked = expectLater(
        session.loginWithPassword(attempt, 'fixture', 'fixture'),
        throwsA(isA<AppFailure>()),
      );
      await secure.started.future;
      session.cancelSignIn();
      secure.gate!.complete();
      await checked;
      expect(secure.value, isNull);
      expect(session.appCredentials, isNull);
      expect(session.current.isSignedIn, isFalse);
    },
  );

  test(
    'App login secure write failure cannot leave a Cookie-only login',
    () async {
      secure.failWrite = true;
      final attempt = session.beginPasswordSmsLogin()!;
      await expectLater(
        session.loginWithPassword(attempt, 'fixture', 'fixture'),
        throwsA(isA<AppFailure>()),
      );
      expect(secure.value, isNull);
      expect(session.appCredentials, isNull);
      expect(session.current.isSignedIn, isFalse);
    },
  );

  test(
    'App SMS requires an issued key and duplicate submissions are blocked',
    () async {
      final attempt = session.beginPasswordSmsLogin()!;
      await expectLater(
        session.loginWithSms(attempt, '123456'),
        throwsA(isA<AppFailure>()),
      );
      secure.gate = Completer<void>();
      final operation = session.loginWithPassword(
        attempt,
        'fixture',
        'fixture',
      );
      await secure.started.future;
      await expectLater(
        session.loginWithPassword(attempt, 'fixture', 'fixture'),
        throwsA(isA<AppFailure>()),
      );
      secure.gate!.complete();
      await operation;
      expect(secure.writes, 1);
    },
  );

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
    transport.feedAccessToken = 'fixture-app';
    transport.feedAccountMid = '42';
    final page =
        await ApiFeedRepository(
          session.api,
          session.requests,
          appIdentity: identity,
        ).loadAppRecommendations(
          request: const AppRecommendationRequest(),
          cancellation: RequestCancellation(),
        );
    expect(page.items.single.id.value, 'BV17x411w7KC');
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
    'explicit official Web login commits without App authorization requests',
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
    final page =
        await ApiFeedRepository(
          session.api,
          session.requests,
          appIdentity: identity,
        ).loadAppRecommendations(
          request: const AppRecommendationRequest(),
          cancellation: RequestCancellation(),
        );
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

const _verificationUrl =
    'https://passport.bilibili.com/h5-app/passport/risk/verify?tmp_token=fixture-temp&request_id=fixture-request&source=risk';

final class _Transport implements ApiTransport, ApiFormTransport {
  final paths = <String>[];
  int navMid = 42, tokenMid = 42;
  bool includeCookies = true;
  bool passwordCaptcha = false, smsCaptcha = false;
  bool passwordVerification = false;
  String? preCaptchaType;
  Map<String, String>? verificationSmsForm, verificationSmsHeaders;
  int preCaptchas = 0;
  String? lastRecaptchaToken;
  String? feedAccessToken, feedAccountMid;
  ApiHttpResponse response(Object data, {int status = 200, int code = 0}) =>
      ApiHttpResponse(
        status,
        Uint8List.fromList(
          utf8.encode(jsonEncode({'code': code, 'data': data})),
        ),
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
    if (uri.path == '/x/passport-login/web/key') {
      final key = ASN1Sequence(
        elements: [
          ASN1Integer((BigInt.one << 1024) - BigInt.from(109)),
          ASN1Integer(BigInt.from(65537)),
        ],
      ).encode();
      return response({
        'hash': 'fixture-hash',
        'key':
            '-----BEGIN RSA PUBLIC KEY-----\n${base64Encode(key)}\n-----END RSA PUBLIC KEY-----',
      });
    }
    if (uri.path == '/x/safecenter/user/info') {
      expect(uri.queryParameters['tmp_code'], 'fixture-temp');
      return response({
        'account_info': {'tel_verify': true, 'hide_tel': '138****0000'},
      });
    }
    if (uri.path == '/x/v2/feed/index') {
      expect(uri.host, 'app.bilibili.com');
      expect(headers.containsKey('Cookie'), isFalse);
      expect(uri.queryParameters['access_key'], feedAccessToken);
      expect(headers['x-bili-mid'], feedAccountMid);
      expect(headers['x-bili-aurora-eid'], feedAccountMid == null ? '' : 'VVY');
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
        '/x/passport-login/oauth2/login',
        '/x/passport-login/sms/send',
        '/x/passport-login/login/sms',
        '/x/safecenter/captcha/pre',
        '/x/safecenter/common/sms/send',
        '/x/safecenter/login/tel/verify',
        '/x/passport-login/oauth2/access_token',
      ]),
    );
    expect(headers.containsKey('Cookie'), isFalse);
    if (uri.path == '/x/safecenter/captcha/pre') {
      expect(headers, isNot(contains('buvid')));
      expect(headers, isNot(contains('app-key')));
      expect(fields, isEmpty);
      preCaptchas++;
      return response({
        'recaptcha_type': preCaptchaType ?? 'geetest',
        'gee_gt': 'refreshed-gt',
        'gee_challenge': 'refreshed-challenge',
        'recaptcha_token': 'refreshed-token',
      });
    }
    expect(fields['sign'], isNotEmpty);
    lastRecaptchaToken = fields['recaptcha_token'];
    const captchaUrl =
        'https://www.bilibili.com/h5/project-msg-auth/verify?recaptcha_token=old-token&gee_gt=old-gt&gee_challenge=old-challenge';
    if (uri.path == '/x/passport-login/oauth2/login' && passwordCaptcha) {
      return response({'url': captchaUrl, 'status': 1}, code: -105);
    }
    if (uri.path == '/x/passport-login/oauth2/login' && passwordVerification) {
      return response({'status': 2, 'url': _verificationUrl});
    }
    if (uri.path == '/x/safecenter/common/sms/send') {
      verificationSmsForm = Map.of(fields);
      verificationSmsHeaders = Map.of(headers);
      return response({'captcha_key': 'fixture-risk-sms'});
    }
    if (uri.path == '/x/safecenter/login/tel/verify') {
      expect(headers['Referer'], _verificationUrl);
      expect(fields['captcha_key'], 'fixture-risk-sms');
      expect(fields['request_id'], 'fixture-request');
      expect(fields['source'], 'risk');
      expect(fields['code'], '123456');
      return response({'code': 'fixture-oauth'});
    }
    if (uri.path == '/x/passport-login/oauth2/access_token') {
      expect(fields['grant_type'], 'authorization_code');
      expect(fields['code'], 'fixture-oauth');
    }
    if (uri.path == '/x/passport-login/sms/send') {
      if (smsCaptcha) {
        return response({'recaptcha_url': captchaUrl}, code: -105);
      }
      return response({'recaptcha_url': '', 'captcha_key': 'fixture-sms'});
    }
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
