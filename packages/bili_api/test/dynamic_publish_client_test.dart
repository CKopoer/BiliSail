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
    'poll images use the vote upload business and preserve metadata',
    () async {
      transport.data = {
        'image_url': '//i0.hdslb.com/bfs/vote/a.png',
        'image_width': 20,
        'image_height': 30,
      };
      final picture = await client.upload(
        Uint8List.fromList([1, 2, 3]),
        'image/png',
        forPoll: true,
      );
      expect((picture.width, picture.height), (20, 30));
      expect(transport.calls.single.body, {
        'category': 'daily',
        'biz': 'vote',
        'csrf': 'fixture-csrf',
      });
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
            19,
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
  test(
    'rich content and all publishing settings use the Web request contract',
    () async {
      final time = DateTime.now().add(const Duration(hours: 1));
      await client.create(
        mid: '7',
        text: '@用户[doge]投票',
        title: '可选标题',
        contents: const [
          ApiDynamicContent('@用户', 2, id: '9007199254740993123'),
          ApiDynamicContent('[doge]', 9),
          ApiDynamicContent('投票', 4, id: '123'),
        ],
        publishAt: time,
        replyPolicy: 2,
        reserveId: '456',
      );
      final req = (transport.calls.single.body as Map)['dyn_req'] as Map;
      expect(req['content'], {
        'title': '可选标题',
        'contents': [
          {'raw_text': '@用户', 'type': 2, 'biz_id': '9007199254740993123'},
          {'raw_text': '[doge]', 'type': 9, 'biz_id': ''},
          {'raw_text': '投票', 'type': 4, 'biz_id': '123'},
        ],
      });
      expect(req['option'], {
        'up_choose_comment': 1,
        'timer_pub_time': time.millisecondsSinceEpoch ~/ 1000,
      });
      expect(req['attach_card'], {
        'common_card': {
          'type': 14,
          'biz_id': 456,
          'reserve_source': 0,
          'reserve_lottery': 0,
        },
      });
      transport.calls.clear();
      await client.create(mid: '7', text: '私密', onlySelf: true, replyPolicy: 1);
      expect(
        ((transport.calls.single.body as Map)['dyn_req'] as Map)['option'],
        {'private_pub': 1, 'close_comment': 1},
      );
    },
  );
  test(
    '18 pictures are allowed while invalid rich identities and scheduling never write',
    () async {
      final images = List.generate(
        18,
        (_) => ApiDynamicPicture(Uri.https('i0.hdslb.com', '/a'), 1, 1, 1),
      );
      await client.create(mid: '7', text: '', pictures: images);
      expect(
        ((transport.calls.single.body as Map)['dyn_req'] as Map)['pics'],
        hasLength(18),
      );
      transport.calls.clear();
      for (final contents in [
        const [ApiDynamicContent('@x', 2)],
        const [ApiDynamicContent('@x', 9)],
      ]) {
        await expectLater(
          client.create(mid: '7', text: 'different', contents: contents),
          throwsArgumentError,
        );
      }
      await expectLater(
        client.create(mid: '7', text: 'x', publishAt: DateTime.now()),
        throwsArgumentError,
      );
      await expectLater(
        client.create(
          mid: '7',
          text: 'x',
          onlySelf: true,
          publishAt: DateTime.now().add(const Duration(days: 1)),
        ),
        throwsArgumentError,
      );
      expect(transport.calls, isEmpty);
    },
  );
  test(
    'mention search retains exact large IDs, encodes once and deduplicates groups',
    () async {
      transport.data = {
        'groups': [
          {
            'items': [
              {
                'uid': '9007199254740993123',
                'name': '名字',
                'face': '//i0.hdslb.com/a.png',
              },
              {'uid': 1.2, 'name': '无效'},
              {'uid': '9007199254740993123', 'name': '名字'},
            ],
          },
        ],
      };
      final items = await client.mentions('名字 &+=%/#');
      expect(items.single.id, '9007199254740993123');
      expect(
        transport.calls.single.uri.queryParameters['keyword'],
        '名字 &+=%/#',
      );
    },
  );
  test(
    'poll and live reservation create exactly once with CSRF and validated metadata',
    () async {
      transport.data = {'vote_id': '9007199254740993123'};
      final id = await client.createPoll(
        mid: '7',
        title: '图片投票',
        maxChoices: 2,
        endsAt: DateTime.now().add(const Duration(days: 1)),
        options: [
          ApiDynamicPollOption('一', imageUrl: Uri.https('i0.hdslb.com', '/a')),
          ApiDynamicPollOption('二', imageUrl: Uri.https('i0.hdslb.com', '/b')),
        ],
      );
      expect(id, '9007199254740993123');
      final info = (transport.calls.single.body as Map)['vote_info'] as Map;
      expect(
        (info['type'], info['choice_cnt'], info['vote_publisher']),
        (1, 2, 7),
      );
      expect(transport.calls.single.uri.path, '/x/vote/create');
      expect(
        transport.calls.single.uri.queryParameters['csrf'],
        'fixture-csrf',
      );
      transport.data = {'sid': '456'};
      final time = DateTime.now().add(const Duration(days: 1));
      expect(
        await client.createReserve(
          title: '直播 &+=',
          startsAt: time,
          onlyMembers: true,
        ),
        '456',
      );
      expect(transport.calls.last.uri.path, '/x/new-reserve/up/reserve/create');
      expect(transport.calls.last.body, {
        'title': '直播 &+=',
        'type': '2',
        'sub_type': '1',
        'from': '1',
        'live_plan_start_time': '${time.millisecondsSinceEpoch ~/ 1000}',
        'csrf': 'fixture-csrf',
      });
      transport.status = 503;
      await expectLater(
        client.createReserve(title: 'x', startsAt: time),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.calls, hasLength(3));
    },
  );
}
