import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const dyn = '9007199254740993123';
Map<String, Object?> post() => {
  'id_str': dyn,
  'type': 'DYNAMIC_TYPE_DRAW',
  'basic': {'comment_id_str': '456', 'comment_type': 11},
  'modules': {
    'module_author': {
      'mid': 7,
      'name': '自己',
      'is_top': true,
      'icon_badge': {'text': '仅自己可见'},
    },
    'module_dynamic': {
      'major': {
        'type': 'MAJOR_TYPE_OPUS',
        'opus': {
          'title': '标题',
          'summary': {
            'text': '@名字[doge]投票',
            'rich_text_nodes': [
              {
                'type': 'RICH_TEXT_NODE_TYPE_AT',
                'text': '@名字',
                'rid': '9007199254740993124',
              },
              {
                'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
                'text': '[doge]',
                'emoji': {'icon_url': 'https://i0.hdslb.com/a.png'},
              },
              {'type': 'RICH_TEXT_NODE_TYPE_VOTE', 'text': '投票', 'rid': '123'},
            ],
          },
          'pics': [
            {
              'url': 'https://i0.hdslb.com/bfs/a.png',
              'width': 20,
              'height': 30,
            },
          ],
        },
      },
      'topic': {'id': 99, 'name': '话题'},
    },
  },
};
Map<String, Object?> poll() => {
  'vote_id': '123',
  'title': '投票',
  'desc': '说明',
  'end_time':
      DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/
      1000,
  'choice_cnt': 2,
  'join_num': 9,
  'vote_publisher': '9007199254740993124',
  'options': [
    {
      'opt_idx': 1,
      'opt_desc': '一',
      'cnt': 6,
      'img_url': '//i0.hdslb.com/a.png',
    },
    {'opt_idx': 2, 'opt_desc': '二', 'cnt': 3},
  ],
};

class Transport implements ApiTransport, ApiJsonTransport, ApiFormTransport {
  final calls = <({Uri uri, Object? body, Map<String, String> headers})>[];
  int status = 200;
  Object? Function(Uri)? data;
  ApiHttpResponse response(Uri uri) => ApiHttpResponse(
    status,
    Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'code': 0,
          'data':
              data?.call(uri) ??
              switch (uri.path) {
                '/x/polymer/web-dynamic/v1/detail' => {'item': post()},
                '/x/v2/reply/subject/interaction-status' => {
                  'up_reply_selection': {'can_modify': true, 'status': 1},
                  'up_reply': {'can_modify': true, 'status': 0},
                },
                '/x/web-interface/nav' => {
                  'wbi_img': {
                    'img_url':
                        'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                    'sub_url':
                        'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
                  },
                },
                '/x/vote/vote_info' => {
                  'vote_info': poll(),
                  'my_votes': [2],
                },
                '/x/vote/do_vote' => {'vote_info': poll()},
                '/vote_svr/v1/vote_svr/followee_votes' => {
                  'votes': [
                    {
                      'uid': '9007199254740993124',
                      'name': '关注的人',
                      'votes': [1],
                    },
                  ],
                },
                _ => null,
              },
        }),
      ),
    ),
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
    return response(uri);
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
    return response(uri);
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
    return response(uri);
  }
}

