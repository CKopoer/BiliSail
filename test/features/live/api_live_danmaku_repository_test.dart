import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bili_lite/core/network/api_requests.dart';
import 'package:bili_lite/domain/app_failure.dart';
import 'package:bili_lite/domain/request_cancellation.dart';
import 'package:bili_lite/features/live/data/api_live_danmaku_repository.dart';
import 'package:bili_lite/features/live/domain/live_danmaku_repository.dart';
import 'package:bili_lite/features/live/domain/live_room.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'network outcomes are uncertain while business rejections are known',
    () async {
      final transport = _Transport();
      final repository = _repository(transport, ApiRequests());
      transport.error = const ApiFailure(
        ApiFailureCategory.network,
        'live_danmaku_send',
      );
      await expectLater(
        repository.send(
          const RoomId('12'),
          'hello',
          cancellation: RequestCancellation(),
        ),
        throwsA(isA<LiveDanmakuWriteUncertain>()),
      );
      expect(transport.posts, 1);
      transport.error = null;
      transport.code = 10031;
      await expectLater(
        repository.send(
          const RoomId('12'),
          'hello',
          cancellation: RequestCancellation(),
        ),
        throwsA(
          isA<AppFailure>().having(
            (error) => error.kind,
            'kind',
            AppFailureKind.rateLimited,
          ),
        ),
      );
      expect(transport.posts, 2);
    },
  );

  test('account transition cancels a pending write instead of adopting its response', () async {
    final transport = _Transport();
    final requests = ApiRequests();
    final repository = _repository(transport, requests);
    transport.pending = Completer<ApiHttpResponse>();
    final sending = repository.send(
      const RoomId('12'),
      'hello',
      cancellation: RequestCancellation(),
    );
    final assertion = expectLater(
      sending,
      throwsA(
        isA<AppFailure>().having(
          (error) => error.kind,
          'kind',
          AppFailureKind.cancelled,
        ),
      ),
    );
    requests.advanceSession();
    expect(transport.cancellation?.isCancelled, true);
    transport.pending!.complete(transport.response);
    await assertion;
    expect(transport.posts, 1);
  });
}

ApiLiveDanmakuRepository _repository(
  _Transport transport,
  ApiRequests requests,
) {
  final cookies = ApiCookieJar()
    ..receive(Uri.https('api.live.bilibili.com', '/'), [
      'SESSDATA=fixture; Path=/; Secure',
      'bili_jct=fixture; Path=/; Secure',
    ]);
  return ApiLiveDanmakuRepository(
    LiveClient(
      BiliApiClient(
        transport: transport,
        cookieJar: cookies,
        sessionProvider: requests,
      ),
    ),
    requests,
    accountScope: () => 'user:1',
  );
}

final class _Transport implements ApiTransport, ApiFormTransport {
  int posts = 0, code = 0;
  Object? error;
  ApiCancellation? cancellation;
  Completer<ApiHttpResponse>? pending;
  ApiHttpResponse get response => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': {}}))),
    {},
  );
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => response;
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    this.cancellation = cancellation;
    if (error case final error?) throw error;
    return pending == null ? response : await pending!.future;
  }
}
