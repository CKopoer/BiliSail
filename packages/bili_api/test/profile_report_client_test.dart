import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show Transport, cookies, response;

ApiHttpResponse _status(Object? root) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode(root))),
  const {},
);

void main() {
  late Transport transport;
  late ProfileClient client;
  setUp(() {
    transport = Transport()..postResult = _status({'status': true});
    client = ProfileClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
  });

  test(
    'space report preserves ID, sorted fields, optional reason and CSRF',
    () async {
      await client.report('9007199254740993123', contents: {3, 1}, reason: 6);
      expect(
        transport.uri,
        Uri.https('space.bilibili.com', '/ajax/report/add'),
      );
      expect(transport.fields, {
        'mid': '9007199254740993123',
        'reason': '1,3',
        'reason_v2': '6',
        'csrf': 'csrf-fixture',
      });
      expect(transport.headers['Origin'], 'https://space.bilibili.com');
      expect(
        transport.headers['Referer'],
        'https://space.bilibili.com/9007199254740993123/',
      );
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      await client.report('7', contents: {2});
      expect(transport.fields.containsKey('reason_v2'), false);
      expect(transport.posts, 2);
    },
  );
  for (final (root, category) in <(Object?, ApiFailureCategory)>[
    (
      {'status': false, 'message': 'private server text'},
      ApiFailureCategory.unavailable,
    ),
    ({'code': -101, 'status': false}, ApiFailureCategory.authentication),
    ({'code': -352}, ApiFailureCategory.rateLimited),
    ({'code': 0, 'status': false}, ApiFailureCategory.unavailable),
    ({'code': 0}, ApiFailureCategory.protocol),
    ({'status': 'true'}, ApiFailureCategory.protocol),
    ({'status': 1}, ApiFailureCategory.protocol),
    ({}, ApiFailureCategory.protocol),
    ([], ApiFailureCategory.protocol),
  ]) {
    test(
      'rejection or invalid status $root never succeeds or retries',
      () async {
        transport.postResult = _status(root);
        await expectLater(
          client.report('7', contents: {1}),
          throwsA(
            isA<ApiFailure>().having((e) => e.category, 'category', category),
          ),
        );
        expect(transport.posts, 1);
      },
    );
  }
  test('malformed JSON and HTTP failures never retry', () async {
    transport.postResult = ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode('<html>')),
      const {},
    );
    await expectLater(
      client.report('7', contents: {1}),
      throwsA(isA<ApiFailure>()),
    );
    transport.postResult = response(null, status: 503);
    await expectLater(
      client.report('7', contents: {1}),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 2);
  });
  test('host-only credentials cannot leak to space', () async {
    client = ProfileClient(
      BiliApiClient(
        transport: transport,
        cookieJar: cookies(domain: 'api.bilibili.com'),
      ),
    );
    await expectLater(
      client.report('7', contents: {1}),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 0);
  });
  test(
    'invalid selections, cancelled and expired requests never send',
    () async {
      for (final contents in <Set<int>>[
        {},
        {0},
        {4},
        {1, 2, 4},
      ]) {
        await expectLater(
          client.report('7', contents: contents),
          throwsArgumentError,
        );
      }
      for (final reason in [0, 7]) {
        await expectLater(
          client.report('7', contents: {1}, reason: reason),
          throwsArgumentError,
        );
      }
      await expectLater(
        client.report('1e10', contents: {1}),
        throwsArgumentError,
      );
      await expectLater(
        client.report(
          '7',
          contents: {1},
          context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
        ),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        client.report(
          '7',
          contents: {1},
          context: ApiRequestContext(deadline: DateTime(2000)),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 0);
    },
  );
  for (final cancel in [false, true]) {
    test(
      'late report completion is rejected after ${cancel ? 'cancellation' : 'epoch change'}',
      () async {
        final pending = Completer<ApiHttpResponse>();
        final session = _Session();
        final signal = ApiCancellation();
        final transport = _PendingTransport(pending);
        final client = ProfileClient(
          BiliApiClient(
            transport: transport,
            cookieJar: cookies(),
            sessionProvider: session,
          ),
        );
        final result = expectLater(
          client.report(
            '7',
            contents: {1},
            context: ApiRequestContext(cancellation: signal, sessionEpoch: 1),
          ),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.cancelled,
            ),
          ),
        );
        if (cancel) {
          signal.cancel();
        } else {
          session.sessionEpoch++;
        }
        pending.complete(_status({'status': true}));
        await result;
        expect(transport.posts, 1);
      },
    );
  }
}

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

final class _PendingTransport implements ApiTransport, ApiFormTransport {
  _PendingTransport(this.pending);
  final Completer<ApiHttpResponse> pending;
  int posts = 0;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => throw UnimplementedError();
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) {
    posts++;
    return pending.future;
  }
}