void main() {
  late Transport transport;
  late BiliApiClient api;
  setUp(() {
    transport = Transport();
    api = BiliApiClient(
      transport: transport,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
          'bili_jct=fixture-csrf; Domain=.bilibili.com; Path=/; Secure',
        ]),
    );
  });
  test(
    'management writes preserve exact identity, request encoding, CSRF and single attempts',
    () async {
      final client = DynamicClient(api);
      await client.remove(dyn);
      await client.pin(dyn, true);
      await client.pin(dyn, false);
      await client.visibility(dyn, true);
      await client.report(dyn, '8', 4, '说明 &+=%/#');
      await client.setInteraction('456', 11, 3);
      expect(transport.calls.map((c) => c.uri.path), [
        '/x/dynamic/feed/operate/remove',
        '/x/dynamic/feed/space/set_top',
        '/x/dynamic/feed/space/rm_top',
        '/x/dynamic/feed/dyn/private_pub_setting',
        '/x/dynamic/feed/dynamic_report/add',
        '/x/v2/reply/subject/modify',
      ]);
      expect(transport.calls.first.body, {'dyn_id_str': dyn});
      expect(transport.calls[1].body, {'dyn_str': dyn});
      expect(transport.calls[1].uri.queryParameters['csrf'], 'fixture-csrf');
      expect(transport.calls[3].body, {
        'object_id': jsonEncode({'dyn_id': dyn}),
        'action': 'private_pub',
      });
      expect((transport.calls[4].body as Map)['reason_desc'], '说明 &+=%/#');
      expect(transport.calls.last.body, {
        'oid': '456',
        'type': '11',
        'action': '3',
        'csrf': 'fixture-csrf',
      });
      transport.calls.clear();
      transport.status = 503;
      await expectLater(client.remove(dyn), throwsA(isA<ApiFailure>()));
      expect(transport.calls, hasLength(1));
    },
  );
  test(
    'draft reads preserve permissions, rich identities, and existing picture metadata',
    () async {
      final client = DynamicClient(api);
      final d = await client.editDraft(dyn);
      expect(d, isNotNull);
      expect(d!.authorId, '7');
      expect(d.onlySelf, true);
      expect(d.replyPolicy, 1);
      expect(d.contents.map((c) => (c.type, c.id)), [
        (2, '9007199254740993124'),
        (9, ''),
        (4, '123'),
      ]);
      expect(d.pictures.single.width, 20);
      expect(d.pictures.single.sizeKiB, 0);
      final parsed = await client.detail(dyn);
      expect(
        (parsed.pinned, parsed.onlySelf, parsed.editable),
        (true, true, true),
      );
      expect(parsed.spans.last.linkUrl!.queryParameters, {
        'vote_id': '123',
        'dynamic_id': dyn,
      });
    },
  );
  test(
    'editing signs Web parameters and sends one mutation without creating a new dynamic',
    () async {
      final client = DynamicPublishClient(api);
      expect(
        await client.create(
          mid: '7',
          text: '@名字[doge]投票',
          title: '新标题',
          editId: dyn,
          repostId: '789',
          contents: const [
            ApiDynamicContent('@名字', 2, id: '9007199254740993124'),
            ApiDynamicContent('[doge]', 9),
            ApiDynamicContent('投票', 4, id: '123'),
          ],
          pictures: [
            ApiDynamicPicture(Uri.https('i0.hdslb.com', '/a.png'), 20, 30, 0),
          ],
        ),
        dyn,
      );
      final writes = transport.calls.where((c) => c.body != null).toList();
      expect(writes, hasLength(1));
      final call = writes.single;
      expect(call.uri.path, '/x/dynamic/feed/edit/dyn');
      expect(call.uri.queryParameters['w_rid'], matches(r'^[0-9a-f]{32}$'));
      expect(call.uri.queryParameters['csrf'], 'fixture-csrf');
      final body = call.body as Map;
      expect(body['dyn_id_str'], dyn);
      expect(body['web_repost_src'], {'dyn_id_str': '789'});
      final req = body['dyn_req'] as Map;
      expect(req['upload_id'], call.uri.queryParameters['w_dyn_req.upload_id']);
      expect(req['scene'], 4);
      expect((req['pics'] as List).single, {
        'img_src': 'https://i0.hdslb.com/a.png',
        'img_width': 20,
        'img_height': 30,
      });
    },
  );
  test(
    'public visibility check sends no account cookies and validates returned identity',
    () async {
      expect(await DynamicClient(api).publicVisible(dyn), true);
      expect(transport.calls.single.headers['Cookie'], isNull);
      expect(
        api.cookieJar.headerFor(Uri.https('api.bilibili.com', '/')),
        contains('SESSDATA=fixture'),
      );
    },
  );
  test(
    'poll loads choices, own votes, long publisher ID and followee votes',
    () async {
      final client = DynamicPollClient(api);
      final p = await client.detail('123');
      expect(p.myVotes, {2});
      expect(p.authorId, '9007199254740993124');
      expect(p.options.first.imageUrl, Uri.https('i0.hdslb.com', '/a.png'));
      final friends = await client.followees('123');
      expect(friends.single.id, '9007199254740993124');
      expect(transport.calls.last.uri.host, 'api.vc.bilibili.com');
    },
  );
  test(
    'anonymous vote includes source dynamic, voter and both CSRF body fields exactly once',
    () async {
      final p = await DynamicPollClient(api).vote(
        id: '123',
        voterId: '7',
        choices: [1, 2],
        anonymous: true,
        dynamicId: dyn,
      );
      expect(p.myVotes, {1, 2});
      final call = transport.calls.single;
      expect(call.uri.path, '/x/vote/do_vote');
      expect(call.uri.queryParameters, {'csrf': 'fixture-csrf'});
      expect(call.body, {
        'vote_id': 123,
        'votes': [1, 2],
        'voter_uid': 7,
        'status': 1,
        'op_bit': 0,
        'dynamic_id': 9007199254740993123,
        'csrf': 'fixture-csrf',
        'csrf_token': 'fixture-csrf',
      });
    },
  );
  test(
    'invalid choices and report descriptions never write; unknown vote result is not retried',
    () async {
      final client = DynamicPollClient(api);
      for (final choices in [
        <int>[],
        [1, 1],
        [-1],
      ]) {
        await expectLater(
          client.vote(
            id: '123',
            voterId: '7',
            choices: choices,
            anonymous: false,
          ),
          throwsArgumentError,
        );
      }
      await expectLater(
        DynamicClient(api).report(dyn, '8', 0, ''),
        throwsArgumentError,
      );
      expect(transport.calls, isEmpty);
      transport.status = 503;
      await expectLater(
        client.vote(id: '123', voterId: '7', choices: [1], anonymous: false),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.calls, hasLength(1));
    },
  );
  test(
    'malformed poll identity, duplicate options and invalid own selections fail closed',
    () async {
      for (final data in [
        {...poll(), 'vote_id': '124'},
        {...poll(), 'choice_cnt': 4},
        {
          ...poll(),
          'options': [
            {'opt_idx': 1, 'opt_desc': '一'},
            {'opt_idx': 1, 'opt_desc': '二'},
          ],
        },
      ]) {
        transport.data = (_) => {'vote_info': data, 'my_votes': []};
        await expectLater(
          DynamicPollClient(api).detail('123'),
          throwsA(isA<ApiFailure>()),
        );
      }
      transport.data = (_) => {
        'vote_info': poll(),
        'my_votes': [99],
      };
      await expectLater(
        DynamicPollClient(api).detail('123'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test(
    'dynamic message sharing uses a typed Web share card rather than a text message',
    () async {
      await MessageClient(api).shareDynamic(
        '7',
        '8',
        id: dyn,
        title: '正文 &+=',
        author: '作者',
        authorId: '9',
        source: 11,
      );
      final body = transport.calls.single.body as Map;
      expect(body['msg[msg_type]'], '7');
      expect(jsonDecode(body['msg[content]'] as String), {
        'id': dyn,
        'title': '正文 &+=',
        'headline': '',
        'source': 11,
        'author': '作者',
        'author_id': '9',
      });
      expect(body['csrf'], 'fixture-csrf');
    },
  );
}
