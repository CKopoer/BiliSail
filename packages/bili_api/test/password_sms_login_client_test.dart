import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

void main() {
  late _Transport transport;
  late PasswordSmsLoginClient client;
  setUp(() {
    transport = _Transport();
    client = PasswordSmsLoginClient(
      BiliApiClient(transport: transport),
      clock: () => DateTime.utc(2026, 11, 15),
    );
  });

  test(
    'App password encrypts salted input and returns both credentials',
    () async {
      final result = await client.password(
        username: 'fixture@example.test',
        password: 'fixture-password',
        buvid: device,
      );
      final success = result as ApiAppLoginSuccess;
      expect(success.credentials.accessToken, 'fixture-app');
      expect(success.cookies.single.name, 'SESSDATA');
      expect(transport.paths, [
        '/x/passport-login/web/key',
        '/x/passport-login/oauth2/login',
      ]);
      final form = transport.forms.single;
      expect(_decrypt(form['password']!), 'fixture-saltfixture-password');
      expect(
        _decrypt(Uri.decodeComponent(form['dt']!)),
        matches(r'^[0-9a-z]{16}$'),
      );
      expect(form['mobi_app'], 'android_hd');
      expect(form['build'], '2001100');
      expect(form['permission'], 'ALL');
      expect(form['from_url'], 'bilibili%3A%2F%2Fpegasus%2Fpromo');
      expect(form['sign'], matches(r'^[a-f0-9]{32}$'));
      expect(form.values.join(), isNot(contains('fixture-password')));
    },
  );

  test(
    'SubjectPublicKeyInfo PEM supports the actual Passport key layout',
    () async {
      transport.spki = true;
      await client.password(
        username: 'fixture',
        password: 'fixture',
        buvid: device,
      );
      expect(
        _decrypt(transport.forms.single['password']!),
        'fixture-saltfixture',
      );
    },
  );

  test(
    'SMS registration, captcha continuation and SMS login use App paths',
    () async {
      transport.smsCaptcha = true;
      final first =
          await client.sendSms(
                countryCode: '86',
                phone: '13800000000',
                buvid: device,
              )
              as ApiAppLoginCaptcha;
      expect(first.captcha.token, 'fixture-recaptcha');
      transport.smsCaptcha = false;
      final sent =
          await client.sendSms(
                countryCode: '86',
                phone: '13800000000',
                buvid: device,
                captcha: first.captcha,
                proof: const ApiLoginCaptchaProof(
                  'fixture-challenge',
                  'passed',
                  'passed|jordan',
                ),
              )
              as ApiAppLoginSmsSent;
      expect(transport.forms.last['recaptcha_token'], 'fixture-recaptcha');
      final result = await client.sms(
        countryCode: '86',
        phone: '13800000000',
        code: '123456',
        captchaKey: sent.captchaKey,
        buvid: device,
      );
      expect(result, isA<ApiAppLoginSuccess>());
      expect(transport.forms.last['captcha_key'], 'fixture-sms');
      expect(transport.paths.last, '/x/passport-login/login/sms');
    },
  );

  test(
    'password captcha remains a challenge until explicit completion',
    () async {
      transport.passwordCaptcha = true;
      final step =
          await client.password(
                username: 'fixture',
                password: 'fixture',
                buvid: device,
              )
              as ApiAppLoginCaptcha;
      transport.passwordCaptcha = false;
      await client.password(
        username: 'fixture',
        password: 'fixture',
        buvid: device,
        captcha: step.captcha,
        proof: const ApiLoginCaptchaProof(
          'new-challenge',
          'valid',
          'valid|jordan',
        ),
      );
      expect(transport.forms.last['gee_challenge'], 'new-challenge');
      expect(transport.forms.last['recaptcha_token'], 'fixture-recaptcha');
    },
  );

  test(
    'bound-phone verification exchanges the returned authorization code',
    () async {
      transport.verify = true;
      final step =
          await client.password(
                username: 'fixture',
                password: 'fixture',
                buvid: device,
              )
              as ApiAppLoginVerification;
      expect(
        await client.verificationPhone(url: step.url, buvid: device),
        '138****0000',
      );
      final captcha = await client.prepareCaptcha(buvid: device);
      final sent = await client.sendVerificationSms(
        url: step.url,
        buvid: device,
        captcha: captcha,
        proof: const ApiLoginCaptchaProof('challenge', 'v', 's'),
      );
      final result = await client.verifyPhone(
        url: step.url,
        captchaKey: (sent as ApiAppLoginSmsSent).captchaKey,
        code: '123456',
        buvid: device,
      );
      expect(result, isA<ApiAppLoginSuccess>());
      expect(transport.forms.last['code'], 'fixture-oauth');
      expect(transport.forms.last['grant_type'], 'authorization_code');
      expect(transport.paths.last, '/x/passport-login/oauth2/access_token');
    },
  );

  test(
    'safe-center captcha uses unsigned Web registration without App headers',
    () async {
      final captcha = await client.prepareCaptcha(buvid: device);
      expect(captcha.gt, 'fixture-gt');
      expect(transport.paths, ['/x/safecenter/captcha/pre']);
      expect(transport.forms.single, isEmpty);
      final headers = transport.preCaptchaHeaders!;
      expect(headers['User-Agent'], contains('AppleWebKit'));
      for (final name in ['buvid', 'app-key', 'bili-http-engine', 'Cookie']) {
        expect(headers, isNot(contains(name)));
      }
    },
  );

  for (final type in ['geetest4', 'img']) {
    test(
      'unsupported $type registration never enters the v3 renderer',
      () async {
        transport.preCaptchaType = type;
        await expectLater(
          client.prepareCaptcha(buvid: device),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (e) => e.category,
                  'category',
                  ApiFailureCategory.unavailable,
                )
                .having(
                  (e) => e.endpointId,
                  'endpoint',
                  'app_login_captcha_type',
                ),
          ),
        );
        expect(transport.paths, ['/x/safecenter/captcha/pre']);
      },
    );
  }

  for (final url in [
    'http://passport.bilibili.com/h5-app/passport/risk/verify',
    'https://example.com/h5-app/passport/risk/verify',
    'https://passport.bilibili.com/other',
  ]) {
    test('untrusted verification URL is rejected: $url', () async {
      transport.verificationUrl = url;
      transport.verify = true;
      await expectLater(
        client.password(
          username: 'fixture',
          password: 'fixture',
          buvid: device,
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.paths.length, 2);
    });
  }

  test(
    'live-shaped www password challenge stays bound to its login token',
    () async {
      transport.passwordCaptcha = true;
      transport.captchaUrl =
          'https://www.bilibili.com/h5/project-msg-auth/verify?ct=1&recaptcha_token=fixture-recaptcha&gee_gt=fixture-gt&gee_challenge=fixture-challenge&hash=fixture-hash';
      final result =
          await client.password(
                username: 'fixture',
                password: 'fixture',
                buvid: device,
              )
              as ApiAppLoginCaptcha;
      expect(result.captcha.token, 'fixture-recaptcha');
      expect(transport.paths, [
        '/x/passport-login/web/key',
        '/x/passport-login/oauth2/login',
      ]);
    },
  );

  test(
    'code zero status one is a captcha step rather than missing credentials',
    () async {
      transport.loginRoot = {
        'code': 0,
        'data': {
          'status': 1,
          'recaptcha_url':
              'https://www.bilibili.com/h5/project-msg-auth/verify?recaptcha_token=t&gee_gt=g&gee_challenge=c',
          'token_info': null,
          'cookie_info': null,
        },
      };
      expect(
        await client.password(
          username: 'fixture',
          password: 'fixture',
          buvid: device,
        ),
        isA<ApiAppLoginCaptcha>(),
      );
    },
  );

  for (final data in <Object?>[
    null,
    {},
    {'recaptcha_url': ''},
    {
      'recaptcha_url':
          'https://www.bilibili.com/h5/project-msg-auth/verify?gee_gt=incomplete',
    },
    {
      'recaptcha_url':
          'https://example.com/?gee_gt=g&gee_challenge=c&recaptcha_token=t',
    },
  ]) {
    test(
      'SMS challenge with missing registration uses pre-captcha once: $data',
      () async {
        transport.smsRoot = {'code': -105, 'data': data};
        final result =
            await client.sendSms(
                  countryCode: '86',
                  phone: '13800000000',
                  buvid: device,
                )
                as ApiAppLoginCaptcha;
        expect(result.captcha.token, 'fixture-recaptcha');
        expect(transport.paths, [
          '/x/passport-login/sms/send',
          '/x/safecenter/captcha/pre',
        ]);
      },
    );
  }

  test(
    'password registration cannot be replaced by an unrelated pre-captcha',
    () async {
      transport.loginRoot = {
        'code': -105,
        'data': {'url': ''},
      };
      await expectLater(
        client.password(
          username: 'fixture',
          password: 'fixture',
          buvid: device,
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.unavailable,
          ),
        ),
      );
      expect(transport.paths, isNot(contains('/x/safecenter/captcha/pre')));
    },
  );

  test(
    'SMS login forwards captcha proof on explicit verification continuation',
    () async {
      await client.sms(
        countryCode: '86',
        phone: '13800000000',
        code: '123456',
        captchaKey: 'fixture-sms',
        buvid: device,
        captcha: const ApiLoginCaptcha('g', 'c', 'bound-token'),
        proof: const ApiLoginCaptchaProof(
          'returned-c',
          'passed',
          'passed|jordan',
        ),
      );
      expect(transport.forms.single['recaptcha_token'], 'bound-token');
      expect(transport.forms.single['gee_challenge'], 'returned-c');
    },
  );

  test(
    'SMS success without an explicit recaptcha_url retains the issued key',
    () async {
      transport.smsRoot = {
        'code': 0,
        'data': {'captcha_key': 'issued-key'},
      };
      final result =
          await client.sendSms(
                countryCode: '86',
                phone: '13800000000',
                buvid: device,
              )
              as ApiAppLoginSmsSent;
      expect(result.captchaKey, 'issued-key');
      expect(transport.paths.length, 1);
    },
  );

  test('ambiguous SMS send failures never replay a mutation', () async {
    transport.failSend = true;
    await expectLater(
      client.sendSms(countryCode: '86', phone: '13800000000', buvid: device),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.forms.length, 1);
  });

  test('expired cancellation discards a late login response', () async {
    transport.gate = Completer<void>();
    final cancel = ApiCancellation();
    final result = client.password(
      username: 'fixture',
      password: 'fixture',
      buvid: device,
      context: ApiRequestContext(cancellation: cancel),
    );
    await transport.started.future;
    cancel.cancel();
    transport.gate!.complete();
    await expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });

  for (final missing in ['token_info', 'cookie_info']) {
    test('missing $missing cannot complete App login', () async {
      transport.missing = missing;
      await expectLater(
        client.password(
          username: 'fixture',
          password: 'fixture',
          buvid: device,
        ),
        throwsA(isA<ApiFailure>()),
      );
    });
  }
}

