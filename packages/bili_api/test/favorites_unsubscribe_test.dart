import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _id = '9007199254740993123';

void main() {
  for (final collection in [false, true]) {
    test(
      'unsubscribe collection=$collection sends one scoped CSRF form',
      () async {
        final transport = _Transport();
        await _client(
          transport,
        ).unsubscribeFavorite(_id, collection: collection);
        expect(transport.posts, 1);
        expect(
          transport.uri,
          Uri.https(
            'api.bilibili.com',
            collection ? '/x/v3/fav/season/unfav' : '/x/v3/fav/folder/unfav',
          ),
        );
        expect(transport.fields, {
          if (collection) ...{
            'season_id': _id,
            'platform': 'web',
          } else
            'media_id': _id,
          'csrf': 'fixture-csrf',
        });
        expect(
          transport.headers['Cookie'],
          contains('SESSDATA=fixture-session'),
        );
        expect(transport.headers['Origin'], 'https://www.bilibili.com');
        expect(transport.headers['Referer'], 'https://www.bilibili.com/');
      },
    );
  }

  for (final code in [-101, -111, -403, -352]) {
    test('unsubscribe business failure $code is never retried', () async {
      final transport = _Transport()..response = _response(code: code);
      await expectLater(
        _client(transport).unsubscribeFavorite(_id, collection: true),
        throwsA(isA<ApiFailure>().having((e) => e.businessCode, 'code', code)),
      );
      expect(transport.posts, 1);
    });
  }

  for (final error in [
    const ApiFailure(ApiFailureCategory.network, 'fixture'),
    TimeoutException('fixture'),
  ]) {
    test('unknown ${error.runtimeType} result is never replayed', () async {
      final transport = _Transport()..error = error;
      await expectLater(
        _client(transport).unsubscribeFavorite(_id, collection: false),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
    });
  }

  test('unsubscribe HTTP 503 is a single failed attempt', () async {
    final transport = _Transport()..response = _response(status: 503);
    await expectLater(
      _client(transport).unsubscribeFavorite(_id, collection: true),
      throwsA(isA<ApiFailure>().having((e) => e.httpStatus, 'status', 503)),
    );
    expect(transport.posts, 1);
  });

  test('missing or wrong-scope credentials prevent the write', () async {
    final transport = _Transport();
    for (final jar in [
      ApiCookieJar(),
      ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture-session; Path=/; Secure',
      ]),
      ApiCookieJar()..receive(Uri.https('passport.bilibili.com', '/'), [
        'SESSDATA=fixture-session; Path=/; Secure',
        'bili_jct=fixture-csrf; Path=/; Secure',
      ]),
    ]) {
      await expectLater(
        HomeClient(
          BiliApiClient(transport: transport, cookieJar: jar),
        ).unsubscribeFavorite(_id, collection: true),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
    }
    expect(transport.posts, 0);
  });

  test(
    'invalid ID, cancelled context and expired deadline never post',
    () async {
      final transport = _Transport();
      final client = _client(transport);
      for (final id in ['ugc:42', '0', '-1', '1.0', '42&season_id=7']) {
        await expectLater(
          client.unsubscribeFavorite(id, collection: true),
          throwsArgumentError,
        );
      }
      await expectLater(
        client.unsubscribeFavorite(
          _id,
          collection: true,
          context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      await expectLater(
        client.unsubscribeFavorite(
          _id,
          collection: false,
          context: ApiRequestContext(deadline: DateTime.utc(2000)),
        ),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.timeout,
          ),
        ),
      );
      expect(transport.posts, 0);
    },
  );

  test('late success after session epoch changes is cancelled', () async {
    final transport = _Transport()..pending = Completer<ApiHttpResponse>();
    final session = _Session();
    final api = BiliApiClient(
      transport: transport,
      cookieJar: _cookies(),
      sessionProvider: session,
    );
    final result = HomeClient(api).unsubscribeFavorite(
      _id,
      collection: true,
      context: const ApiRequestContext(sessionEpoch: 1),
    );
    final expectation = expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    session.epoch++;
    transport.pending?.complete(_response());
    await expectation;
    expect(transport.posts, 1);
  });
}

HomeClient _client(_Transport transport) =>
    HomeClient(BiliApiClient(transport: transport, cookieJar: _cookies()));

ApiCookieJar _cookies() =>
    ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
      'SESSDATA=fixture-session; Path=/; Secure',
      'bili_jct=fixture-csrf; Path=/; Secure',
    ]);

ApiHttpResponse _response({int code = 0, int status = 200}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': null}))),
  const {},
);

final class _Session implements ApiSessionProvider {
  int epoch = 1;
  @override
  int get sessionEpoch => epoch;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  int posts = 0;
  Uri? uri;
  Map<String, String> fields = {};
  Map<String, String> headers = {};
  Object? error;
  ApiHttpResponse response = _response();
  Completer<ApiHttpResponse>? pending;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => throw StateError('Unsubscription must not issue a GET');
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    if (error case final failure?) throw failure;
    if (pending case final operation?) return await operation.future;
    return response;
  }
}
