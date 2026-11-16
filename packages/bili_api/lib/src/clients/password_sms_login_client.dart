import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/asn1.dart';
import 'package:pointycastle/export.dart' hide Digest;

import '../api_client.dart';
import '../models.dart';
import '../models/app_recommendation_models.dart';
import 'app_passport_client.dart';

final class ApiLoginCaptcha {
  const ApiLoginCaptcha(this.gt, this.challenge, this.token);
  final String gt, challenge, token;
}

final class ApiLoginCaptchaProof {
  const ApiLoginCaptchaProof(this.challenge, this.validate, this.seccode);
  final String challenge, validate, seccode;
}

sealed class ApiAppLoginResult {
  const ApiAppLoginResult();
}

final class ApiAppLoginSuccess extends ApiAppLoginResult {
  const ApiAppLoginSuccess(this.credentials, this.cookies);
  final ApiAppCredentials credentials;
  final List<ApiLoginCookie> cookies;
}

final class ApiAppLoginCaptcha extends ApiAppLoginResult {
  const ApiAppLoginCaptcha(this.captcha);
  final ApiLoginCaptcha captcha;
}

final class ApiAppLoginVerification extends ApiAppLoginResult {
  const ApiAppLoginVerification(this.url);
  final Uri url;
}

final class ApiAppLoginSmsSent extends ApiAppLoginResult {
  const ApiAppLoginSmsSent(this.captchaKey);
  final String captchaKey;
}

/// App Passport protocol, independently implemented from documented endpoints.
/// The protocol comparison and GPL reference scope are recorded in docs.
final class PasswordSmsLoginClient {
  PasswordSmsLoginClient(this.api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;
  final BiliApiClient api;
  final DateTime Function() _clock;
  final _random = Random.secure();
  late final String _deviceId = _newDeviceId();
  static const _statistics =
      '{"appId":5,"platform":3,"version":"2.0.1","abtest":""}';

  String _newDeviceId() {
    final time = _clock();
    int bcd(int value) => (value ~/ 10) * 16 + value % 10;
    final bytes = [
      for (var i = 0; i < 16; i++) _random.nextInt(256),
      for (final n in [
        time.year ~/ 100,
        time.year % 100,
        time.month,
        time.day,
        time.hour,
        time.minute,
        time.second,
      ])
        bcd(n),
      for (var i = 0; i < 8; i++) _random.nextInt(256),
    ];
    return '${Digest(bytes)}${(bytes.fold<int>(0, (a, b) => a + b) & 255).toRadixString(16).padLeft(2, '0')}';
  }

  Map<String, String> _base(String buvid) => {
    'build': '2001100',
    'buvid': buvid,
    'c_locale': 'zh_CN',
    'channel': 'master',
    'disable_rcmd': '0',
    'local_id': buvid,
    'mobi_app': 'android_hd',
    'platform': 'android',
    's_locale': 'zh_CN',
    'statistics': _statistics,
  };

  Future<Map<String, String>> _device(
    String publicKey,
    ApiRequestContext? context,
  ) async {
    final info = await api.appDeviceInfo(context: context);
    return {
      'bili_local_id': _deviceId, 'device': 'phone', 'device_id': _deviceId,
      'device_name': info.model,
      'device_platform': 'Android${info.osVersion}${info.model}',
      // These two Passport values are protocol-encoded before form encoding.
      'dt': Uri.encodeComponent(
        _encrypt(
          publicKey,
          List.generate(
            16,
            (_) => _random.nextInt(36).toRadixString(36),
          ).join(),
        ),
      ),
    };
  }

  Map<String, String> _proof(
    ApiLoginCaptcha? captcha,
    ApiLoginCaptchaProof? proof,
  ) {
    if (proof == null) return const {};
    if (captcha == null ||
        proof.challenge.length > 4096 ||
        proof.challenge.isEmpty ||
        proof.validate.isEmpty ||
        proof.validate.length > 4096 ||
        proof.seccode.isEmpty ||
        proof.seccode.length > 4096) {
      throw ArgumentError('Invalid captcha proof');
    }
    return {
      'gee_challenge': proof.challenge,
      'gee_validate': proof.validate,
      'gee_seccode': proof.seccode,
      'recaptcha_token': captcha.token,
    };
  }

  Future<Map<String, Object?>> _request(
    String path,
    Map<String, String> fields,
    String buvid,
    ApiRequestContext? context, {
    bool post = true,
    String? referer,
  }) => api.requestPasswordSmsJson(
    path,
    fields,
    buvid: buvid,
    endpoint: 'app_password_sms_login',
    post: post,
    referer: referer,
    context: context,
  );

  Map<String, Object?> _data(Map<String, Object?> root) {
    if (root['code'] != 0) {
      throw ApiFailure(
        ApiFailureCategory.authentication,
        'app_password_sms_login',
        businessCode: root['code'] as int,
      );
    }
    final data = root['data'];
    if (data is! Map<String, Object?>) _protocol();
    return data;
  }

  Never _protocol() => throw const ApiFailure(
    ApiFailureCategory.protocol,
    'app_password_sms_login',
  );

  String _string(Object? value, {int maximum = 4096, bool multiline = false}) {
    if (value is! String ||
        value.isEmpty ||
        value.length > maximum ||
        RegExp(multiline ? r'\x00' : r'[\r\n\x00]').hasMatch(value)) {
      _protocol();
    }
    return value;
  }

  Uri _passportUri(Object? value, {required bool verification}) {
    final uri = Uri.tryParse(_string(value, maximum: 8192));
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host != 'passport.bilibili.com' ||
        uri.port != 443 ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (verification && uri.path != '/h5-app/passport/risk/verify')) {
      _protocol();
    }
    return uri;
  }

