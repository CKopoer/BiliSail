import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/pgc/data/api_pgc_danmaku_repository.dart';
import 'package:bilisail/features/pgc/domain/pgc_danmaku_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const target = (
    episodeId: '7',
    video: VideoId('BV1234567890'),
    cid: '9007199254740993',
  );
  test('PGC send reuses Web CSRF and does not need an archive aid', () async {
    final transport = _Transport();
    final requests = ApiRequests();
    final repository = _repository(transport, requests);
    await repository.send(
      target,
      '中文 & + %',
      const Duration(milliseconds: 12345),
      mode: 5,
      color: 0x123456,
      cancellation: RequestCancellation(),
    );
    expect(transport.posts, 1);
    expect(transport.path, '/x/v2/dm/post');
    expect(transport.fields['oid'], target.cid);
    expect(transport.fields['bvid'], target.video.value);
    expect(transport.fields['msg'], '中文 & + %');
    expect(transport.fields['progress'], '12345');
    expect(transport.fields['mode'], '5');
    expect(transport.fields['csrf'], 'fixture-csrf');
    expect(repository.sessionEpoch, requests.sessionEpoch);
  });
  test(
    'uncertain HTTP write is sent once and is never automatic success',
    () async {
      final transport = _Transport()..status = 503;
      await expectLater(
        _repository(transport, ApiRequests()).send(
          target,
          'fixture',
          Duration.zero,
          mode: 1,
          color: 0xffffff,
          cancellation: RequestCancellation(),
        ),
        throwsA(isA<PgcDanmakuWriteUncertain>()),
      );
      expect(transport.posts, 1);
    },
  );
  test(
    'a cancelled write is silent cancellation, not an uncertain send',
    () async {
      final transport = _Transport();
      final cancellation = RequestCancellation()..cancel();
      await expectLater(
        _repository(transport, ApiRequests()).send(
          target,
          'fixture',
          Duration.zero,
          mode: 1,
          color: 0xffffff,
          cancellation: cancellation,
        ),
        throwsA(
          isA<AppFailure>().having(
            (e) => e.kind,
            'kind',
            AppFailureKind.cancelled,
          ),
        ),
      );
      expect(transport.posts, 0);
    },
  );
}

ApiPgcDanmakuRepository _repository(
  _Transport transport,
  ApiRequests requests,
) {
  final jar = ApiCookieJar()
    ..receive(Uri.https('api.bilibili.com', '/'), [
      'SESSDATA=fixture-session; Path=/; Secure',
      'bili_jct=fixture-csrf; Path=/; Secure',
    ]);
  return ApiPgcDanmakuRepository(
    VideoActionsClient(
      BiliApiClient(
        transport: transport,
        sessionProvider: requests,
        cookieJar: jar,
      ),
    ),
    requests,
    accountScope: () => 'user:1',
  );
}

final class _Transport implements ApiTransport, ApiFormTransport {
  int posts = 0, status = 200;
  String? path;
  Map<String, String> fields = {};
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => throw StateError('PGC send must not read UGC interaction state');
  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    path = uri.path;
    this.fields = fields;
    return ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': null}))),
      {},
    );
  }
}
