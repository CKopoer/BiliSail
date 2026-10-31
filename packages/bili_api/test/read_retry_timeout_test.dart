import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final bounded in [false, true]) {
    test('${bounded ? 'bounded' : 'Web'} read cancels a stalled attempt '
        'and succeeds with a fresh attempt', () async {
      final stalled = Completer<ApiHttpResponse>();
      final transport = _Transport((_, index) async {
        if (index == 0) return stalled.future;
        return _response({'attempt': 2});
      });
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final cancellation = ApiCancellation();
      final context = ApiRequestContext(
        cancellation: cancellation,
        deadline: DateTime.now().add(const Duration(seconds: 25)),
      );

      final result = await (bounded
          ? api.requestAppJson(
              '/x/v2/feed/index',
              const {},
              endpoint: 'app_recommended',
              buvid: 'a' * 32,
              context: context,
            )
          : api.requestJson(
              Uri.https('api.bilibili.com', '/x/v3/fav/folder/created/list'),
              'profile_folders',
              context: context,
            ));

      expect(result, {'attempt': 2});
      expect(transport.attempts, hasLength(2));
      expect(transport.attempts.map((a) => a.timeout), [
        const Duration(seconds: 2),
        const Duration(seconds: 2),
      ]);
      expect(transport.attempts.first.cancellation.isCancelled, isTrue);
      expect(transport.attempts.last.cancellation.isCancelled, isFalse);
      expect(
        identical(
          transport.attempts.first.cancellation,
          transport.attempts.last.cancellation,
        ),
        isFalse,
      );
      expect(
        transport.attempts.first.maxBytes,
        bounded ? 2 * 1024 * 1024 : null,
      );
      expect(cancellation.isCancelled, isFalse);

      // A transport that completes after cancellation must not affect success
      // or emit an unhandled asynchronous error.
      stalled.completeError(
        const ApiFailure(ApiFailureCategory.network, 'late'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(transport.attempts, hasLength(2));
      cancellation.cancel();
      await Future<void>.delayed(Duration.zero);
      expect(transport.attempts.last.cancellation.isCancelled, isFalse);
    });
  }

  test(
    'three stalled reads time out without exhausting the 25 second budget',
    () async {
      final transport = _Transport(
        (_, _) => Completer<ApiHttpResponse>().future,
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final cancellation = ApiCancellation();

      await expectLater(
        api.getPopular(
          context: ApiRequestContext(
            cancellation: cancellation,
            deadline: DateTime.now().add(const Duration(seconds: 25)),
          ),
        ),
        throwsA(_failure(ApiFailureCategory.timeout)),
      );
      expect(transport.attempts, hasLength(3));
      expect(
        transport.attempts.every(
          (a) => a.timeout == const Duration(seconds: 2),
        ),
        isTrue,
      );
      expect(
        transport.attempts.every((a) => a.cancellation.isCancelled),
        isTrue,
      );
      expect(cancellation.isCancelled, isFalse);
    },
  );

  test(
    'remaining total deadline caps an attempt and prevents another read',
    () async {
      final transport = _Transport(
        (_, _) => Completer<ApiHttpResponse>().future,
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(
        api.getPopular(
          context: ApiRequestContext(
            deadline: DateTime.now().add(const Duration(milliseconds: 250)),
          ),
        ),
        throwsA(_failure(ApiFailureCategory.timeout)),
      );
      expect(transport.attempts, hasLength(1));
      expect(
        transport.attempts.single.timeout,
        lessThanOrEqualTo(const Duration(milliseconds: 250)),
      );
      expect(transport.attempts.single.cancellation.isCancelled, isTrue);
    },
  );

  test(
    'retries keep the original deadline instead of resetting the budget',
    () async {
      final start = DateTime.utc(2026, 10, 31);
      var now = start;
      final transport = _Transport((_, index) async {
        now = start.add(Duration(seconds: index == 0 ? 24 : 25));
        if (index == 0) return ApiHttpResponse(503, Uint8List(0), const {});
        throw const ApiFailure(ApiFailureCategory.timeout, 'transport');
      });
      final api = BiliApiClient(transport: transport, clock: () => now);
      addTearDown(api.close);

      await expectLater(
        api.getPopular(
          context: ApiRequestContext(
            deadline: start.add(const Duration(seconds: 25)),
          ),
        ),
        throwsA(_failure(ApiFailureCategory.timeout)),
      );
      expect(transport.attempts.map((a) => a.timeout), [
        const Duration(seconds: 2),
        const Duration(seconds: 1),
      ]);
    },
  );

  test(
    'caller cancellation interrupts a stalled read without retrying',
    () async {
      final transport = _Transport(
        (_, _) => Completer<ApiHttpResponse>().future,
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final cancellation = ApiCancellation();
      final result = api.getPopular(
        context: ApiRequestContext(cancellation: cancellation),
      );
      final cancelled = expectLater(
        result,
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      cancellation.cancel();
      expect(transport.attempts.single.cancellation.isCancelled, isTrue);
      await cancelled;
      expect(transport.attempts, hasLength(1));
      expect(transport.attempts.single.cancellation.isCancelled, isTrue);
    },
  );

  test(
    'caller cancellation during backoff prevents the next attempt',
    () async {
      final transport = _Transport(
        (_, _) async => ApiHttpResponse(503, Uint8List(0), const {}),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final cancellation = ApiCancellation();
      final timer = Timer(
        const Duration(milliseconds: 50),
        cancellation.cancel,
      );
      addTearDown(timer.cancel);
      await expectLater(
        api.getPopular(context: ApiRequestContext(cancellation: cancellation)),
        throwsA(_failure(ApiFailureCategory.cancelled)),
      );
      expect(transport.attempts, hasLength(1));
    },
  );

  test('GET mutations keep their full budget and are never replayed', () async {
    final transport = _Transport(
      (_, _) async => ApiHttpResponse(503, Uint8List(0), const {}),
    );
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    await expectLater(
      api.requestAppJson(
        '/x/feed/dislike',
        const {},
        endpoint: 'app_dislike',
        buvid: 'a' * 32,
        accessToken: 'test-token',
        context: ApiRequestContext(
          deadline: DateTime.now().add(const Duration(seconds: 25)),
        ),
      ),
      throwsA(_failure(ApiFailureCategory.http)),
    );
    expect(transport.attempts, hasLength(1));
    expect(
      transport.attempts.single.timeout,
      greaterThan(const Duration(seconds: 24)),
    );
    expect(
      transport.attempts.single.timeout,
      lessThanOrEqualTo(const Duration(seconds: 25)),
    );
  });
}

Matcher _failure(ApiFailureCategory category) => isA<ApiFailure>().having(
  (failure) => failure.category,
  'category',
  category,
);

ApiHttpResponse _response(Map<String, Object?> data) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

final class _Attempt {
  const _Attempt(this.timeout, this.cancellation, this.maxBytes);
  final Duration timeout;
  final ApiCancellation cancellation;
  final int? maxBytes;
}

final class _Transport implements ApiTransport, ApiBoundedTransport {
  _Transport(this.handler);
  final Future<ApiHttpResponse> Function(_Attempt, int) handler;
  final attempts = <_Attempt>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => _send(timeout, cancellation, null);

  @override
  Future<ApiHttpResponse> getBounded(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    required int maxBytes,
    ApiCancellation? cancellation,
  }) => _send(timeout, cancellation, maxBytes);

  Future<ApiHttpResponse> _send(
    Duration timeout,
    ApiCancellation? cancellation,
    int? maxBytes,
  ) {
    final attempt = _Attempt(timeout, cancellation!, maxBytes);
    attempts.add(attempt);
    return handler(attempt, attempts.length - 1);
  }
}