  ApiLoginCaptcha? _captcha(Object? value) {
    if (value == null || value == '') return null;
    // This URL supplies captcha fields; it is never a navigation destination.
    // App Passport currently returns www.bilibili.com for password challenges.
    if (value is! String || value.length > 8192) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.port != 443 ||
        !const {
          'passport.bilibili.com',
          'www.bilibili.com',
        }.contains(uri.host) ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return _captchaFields(uri.queryParameters);
  }

  ApiLoginCaptcha? _captchaFields(Map<String, Object?> data) {
    final gt = data['gee_gt'],
        challenge = data['gee_challenge'],
        token = data['recaptcha_token'];
    bool valid(Object? value) =>
        value is String &&
        value.isNotEmpty &&
        value.length <= 4096 &&
        !RegExp(r'[\r\n\x00]').hasMatch(value);
    if (!valid(gt) || !valid(challenge) || !valid(token)) return null;
    return ApiLoginCaptcha(gt as String, challenge as String, token as String);
  }

  ApiLoginCaptcha? _responseCaptcha(Object? data) =>
      data is Map<String, Object?>
      ? _captcha(data['url']) ??
            _captcha(data['recaptcha_url']) ??
            _captchaFields(data)
      : null;

  Future<ApiAppLoginResult> _smsResult(
    Map<String, Object?> root,
    String buvid,
    ApiRequestContext? context,
  ) async {
    final data = root['data'];
    final challenge = _responseCaptcha(data);
    if (root['code'] == -105 ||
        root['code'] == 0 &&
            (challenge != null ||
                data is! Map<String, Object?> ||
                data['captcha_key'] is! String ||
                data['captcha_key'] == '' ||
                data['recaptcha_url'] != null && data['recaptcha_url'] != '')) {
      return ApiAppLoginCaptcha(
        challenge ?? await prepareCaptcha(buvid: buvid, context: context),
      );
    }
    return ApiAppLoginSmsSent(_string(_data(root)['captcha_key']));
  }

  Future<({String key, String salt})> _key(
    String buvid,
    ApiRequestContext? context,
  ) async {
    final data = _data(
      await _request(
        '/x/passport-login/web/key',
        const {},
        buvid,
        context,
        post: false,
      ),
    );
    return (
      key: _string(data['key'], maximum: 8192, multiline: true),
      salt: _string(data['hash'], maximum: 256),
    );
  }

  ApiAppLoginResult _loginResult(Map<String, Object?> root) {
    final data = root['data'];
    if (root['code'] == -105 ||
        root['code'] == 0 &&
            data is Map<String, Object?> &&
            data['status'] == 1) {
      final captcha = _responseCaptcha(data);
      if (captcha != null) return ApiAppLoginCaptcha(captcha);
      // A password registration belongs to this attempt; a generic pre-captcha
      // cannot replace its token. Report an unavailable challenge explicitly.
      throw const ApiFailure(
        ApiFailureCategory.unavailable,
        'app_login_captcha',
      );
    }
    final success = _data(root);
    if (success['status'] == 2) {
      final url = _passportUri(success['url'], verification: true);
      for (final key in ['tmp_token', 'request_id', 'source']) {
        _string(url.queryParameters[key]);
      }
      return ApiAppLoginVerification(url);
    }
    final parsed = AppPassportClient(
      api,
      clock: _clock,
    ).parseLogin(success, endpoint: 'app_password_sms_login');
    final credentials = parsed.credentials;
    if (credentials == null || parsed.cookies.isEmpty) _protocol();
    return ApiAppLoginSuccess(credentials, parsed.cookies);
  }