const device = 'XY0123456789ABCDEF0123456789ABCDEF012';
final _random = FortunaRandom()
  ..seed(KeyParameter(Uint8List.fromList(List.generate(32, (i) => i + 1))));
final _generator = RSAKeyGenerator()
  ..init(
    ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), 1024, 64),
      _random,
    ),
  );
final _pair = _generator.generateKeyPair();
final _public = _pair.publicKey;
final _private = _pair.privateKey;
final _der = ASN1Sequence(
  elements: [ASN1Integer(_public.modulus), ASN1Integer(_public.exponent)],
).encode();
final pem =
    '-----BEGIN RSA PUBLIC KEY-----\n${base64Encode(_der)}\n-----END RSA PUBLIC KEY-----';
final spkiPem =
    '-----BEGIN PUBLIC KEY-----\n${base64Encode(ASN1Sequence(
      elements: [
        ASN1Sequence(elements: [
          ASN1ObjectIdentifier([1, 2, 840, 113549, 1, 1, 1]),
          ASN1Null(),
        ]),
        ASN1BitString(stringValues: _der),
      ],
    ).encode())}\n-----END PUBLIC KEY-----';
String _decrypt(String value) => utf8.decode(
  (PKCS1Encoding(RSAEngine())
        ..init(false, PrivateKeyParameter<RSAPrivateKey>(_private)))
      .process(base64Decode(value)),
);

