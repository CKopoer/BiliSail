import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _device = 'fixture_device_0123456789';
Map<String, Object?> _token() => {
  'mid': 42,
  'access_token': 'fixture-app',
  'refresh_token': 'fixture-refresh',
  'expires_in': 86400,
  'cookie_info': {
    'cookies': [
      {'name': 'SESSDATA', 'value': 'fixture'},
      {'name': 'bili_jct', 'value': 'fixture-csrf'},
    ],
  },
};
void main() {
  test(
    'HD response uses top-level token and Cookie metadata in one result',
    () async {
      final transport = _Transport()..data = _token();
      final result = await AppPassportClient(
        BiliApiClient(transport: transport),
      ).poll(buvid: _device, authCode: 'fixture-code');
      expect(result.credentials?.accessToken, 'fixture-app');
      expect(result.credentials?.refreshToken, 'fixture-refresh');
      expect(result.cookies.map((cookie) => cookie.name), [
        'SESSDATA',
        'bili_jct',
      ]);
      expect(
        result.cookies.every((cookie) => cookie.domain == 'bilibili.com'),
        isTrue,
      );
      expect(transport.headers.single.containsKey('Cookie'), isFalse);
    },
  );
  for (final bad in [
    {'name': 'SESSDATA', 'value': 'fixture', 'domain': 'example.com'},
    {'name': 'SESSDATA', 'value': 'fixture\r\nCookie: bad'},
    {'name': 'bad;name', 'value': 'fixture'},
    {'name': 'SESSDATA', 'value': 'fixture', 'expires': -2},
  ]) {
    test('invalid returned Cookie cannot enter a session: $bad', () async {
      final transport = _Transport()
        ..data = {
          ..._token(),
          'cookie_info': {
            'cookies': [bad],
          },
        };
      await expectLater(
        AppPassportClient(
          BiliApiClient(transport: transport),
        ).poll(buvid: _device, authCode: 'fixture-code'),
        throwsA(
          isA<ApiFailure>().having(
            (value) => value.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }
}

final class _Transport implements ApiTransport, ApiFormTransport {
  Object data = {};
  final headers = <Map<String, String>>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => throw StateError('unexpected GET');
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.headers.add(headers);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