  Future<ApiAppLoginResult> password({
    required String username,
    required String password,
    required String buvid,
    ApiLoginCaptcha? captcha,
    ApiLoginCaptchaProof? proof,
    ApiRequestContext? context,
  }) async {
    if (username.trim().isEmpty ||
        username.length > 256 ||
        password.isEmpty ||
        password.length > 1024) {
      throw ArgumentError('Invalid login input');
    }
    final key = await _key(buvid, context);
    return _loginResult(
      await _request(
        '/x/passport-login/oauth2/login',
        {
          ..._base(buvid),
          ...await _device(key.key, context),
          ..._proof(captcha, proof),
          'username': username,
          'password': _encrypt(key.key, key.salt + password),
          'permission': 'ALL',
          'from_pv': 'main.homepage.avatar-nologin.all.click',
          'from_url': Uri.encodeComponent('bilibili://pegasus/promo'),
        },
        buvid,
        context,
      ),
    );
  }

  Future<ApiAppLoginResult> sendSms({
    required String countryCode,
    required String phone,
    required String buvid,
    ApiLoginCaptcha? captcha,
    ApiLoginCaptchaProof? proof,
    ApiRequestContext? context,
  }) async {
    if (!RegExp(r'^[1-9][0-9]{0,4}$').hasMatch(countryCode) ||
        !RegExp(r'^[0-9]{5,20}$').hasMatch(phone)) {
      throw ArgumentError('Invalid phone');
    }
    final root = await _request(
      '/x/passport-login/sms/send',
      {
        ..._base(buvid),
        ..._proof(captcha, proof),
        'cid': countryCode,
        'tel': phone,
        'login_session_id': md5
            .convert(ascii.encode('$buvid${_clock().millisecondsSinceEpoch}'))
            .toString(),
      },
      buvid,
      context,
    );
    return _smsResult(root, buvid, context);
  }