class _Transport implements ApiTransport, ApiFormTransport {
  final paths = <String>[], forms = <Map<String, String>>[];
  bool smsCaptcha = false,
      passwordCaptcha = false,
      verify = false,
      failSend = false,
      spki = false;
  String? verificationUrl, missing, captchaUrl;
  Map<String, Object?>? loginRoot, smsRoot;
  Map<String, String>? preCaptchaHeaders;
  String? preCaptchaType;
  Completer<void>? gate;
  final started = Completer<void>();
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    _headers(uri, headers);
    paths.add(uri.path);
    return _response(
      uri.path.endsWith('/key')
          ? {'key': spki ? spkiPem : pem, 'hash': 'fixture-salt'}
          : {
              'account_info': {'hide_tel': '138****0000', 'tel_verify': true},
            },
    );
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    _headers(uri, headers);
    paths.add(uri.path);
    forms.add(Map.of(fields));
    if (failSend) throw const ApiFailure(ApiFailureCategory.network, 'fixture');
    if ((uri.path.endsWith('/oauth2/login') ||
            uri.path.endsWith('/login/sms')) &&
        loginRoot != null) {
      return _response(loginRoot!['data'], code: loginRoot!['code'] as int);
    }
    if (uri.path.endsWith('/sms/send') && smsRoot != null) {
      return _response(smsRoot!['data'], code: smsRoot!['code'] as int);
    }
    if (uri.path.endsWith('/captcha/pre')) {
      preCaptchaHeaders = Map.of(headers);
      return _response({
        'recaptcha_type':
            preCaptchaType ??
            (headers.containsKey('buvid') ? 'geetest4' : 'geetest'),
        'gee_gt': 'fixture-gt',
        'gee_challenge': 'fixture-challenge',
        'recaptcha_token': 'fixture-recaptcha',
      });
    }
    final captchaUrl =
        this.captchaUrl ??
        'https://passport.bilibili.com/recaptcha?gee_gt=fixture-gt&gee_challenge=fixture-challenge&recaptcha_token=fixture-recaptcha';
    if (uri.path.endsWith('/sms/send')) {
      return _response(
        smsCaptcha
            ? {'recaptcha_url': captchaUrl}
            : {'recaptcha_url': '', 'captcha_key': 'fixture-sms'},
      );
    }
    if (uri.path.endsWith('/tel/verify')) {
      return _response({'code': 'fixture-oauth'});
    }
    if (uri.path.endsWith('/oauth2/login')) {
      if (passwordCaptcha) return _response({'url': captchaUrl}, code: -105);
      if (verify) {
        return _response({
          'status': 2,
          'url':
              verificationUrl ??
              'https://passport.bilibili.com/h5-app/passport/risk/verify?tmp_token=fixture-temp&request_id=fixture-request&source=risk',
        });
      }
    }
    if (!started.isCompleted) started.complete();
    await gate?.future;
    final data = <String, Object?>{
      'token_info': {
        'mid': 42,
        'access_token': 'fixture-app',
        'refresh_token': 'fixture-refresh',
        'expires_in': 3600,
      },
      'cookie_info': {
        'cookies': [
          {'name': 'SESSDATA', 'value': 'fixture-cookie'},
        ],
      },
    };
    data.remove(missing);
    return _response(data);
  }

  void _headers(Uri uri, Map<String, String> headers) {
    expect(uri.host, 'passport.bilibili.com');
    expect(uri.queryParameters.containsKey('password'), isFalse);
    expect(headers.keys.map((e) => e.toLowerCase()), isNot(contains('cookie')));
    if (uri.path == '/x/safecenter/captcha/pre') {
      expect(headers, isNot(contains('buvid')));
      expect(headers, isNot(contains('app-key')));
    } else {
      expect(headers['app-key'], 'android_hd');
      expect(headers['buvid'], device);
    }
  }

  ApiHttpResponse _response(Object? data, {int code = 0}) => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
    const {},
  );
}
