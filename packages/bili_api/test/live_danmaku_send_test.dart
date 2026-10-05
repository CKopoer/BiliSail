import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiHttpResponse _response({int code = 0, String message = '', Object? data}) =>
    ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({'code': code, 'message': message, 'data': data}),
        ),
      ),
      {},
    );

void main() {
  test(
    'live writes use host-scoped cookies, raw fields and one CSRF post',
    () async {
      final transport = _Transport();
      final cookies =
          ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
            'bili_jct=fixture-csrf; Domain=.bilibili.com; Path=/; Secure',
          ]);
      final api = BiliApiClient(transport: transport, cookieJar: cookies);
      final client = LiveClient(api);
      await client.sendDanmaku('9007199254740993', '中文 &+=%/#');
      expect(transport.uri?.host, 'api.live.bilibili.com');
      expect(transport.uri?.path, '/msg/send');
      expect(transport.fields['roomid'], '9007199254740993');
      expect(transport.fields['msg'], '中文 &+=%/#');
      expect(transport.fields['dm_type'], '0');
      expect(transport.fields['csrf'], 'fixture-csrf');
      expect(transport.fields['csrf_token'], 'fixture-csrf');
      expect(transport.headers['Origin'], 'https://live.bilibili.com');
      expect(transport.headers['Referer'], 'https://live.bilibili.com/');
      await client.sendDanmaku('12', '[干杯]', emoticonUnique: 'room_12_1');
      expect(transport.fields['msg'], 'room_12_1');
      expect(transport.fields['dm_type'], '1');
      expect(transport.posts, 2);
      expect(
        () => api.submitLiveForm('/x/v2/dm/post', 'invalid', {}),
        throwsArgumentError,
      );
    },
  );

  test('host-only video cookies never authorize live writes', () async {
    final transport = _Transport();
    final cookies =
        ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]);
    await expectLater(
      LiveClient(
        BiliApiClient(transport: transport, cookieJar: cookies),
      ).sendDanmaku('12', 'hello'),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.category,
          'category',
          ApiFailureCategory.authentication,
        ),
      ),
    );
    expect(transport.posts, 0);
  });

  test(
    'timeout, rate limit and code-zero rejection never replay or succeed',
    () async {
      final transport = _Transport();
      final cookies =
          ApiCookieJar()..receive(Uri.https('api.live.bilibili.com', '/'), [
            'SESSDATA=fixture; Path=/; Secure',
            'bili_jct=fixture-csrf; Path=/; Secure',
          ]);
      final client = LiveClient(
        BiliApiClient(transport: transport, cookieJar: cookies),
      );
      transport.error = TimeoutException('fixture');
      await expectLater(
        client.sendDanmaku('12', 'hello'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
      transport.error = null;
      transport.result = _response(code: 10031);
      await expectLater(
        client.sendDanmaku('12', 'hello'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.rateLimited,
          ),
        ),
      );
      transport.result = _response(message: 'fixture rejection');
      await expectLater(
        client.sendDanmaku('12', 'hello'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.permission,
          ),
        ),
      );
      expect(transport.posts, 3);
      final cancellation = ApiCancellation()..cancel();
      await expectLater(
        client.sendDanmaku(
          '12',
          'hello',
          context: ApiRequestContext(cancellation: cancellation),
        ),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 3);
    },
  );

  test(
    'emoticon mapping preserves locks and bounds packages and items',
    () async {
      final transport = _Transport();
      transport.result = _response(
        data: {
          'data': [
            {
              'pkg_name': '房间表情',
              'emoticons': [
                {
                  'emoticon_unique': 'room_12_1',
                  'emoji': '[干杯]',
                  'width': 100,
                  'perm': 1,
                  'url': 'http://i0.hdslb.com/bfs/live/fixture.png',
                },
                {
                  'emoticon_unique': 'locked',
                  'emoji': '[锁定]',
                  'width': 100,
                  'perm': 0,
                  'unlock_show_text': '需要粉丝等级',
                },
                {
                  'emoticon_unique': 'text',
                  'emoji': '[笑]',
                  'width': 0,
                  'perm': 1,
                },
              ],
            },
          ],
        },
      );
      final client = LiveClient(BiliApiClient(transport: transport));
      final packages = await client.getEmoticons('12');
      expect(transport.uri?.queryParameters, {
        'room_id': '12',
        'platform': 'pc',
      });
      expect(packages.single.items.first.isSticker, isTrue);
      expect(packages.single.items.first.imageUrl?.scheme, 'https');
      expect(packages.single.items[1].allowed, isFalse);
      expect(packages.single.items[1].unlockHint, '需要粉丝等级');
      expect(packages.single.items.last.isSticker, isFalse);
      transport.result = _response(
        data: {
          'data': List.generate(
            40,
            (_) => {
              'emoticons': List.generate(
                600,
                (_) => {'emoji': 'text', 'perm': 1},
              ),
            },
          ),
        },
      );
      final bounded = await client.getEmoticons('12');
      expect(bounded.expand((package) => package.items).length, 500);
    },
  );
}

final class _Transport implements ApiTransport, ApiFormTransport {
  Uri? uri;
  Map<String, String> fields = {}, headers = {};
  int posts = 0;
  Object? error;
  ApiHttpResponse result = _response();
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    return result;
  }

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
    if (error case final error?) throw error;
    return result;
  }
}
