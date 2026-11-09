import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

class _Transport
    implements
        ApiTransport,
        ApiJsonTransport,
        ApiFormTransport,
        ApiMultipartTransport {
  final calls = <({Uri uri, Object? body, Map<String, String> headers})>[];
  int code = 0, status = 200;
  Object? data = {'dyn_id_str': '9007199254740993123'};
  ApiHttpResponse result() => ApiHttpResponse(
    status,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
    {},
  );
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add((uri: uri, body: null, headers: headers));
    return result();
  }

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add((uri: uri, body: body, headers: headers));
    return result();
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add((uri: uri, body: fields, headers: headers));
    return result();
  }

  @override
  Future<ApiHttpResponse> postMultipart(
    Uri uri, {
    required Map<String, String> fields,
    required Uint8List bytes,
    required String mimeType,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add((uri: uri, body: fields, headers: headers));
    return result();
  }
}

void main() {
  late _Transport transport;
  late BiliApiClient api;
  late DynamicPublishClient client;
  setUp(() {
    transport = _Transport();
    api = BiliApiClient(
      transport: transport,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Domain=.bilibili.com; Secure',
          'bili_jct=fixture-csrf; Path=/; Domain=.bilibili.com; Secure',
        ]),
    );
    client = DynamicPublishClient(api);
  });

  test(
    'text publishing sends a single JSON creation with exact text and topic identity',
    () async {
      final id = await client.create(
        mid: '7',
        text: '文本 &+=%/#😀',
        topic: const ApiDynamicComposeTopic('9007199254740993123', '话题'),
      );
      expect(id, '9007199254740993123');
      final call = transport.calls.single;
      expect(call.uri.path, '/x/dynamic/feed/create/dyn');
      expect(call.uri.queryParameters, {
        'platform': 'web',
        'csrf': 'fixture-csrf',
      });
      expect(call.headers['Cookie'], contains('SESSDATA=fixture'));
      final body = call.body as Map<String, Object?>;
      final request = body['dyn_req'] as Map<String, Object?>;
      expect(request['scene'], 1);
      expect(request['content'], {
        'contents': [
          {'raw_text': '文本 &+=%/#😀', 'type': 1, 'biz_id': ''},
        ],
      });
      expect(request['topic'], {
        'id': 9007199254740993123,
        'name': '话题',
        'from_source': 'dyn.web.list',
        'from_topic_id': 0,
      });
      expect(request['upload_id'], matches(r'^7_[0-9]+_[0-9]{4}$'));
      expect(body.containsKey('web_repost_src'), isFalse);
    },
  );

  test(
    'picture-only posts use scene 2 and the uploaded dimensions/size',
    () async {
      transport.data = {
        'image_url': '//i0.hdslb.com/bfs/new_dyn/a.png',
        'image_width': 20,
        'image_height': 30,
      };
      final picture = await client.upload(
        Uint8List.fromList([1, 2, 3]),
        'image/png',
      );
      expect(transport.calls.single.body, {
        'category': 'daily',
        'biz': 'new_dyn',
        'csrf': 'fixture-csrf',
      });
      transport.data = {'dyn_id': '123'};
      expect(
        await client.create(mid: '7', text: '', pictures: [picture]),
        '123',
      );
      final request = ((transport.calls.last.body as Map)['dyn_req'] as Map);
      expect(request['scene'], 2);
      expect(request['pics'], [
        {
          'img_src': 'https://i0.hdslb.com/bfs/new_dyn/a.png',
          'img_width': 20,
          'img_height': 30,
          'img_size': 3 / 1024,
        },
      ]);
    },
  );

  test(
    'topic search encodes keyword once and maps public topic identities',
    () async {
      transport.data = {
        'topic_items': [
          {'id': '9007199254740993123', 'name': 'C# & 话题'},
          {'id': 1.5, 'name': 'invalid'},
        ],
      };
      final items = await client.topics('C# &%=话题');
      expect(
        (items.single.id, items.single.name),
        ('9007199254740993123', 'C# & 话题'),
      );
      expect(transport.calls.single.uri.host, 'app.bilibili.com');
      expect(
        transport.calls.single.uri.queryParameters['keywords'],
        'C# &%=话题',
      );
    },
  );

  test(
    'topic favorite, cancellation and report use authenticated single-attempt forms',
    () async {
      transport.data = null;
      final topics = DynamicTopicClient(api);
      await topics.favorite('12', true);
      await topics.favorite('12', false);
      await topics.report('12', '广告：说明 &+=%/#');
      expect(transport.calls.map((c) => c.uri.path), [
        '/x/topic/fav/sub/add',
        '/x/topic/fav/sub/cancel',
        '/x/topic/report',
      ]);
      expect(transport.calls.last.body, {
        'topic_id': '12',
        'reason': '广告：说明 &+=%/#',
        'csrf': 'fixture-csrf',
      });
    },
  );

  test(
    'invalid drafts, images and guest writes never reach the transport',
    () async {
      await expectLater(client.create(mid: '7', text: ''), throwsArgumentError);
      await expectLater(
        client.create(mid: '7', text: '😀' * 1001),
        throwsArgumentError,
      );
      await expectLater(
        client.create(
          mid: '7',
          text: 'x',
          pictures: List.generate(
            10,
            (_) => ApiDynamicPicture(Uri.https('i0.hdslb.com', '/a'), 1, 1, 1),
          ),
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.create(
          mid: '7',
          text: 'x',
          pictures: [ApiDynamicPicture(Uri.https('evil.test', '/a'), 1, 1, 1)],
        ),
        throwsArgumentError,
      );
      await expectLater(
        client.upload(Uint8List(0), 'image/png'),
        throwsArgumentError,
      );
      await expectLater(
        DynamicPublishClient(
          BiliApiClient(transport: transport),
        ).create(mid: '7', text: 'x'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.calls, isEmpty);
    },
  );

  for (final failure in ['http', 'protocol', 'business']) {
    test('a $failure creation failure is never retried', () async {
      if (failure == 'http') transport.status = 503;
      if (failure == 'business') transport.code = -412;
      if (failure == 'protocol') transport.data = {};
      await expectLater(
        client.create(mid: '7', text: 'x'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.calls, hasLength(1));
    });
  }

  test('a malformed upload response never returns a usable picture', () async {
    for (final url in [
      'https://evil.test/a',
      'https://i0.hdslb.com/a?secret=x',
    ]) {
      transport.data = {'image_url': url, 'image_width': 1, 'image_height': 1};
      await expectLater(
        client.upload(Uint8List.fromList([1]), 'image/png'),
        throwsA(isA<ApiFailure>()),
      );
    }
  });
}
