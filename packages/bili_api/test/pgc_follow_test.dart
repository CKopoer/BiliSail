import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _season = '9007199254740993';
ApiHttpResponse _response(Object? result, {int code = 0, int status = 200}) =>
    ApiHttpResponse(
      status,
      Uint8List.fromList(
        utf8.encode(jsonEncode({'code': code, 'result': result})),
      ),
      const {},
    );

void main() {
  late _Transport transport;
  late BiliApiClient api;
  late PgcClient client;
  setUp(() {
    transport = _Transport();
    api = BiliApiClient(
      transport: transport,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]),
    );
    client = PgcClient(api);
  });
  tearDown(() => api.close());

  for (final value in [false, true, 0, 1, '0', '1']) {
    test('reads follow=$value from the season user status envelope', () async {
      transport.response = _response({'follow': value});
      expect(await client.isFollowed(_season), [true, 1, '1'].contains(value));
      expect(transport.uri?.host, 'api.bilibili.com');
      expect(transport.uri?.path, '/pgc/view/web/season/user/status');
      expect(transport.uri?.queryParameters, {'season_id': _season});
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
    });
  }

  for (final value in [null, 2, 'true', {}, []]) {
    test(
      'invalid follow state $value cannot become an unfollowed state',
      () async {
        transport.response = _response({'follow': value});
        await expectLater(
          client.isFollowed(_season),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
      },
    );
  }

  for (final followed in [true, false]) {
    test('follow=$followed posts one scoped Cookie and CSRF form', () async {
      transport.response = _response({'toast': 'fixture'});
      await client.setFollowed(_season, followed);
      expect(transport.posts, 1);
      expect(
        transport.uri?.path,
        followed ? '/pgc/web/follow/add' : '/pgc/web/follow/del',
      );
      expect(transport.fields, {'season_id': _season, 'csrf': 'fixture-csrf'});
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      expect(transport.headers['Origin'], 'https://www.bilibili.com');
    });
  }

  for (final response in [
    _response(null, status: 503),
    ApiHttpResponse(200, Uint8List.fromList(utf8.encode('broken')), const {}),
    _response(null, code: -101),
  ]) {
    test(
      'failed mutation never retries (${response.statusCode}, ${response.body.length})',
      () async {
        transport.response = response;
        await expectLater(
          client.setFollowed(_season, true),
          throwsA(isA<ApiFailure>()),
        );
        expect(transport.posts, 1);
      },
    );
  }

  test(
    'missing credentials prevents a write before reaching transport',
    () async {
      api.cookieJar.clear();
      await expectLater(
        client.setFollowed(_season, true),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
      expect(transport.posts, 0);
    },
  );

  test('invalid season identifiers never reach transport', () async {
    for (final id in ['', '0', '-1', 'ss42', '42&ep_id=1']) {
      await expectLater(client.isFollowed(id), throwsArgumentError);
      await expectLater(client.setFollowed(id, true), throwsArgumentError);
    }
    expect(transport.uri, isNull);
  });

  test('cancelled mutation drops a late success without replaying', () async {
    final cancellation = ApiCancellation();
    transport.pending = Completer<ApiHttpResponse>();
    final result = client.setFollowed(
      _season,
      true,
      context: ApiRequestContext(cancellation: cancellation),
    );
    final check = expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    cancellation.cancel();
    transport.pending!.complete(_response(null));
    await check;
    expect(transport.posts, 1);
  });
}

class _Transport implements ApiTransport, ApiFormTransport {
  ApiHttpResponse response = _response(null);
  Completer<ApiHttpResponse>? pending;
  int posts = 0;
  Uri? uri;
  Map<String, String> fields = {}, headers = {};
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.headers = headers;
    return response;
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    posts++;
    return pending?.future ?? response;
  }
}
