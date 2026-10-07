import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'cancelling the first WBI waiter does not cancel another recommendation',
    () async {
      final transport = _Transport();
      final client = BiliApiClient(transport: transport);
      final cancellation = ApiCancellation();
      final first = client.getRecommended(
        context: ApiRequestContext(cancellation: cancellation),
      );
      final second = client.getRecommended();
      final cancelled = expectLater(first, throwsA(_cancelled));
      expect(transport.keys, hasLength(1));
      cancellation.cancel();
      transport.keys.single.result.complete(_keys());
      await cancelled;
      expect((await second).items.single.title, '推荐视频');
      expect(transport.keys.single.cancellation?.isCancelled, isFalse);
      expect(transport.recommendations, 1);
      client.close();
    },
  );

  test(
    'new session gets its own WBI flight before the old one completes',
    () async {
      final transport = _Transport();
      final session = _Session();
      final client = BiliApiClient(
        transport: transport,
        sessionProvider: session,
      );
      final first = client.getRecommended(
        context: const ApiRequestContext(sessionEpoch: 0),
      );
      final cancelled = expectLater(first, throwsA(_cancelled));
      session.sessionEpoch++;
      final second = client.getRecommended(
        context: const ApiRequestContext(sessionEpoch: 1),
      );
      expect(transport.keys, hasLength(2));
      transport.keys.first.result.complete(_keys());
      await cancelled;
      // Old-flight cleanup must not clear the new flight or start a third nav.
      final third = client.getRecommended(
        context: const ApiRequestContext(sessionEpoch: 1),
      );
      expect(transport.keys, hasLength(2));
      transport.keys.last.result.complete(_keys());
      final results = await Future.wait([second, third]);
      expect(results.every((result) => result.items.isNotEmpty), isTrue);
      expect(transport.recommendations, 2);
      client.close();
    },
  );

  test('cancelled WBI waiter completes without waiting for nav', () async {
    final transport = _Transport();
    final client = BiliApiClient(transport: transport);
    final cancellation = ApiCancellation();
    final read = client.getRecommended(
      context: ApiRequestContext(cancellation: cancellation),
    );
    final cancelled = expectLater(read, throwsA(_cancelled));
    cancellation.cancel();
    await cancelled;
    transport.keys.single.result.complete(_keys());
    await client.getRecommended();
    expect(transport.keys, hasLength(1));
    client.close();
  });

  test('stale request cannot start WBI nav in a new session', () async {
    final transport = _Transport();
    final session = _Session()..sessionEpoch = 1;
    final client = BiliApiClient(
      transport: transport,
      sessionProvider: session,
    );
    await expectLater(
      client.getRecommended(context: const ApiRequestContext(sessionEpoch: 0)),
      throwsA(_cancelled),
    );
    expect(transport.keys, isEmpty);
    client.close();
  });

  test(
    'one waiter deadline does not expire shared keys for other callers',
    () async {
      var now = DateTime.utc(2026, 10, 7);
      final transport = _Transport();
      final client = BiliApiClient(transport: transport, clock: () => now);
      final first = client.getRecommended(
        context: ApiRequestContext(
          deadline: now.add(const Duration(seconds: 1)),
        ),
      );
      final expired = expectLater(
        first,
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.category,
            'category',
            ApiFailureCategory.timeout,
          ),
        ),
      );
      final second = client.getRecommended();
      now = now.add(const Duration(seconds: 2));
      transport.keys.single.result.complete(_keys());
      await expired;
      expect((await second).items.single.title, '推荐视频');
      await client.getRecommended();
      expect(transport.keys, hasLength(1));
      expect(transport.recommendations, 2);
      client.close();
    },
  );

  test('failed WBI flight is cleared for a later explicit read', () async {
    final transport = _Transport();
    final client = BiliApiClient(transport: transport);
    final first = client.getRecommended();
    final failed = expectLater(
      first,
      throwsA(
        isA<ApiFailure>().having(
          (failure) => failure.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
    transport.keys.single.result.complete(_response({'code': 0, 'data': {}}));
    await failed;
    final retry = client.getRecommended();
    expect(transport.keys, hasLength(2));
    transport.keys.last.result.complete(_keys());
    expect((await retry).items.single.title, '推荐视频');
    client.close();
  });

  test('closing the client cancels shared nav and its waiters', () async {
    final transport = _Transport();
    final client = BiliApiClient(transport: transport);
    final read = client.getRecommended();
    final cancelled = expectLater(read, throwsA(_cancelled));
    client.close();
    await cancelled;
    expect(transport.keys.single.cancellation?.isCancelled, isTrue);
    // The transport can still complete late; its error stays observed.
    transport.keys.single.result.complete(_keys());
    await Future<void>.delayed(Duration.zero);
    expect(transport.recommendations, 0);
  });
}

final _cancelled = isA<ApiFailure>().having(
  (failure) => failure.category,
  'category',
  ApiFailureCategory.cancelled,
);

class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

class _Transport implements ApiTransport {
  final keys =
      <({ApiCancellation? cancellation, Completer<ApiHttpResponse> result})>[];
  int recommendations = 0;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path.endsWith('/nav')) {
      final result = Completer<ApiHttpResponse>();
      keys.add((cancellation: cancellation, result: result));
      final response = await result.future;
      if (cancellation?.isCancelled == true) {
        throw const ApiFailure(ApiFailureCategory.cancelled, 'nav');
      }
      return response;
    }
    expect(uri.path, '/x/web-interface/index/top/feed/rcmd');
    recommendations++;
    return _response({
      'code': 0,
      'data': {
        'item': [
          {
            'bvid': 'BV1234567890',
            'title': '推荐视频',
            'duration': 60,
            'owner': {'name': '测试 UP'},
          },
        ],
      },
    });
  }
}

ApiHttpResponse _keys() => _response({
  'code': -101,
  'data': {
    'wbi_img': {
      'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
      'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
    },
  },
});

ApiHttpResponse _response(Object value) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode(value))),
  const {},
);
