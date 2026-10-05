import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiHttpResponse response(Object? data, {int status = 200}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  {},
);
ApiCookieJar cookies() =>
    ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
      'SESSDATA=fixture-session; Path=/; Secure',
      'bili_jct=fixture-csrf; Path=/; Secure',
    ]);
void main() {
  test('comment writes require CSRF, retain targets and never retry', () async {
    final transport = _Transport();
    final api = BiliApiClient(transport: transport, cookieJar: cookies());
    await api.likeVideoComment('42', '9007199254740993', true);
    expect(transport.uri?.path, '/x/v2/reply/action');
    expect(transport.fields['action'], '1');
    expect(transport.fields['csrf'], 'fixture-csrf');
    transport.result = response({
      'reply': {
        'rpid_str': '9007199254740994',
        'root_str': '9007199254740993',
        'member': {'uname': 'Fixture'},
        'content': {'message': 'raw &+=%/#'},
      },
    });
    final added = await api.addVideoComment(
      '42',
      'raw &+=%/#',
      rootId: '9007199254740993',
    );
    expect(added.rootId, '9007199254740993');
    expect(transport.fields['message'], 'raw &+=%/#');
    expect(transport.fields['parent'], '9007199254740993');
    transport.result = response(null, status: 503);
    await expectLater(
      api.likeVideoComment('42', added.id, false),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 3);
    await expectLater(
      BiliApiClient(transport: transport).addVideoComment('42', 'hello'),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 3);
  });

  test('action parameters retain IDs, milliseconds and raw text', () async {
    final transport = _Transport();
    final client = VideoActionsClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
    await client.favorite('9007199254740993', ['11', '12'], ['13']);
    expect(transport.fields, {
      'rid': '9007199254740993',
      'type': '2',
      'add_media_ids': '11,12',
      'del_media_ids': '13',
      'csrf': 'fixture-csrf',
    });
    await client.sendDanmaku(
      'BV1234567890',
      '9007199254740993',
      '测试 & % +',
      const Duration(milliseconds: 12345),
      mode: 5,
      color: 0x123456,
    );
    expect(transport.fields['oid'], '9007199254740993');
    expect(transport.fields['msg'], '测试 & % +');
    expect(transport.fields['progress'], '12345');
    expect(transport.fields['mode'], '5');
    expect(transport.fields['color'], '${0x123456}');
    await client.like('BV1234567890', false);
    expect(transport.fields['like'], '2');
    expect(transport.posts, 3);
  });

  test(
    'CSRF comes from scoped cookie jar and caller cannot override it',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport, cookieJar: cookies());
      await api.submitForm('/x/v2/dm/post', 'test', {
        'msg': '中文 &+=%/#',
        'csrf': 'wrong',
      });
      expect(transport.fields['csrf'], 'fixture-csrf');
      expect(transport.fields['msg'], '中文 &+=%/#');
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture-session'));
      expect(transport.headers['Cookie'], contains('bili_jct=fixture-csrf'));
      expect(transport.uri?.scheme, 'https');
    },
  );
  test('missing or wrong-domain credentials reject before transport', () async {
    for (final jar in [
      ApiCookieJar(),
      ApiCookieJar()..receive(Uri.https('live.bilibili.com', '/'), [
        'SESSDATA=fixture; Path=/; Secure',
        'bili_jct=fixture; Path=/; Secure',
      ]),
    ]) {
      final transport = _Transport();
      final client = VideoActionsClient(
        BiliApiClient(transport: transport, cookieJar: jar),
      );
      await expectLater(
        client.like('BV1234567890', true),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
      expect(transport.posts, 0);
    }
  });
  for (final category in [
    ApiFailureCategory.network,
    ApiFailureCategory.timeout,
  ]) {
    test('$category writes are sent once', () async {
      final transport = _Transport()..error = ApiFailure(category, 'transport');
      final client = VideoActionsClient(
        BiliApiClient(transport: transport, cookieJar: cookies()),
      );
      await expectLater(
        client.watchLater('BV1234567890'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
    });
  }
  for (final status in [500, 302]) {
    test('HTTP $status mutation is not replayed', () async {
      final transport = _Transport()..result = response(null, status: status);
      final client = VideoActionsClient(
        BiliApiClient(transport: transport, cookieJar: cookies()),
      );
      await expectLater(
        client.coin('BV1234567890', 2),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
      expect(transport.fields['multiply'], '2');
      expect(transport.fields['select_like'], '0');
    });
  }
  test('late POST response is rejected after session epoch changes', () async {
    final session = _Session();
    final transport = _Transport()..pending = Completer<ApiHttpResponse>();
    final api = BiliApiClient(
      transport: transport,
      cookieJar: cookies(),
      sessionProvider: session,
    );
    final future = VideoActionsClient(api).like('BV1234567890', true);
    session.epoch++;
    transport.pending!.complete(response(null));
    await expectLater(
      future,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    expect(transport.posts, 1);
  });
  test('state and folders parse typed values and preserve large IDs', () async {
    final transport = _Transport();
    final client = VideoActionsClient(BiliApiClient(transport: transport));
    final state = await client.loadState('BV1234567890', '42');
    expect(state.liked, true);
    expect(state.coins, 2);
    expect(state.favorited, false);
    final folders = await client.folders('1', '42');
    expect(folders.single.id, '9007199254740993');
    expect(folders.single.containsVideo, true);
    expect(transport.gets.last.queryParameters, {
      'up_mid': '1',
      'rid': '42',
      'type': '2',
    });
  });
  test('Dio form encodes once and never follows redirect', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final bodies = <String>[];
    final subscription = server.listen((request) async {
      bodies.add(await utf8.decoder.bind(request).join());
      request.response.statusCode = 302;
      request.response.headers.set(
        'location',
        'http://127.0.0.1:${server.port}/redirected',
      );
      await request.response.close();
    });
    final transport = DioApiTransport();
    addTearDown(() async {
      transport.close();
      await subscription.cancel();
      await server.close(force: true);
    });
    final result = await transport.postForm(
      Uri.parse('http://127.0.0.1:${server.port}/post'),
      fields: {'msg': '中文 &+=%/#', 'csrf': 'fixture'},
      headers: {},
      timeout: const Duration(seconds: 2),
    );
    expect(result.statusCode, 302);
    expect(bodies.length, 1);
    expect(Uri.splitQueryString(bodies.single), {
      'msg': '中文 &+=%/#',
      'csrf': 'fixture',
    });
  });
}

final class _Session implements ApiSessionProvider {
  int epoch = 1;
  @override
  int get sessionEpoch => epoch;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  int posts = 0;
  final gets = <Uri>[];
  Uri? uri;
  Map<String, String> fields = {};
  Map<String, String> headers = {};
  Object? error;
  Completer<ApiHttpResponse>? pending;
  ApiHttpResponse result = response(null);
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    gets.add(uri);
    return response(switch (uri.path) {
      '/x/web-interface/archive/has/like' => 1,
      '/x/web-interface/archive/coins' => {'multiply': 2},
      '/x/v2/fav/video/favoured' => {'favoured': false},
      _ => {
        'list': [
          {'id': '9007199254740993', 'title': '收藏夹', 'fav_state': 1},
        ],
      },
    });
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
    if (error case final Object e) throw e;
    return pending == null ? result : await pending!.future;
  }
}