  Future<ApiAppLoginResult> sms({
    required String countryCode,
    required String phone,
    required String code,
    required String captchaKey,
    required String buvid,
    ApiLoginCaptcha? captcha,
    ApiLoginCaptchaProof? proof,
    ApiRequestContext? context,
  }) async {
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(code)) {
      throw ArgumentError('Invalid SMS code');
    }
    final key = await _key(buvid, context);
    return _loginResult(
      await _request(
        '/x/passport-login/login/sms',
        {
          ..._base(buvid),
          ...await _device(key.key, context),
          ..._proof(captcha, proof),
          'cid': countryCode,
          'tel': phone,
          'code': code,
          'captcha_key': captchaKey,
          'from_pv': 'main.my-information.my-login.0.click',
          'from_url': Uri.encodeComponent('bilibili://user_center/mine'),
        },
        buvid,
        context,
      ),
    );
  }

  Future<ApiLoginCaptcha> prepareCaptcha({
    required String buvid,
    ApiRequestContext? context,
  }) async {
    final data = _data(
      await _request('/x/safecenter/captcha/pre', const {}, buvid, context),
    );
    final type = data['recaptcha_type'];
    if (type != null && type != 'geetest') {
      // A Geetest 4 captcha ID cannot be passed to the fullpage/v3 renderer.
      // Reject the protocol explicitly instead of reporting a stale v3 config.
      throw const ApiFailure(
        ApiFailureCategory.unavailable,
        'app_login_captcha_type',
      );
    }
    return ApiLoginCaptcha(
      _string(data['gee_gt']),
      _string(data['gee_challenge']),
      _string(data['recaptcha_token']),
    );
  }

  Future<String> verificationPhone({
    required Uri url,
    required String buvid,
    ApiRequestContext? context,
  }) async {
    final safe = _passportUri(url.toString(), verification: true);
    final data = _data(
      await _request(
        '/x/safecenter/user/info',
        {'tmp_code': _string(safe.queryParameters['tmp_token'])},
        buvid,
        context,
        post: false,
      ),
    );
    final info = data['account_info'];
    if (info is! Map<String, Object?> || info['tel_verify'] != true) {
      throw const ApiFailure(
        ApiFailureCategory.unavailable,
        'app_login_phone_verification',
      );
    }
    return _string(info['hide_tel'], maximum: 64);
  }

  Future<ApiAppLoginResult> sendVerificationSms({
    required Uri url,
    required String buvid,
    required ApiLoginCaptcha captcha,
    required ApiLoginCaptchaProof proof,
    ApiRequestContext? context,
  }) async {
    final safe = _passportUri(url.toString(), verification: true);
    final root = await _request(
      '/x/safecenter/common/sms/send',
      {
        'disable_rcmd': '0',
        'sms_type': 'loginTelCheck',
        'tmp_code': _string(safe.queryParameters['tmp_token']),
        ..._proof(captcha, proof),
      },
      buvid,
      context,
      referer: safe.toString(),
    );
    return _smsResult(root, buvid, context);
  }

  Future<ApiAppLoginResult> verifyPhone({
    required Uri url,
    required String captchaKey,
    required String code,
    required String buvid,
    ApiRequestContext? context,
  }) async {
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(code)) {
      throw ArgumentError('Invalid SMS code');
    }
    final safe = _passportUri(url.toString(), verification: true);
    final data = _data(
      await _request(
        '/x/safecenter/login/tel/verify',
        {
          'type': 'loginTelCheck',
          'code': code,
          'captcha_key': captchaKey,
          'tmp_code': _string(safe.queryParameters['tmp_token']),
          'request_id': _string(safe.queryParameters['request_id']),
          'source': _string(safe.queryParameters['source']),
        },
        buvid,
        context,
        referer: safe.toString(),
      ),
    );
    return _loginResult(
      await _request(
        '/x/passport-login/oauth2/access_token',
        {
          'build': '2001100',
          'buvid': buvid,
          'code': _string(data['code']),
          'disable_rcmd': '0',
          'grant_type': 'authorization_code',
          'local_id': buvid,
          'mobi_app': 'android_hd',
          'platform': 'android',
        },
        buvid,
        context,
      ),
    );
  }

  String _encrypt(String pem, String text) {
    try {
      final der = base64Decode(
        pem.replaceAll(RegExp(r'-----[^-]+-----|\s'), ''),
      );
      final parsed = ASN1Parser(der).nextObject();
      if (parsed is! ASN1Sequence) _protocol();
      final elements = parsed.elements;
      if (elements == null || elements.length != 2) _protocol();
      ASN1Sequence sequence = parsed;
      if (elements[0] is! ASN1Integer) {
        final algorithm = elements[0], bits = elements[1];
        if (algorithm is! ASN1Sequence || bits is! ASN1BitString) _protocol();
        final oid = algorithm.elements?.firstOrNull;
        final bytes = bits.stringValues;
        if (oid is! ASN1ObjectIdentifier ||
            oid.objectIdentifierAsString != '1.2.840.113549.1.1.1' ||
            bytes == null ||
            bits.unusedbits != 0) {
          _protocol();
        }
        final key = ASN1Parser(Uint8List.fromList(bytes)).nextObject();
        if (key is! ASN1Sequence) _protocol();
        sequence = key;
      }
      final numbers = sequence.elements;
      if (numbers == null || numbers.length != 2) _protocol();
      final n = numbers[0], e = numbers[1];
      if (n is! ASN1Integer || e is! ASN1Integer) _protocol();
      final modulus = n.integer, exponent = e.integer;
      if (modulus == null ||
          exponent == null ||
          modulus.bitLength < 1024 ||
          modulus.bitLength > 4096 ||
          exponent < BigInt.from(3)) {
        _protocol();
      }
      final random = FortunaRandom()
        ..seed(
          KeyParameter(
            Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256))),
          ),
        );
      final cipher = PKCS1Encoding(RSAEngine())
        ..init(
          true,
          ParametersWithRandom(
            PublicKeyParameter<RSAPublicKey>(RSAPublicKey(modulus, exponent)),
            random,
          ),
        );
      final bytes = Uint8List.fromList(utf8.encode(text));
      if (bytes.length > cipher.inputBlockSize) {
        throw ArgumentError('Password exceeds RSA block size');
      }
      return base64Encode(cipher.process(bytes));
    } on ArgumentError {
      rethrow;
    } on Object {
      _protocol();
    }
  }
}
