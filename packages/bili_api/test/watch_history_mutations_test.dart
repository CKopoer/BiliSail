import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiHttpResponse response({int status = 200, int code = 0}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': null}))),
  const {},
);

void main() {
  late _Transport transport;
  late BiliApiClient api;
  late _Session session;
  setUp(() {
    transport = _Transport();
    session = _Session();
    api = BiliApiClient(
      transport: transport,
      sessionProvider: session,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]),
    );
  });
  tearDown(() => api.close());

  for (final business in [
    'archive',
    'pgc',
    'live',
    'article',
    'article-list',
    'cheese',
  ]) {
    test('delete $business uses the root kid and scoped CSRF once', () async {
      await WatchHistoryClient(api).delete('${business}_9007199254740993123');
      expect(
        transport.uri?.toString(),
        'https://api.bilibili.com/x/v2/history/delete',
      );
      expect(transport.fields, {
        'kid': '${business}_9007199254740993123',
        'jsonp': 'jsonp',
        'csrf': 'fixture-csrf',
      });
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      expect(transport.posts, 1);
    });
  }
  test('clear uses the official clear endpoint once', () async {
    await WatchHistoryClient(api).clear();
    expect(transport.uri?.path, '/x/v2/history/clear');
    expect(transport.fields, {'jsonp': 'jsonp', 'csrf': 'fixture-csrf'});
    expect(transport.posts, 1);
  });
  test('invalid deletion identities cannot reach the transport', () async {
    for (final key in [
      'BV1234567890',
      'archive_0',
      'pgc_1.5',
      'archive_1&kid=2',
      'future_1',
    ]) {
      await expectLater(
        WatchHistoryClient(api).delete(key),
        throwsArgumentError,
      );
    }
    expect(transport.posts, 0);
  });
  for (final clear in [false, true]) {
    Future<void> write({ApiRequestContext? context}) => clear
        ? WatchHistoryClient(api).clear(context: context)
        : WatchHistoryClient(api).delete('archive_42', context: context);
    for (final failure in [response(status: 503), response(code: -101)]) {
      test('${clear ? 'clear' : 'delete'} failure is never retried', () async {
        transport.result = failure;
        await expectLater(write(), throwsA(isA<ApiFailure>()));
        expect(transport.posts, 1);
      });
    }
    test(
      '${clear ? 'clear' : 'delete'} missing scoped credentials prevents writes',
      () async {
        api.cookieJar.clear();
        await expectLater(write(), throwsA(isA<ApiFailure>()));
        expect(transport.posts, 0);
      },
    );
    test(
      '${clear ? 'clear' : 'delete'} cancellation and expired deadline prevent writes',
      () async {
        final cancellation = ApiCancellation()..cancel();
        await expectLater(
          write(context: ApiRequestContext(cancellation: cancellation)),
          throwsA(isA<ApiFailure>()),
        );
        await expectLater(
          write(context: ApiRequestContext(deadline: DateTime(2000))),
          throwsA(isA<ApiFailure>()),
        );
        expect(transport.posts, 0);
      },
    );
    test(
      '${clear ? 'clear' : 'delete'} rejects a late response after session changes',
      () async {
        transport.pending = Completer<ApiHttpResponse>();
        final pending = write(
          context: ApiRequestContext(sessionEpoch: session.sessionEpoch),
        );
        final assertion = expectLater(
          pending,
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.cancelled,
            ),
          ),
        );
        session.sessionEpoch++;
        transport.pending?.complete(response());
        await assertion;
        expect(transport.posts, 1);
      },
    );
  }
}

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  ApiHttpResponse result = response();
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
  }) => throw StateError('unexpected read');
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
    return pending?.future ?? result;
  }
}
