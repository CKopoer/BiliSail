import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class DynamicTransport implements ApiTransport {
  DynamicTransport(this.items);
  final List<Object?> items;
  final List<Uri> requests = [];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': {'items': items, 'has_more': false},
          }),
        ),
      ),
      {},
    );
  }
}

Map<String, Object?> post({
  String id = '900719925474099312345',
  List<Object?> nodes = const [],
  Map<String, Object?> major = const {},
  Object? original,
}) => {
  'id_str': id,
  'type': 'DYNAMIC_TYPE_FORWARD',
  'orig': ?original,
  'modules': {
    'module_author': {
      'mid': '900719925474099312346',
      'name': '作者',
      'pub_time': '今天',
      'pub_action': '发布了动态',
    },
    'module_dynamic': {
      'desc': {'text': '回退正文', 'rich_text_nodes': nodes},
      'major': major,
    },
    'module_stat': {
      'forward': {'count': 3},
      'comment': {'count': '4'},
      'like': {'count': -1},
    },
  },
};
void main() {
  for (final home in [true, false]) {
    for (final opus in [true, false]) {
      test(
        '${home ? 'home' : 'space'} ${opus ? 'opus' : 'draw'} keeps valid picture ratios',
        () async {
          final pictures = [
            {
              'src': '//i0.hdslb.com/landscape.png',
              'width': 2400,
              'height': 1600,
            },
            {
              'src': '//i0.hdslb.com/portrait.png',
              'width': '1600',
              'height': '2400',
            },
            {'src': '//i0.hdslb.com/long.png', 'width': 400, 'height': 4000},
            {'src': '//i0.hdslb.com/missing.png'},
            {'src': '//i0.hdslb.com/zero.png', 'width': 0, 'height': 100},
            {'src': '//i0.hdslb.com/negative.png', 'width': 100, 'height': -1},
            {'src': '//i0.hdslb.com/nan.png', 'width': 'NaN', 'height': 100},
            {
              'src': '//i0.hdslb.com/infinite.png',
              'width': 'Infinity',
              'height': 100,
            },
            {
              'src': '//i0.hdslb.com/overflow.png',
              'width': 1e308,
              'height': 1e-308,
            },
          ];
          final api = BiliApiClient(
            transport: DynamicTransport([
              post(
                major: {
                  if (opus)
                    'opus': {'pics': pictures}
                  else
                    'draw': {'items': pictures},
                },
              ),
            ]),
          );
          final value = home
              ? (await HomeClient(api).load(
                  channel: 'dynamic',
                  section: '全部',
                  page: 1,
                )).items.single.dynamicPost
              : (await ProfileClient(
                  api,
                ).loadDynamics('2')).items.single.dynamicPost;
          expect(value, isNotNull);
          expect(value!.imageUrls, hasLength(9));
          expect(value.imageAspectRatios, {
            Uri.parse('https://i0.hdslb.com/landscape.png'): 1.5,
            Uri.parse('https://i0.hdslb.com/portrait.png'): 2 / 3,
            Uri.parse('https://i0.hdslb.com/long.png'): .1,
          });
          expect(() => value.imageAspectRatios.clear(), throwsUnsupportedError);
        },
      );
    }
  }
  for (final home in [true, false]) {
    test(
      '${home ? 'all' : 'space'} selects opus rich summary over placeholder desc',
      () async {
        for (final placeholderNodes in [
          null,
          <Object?>[],
          <Object?>[{}],
        ]) {
          final item = {
            'id_str': '14',
            'type': 'DYNAMIC_TYPE_DRAW',
            'modules': {
              'module_dynamic': {
                'desc': {'text': '', 'rich_text_nodes': placeholderNodes},
                'major': {
                  'type': 'MAJOR_TYPE_OPUS',
                  'none': null,
                  'opus': {
                    'title': '图文标题',
                    'summary': {
                      'text': '图文正文\n第二行[表情]',
                      'rich_text_nodes': [
                        {
                          'type': 'RICH_TEXT_NODE_TYPE_TEXT',
                          'text': '图文正文\n第二行',
                        },
                        {
                          'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
                          'text': '[表情]',
                          'emoji': {
                            'icon_url': '//i0.hdslb.com/emoji.png',
                            'size': 2,
                          },
                        },
                      ],
                    },
                    'pics': [
                      {'src': '//i0.hdslb.com/pic.png'},
                    ],
                  },
                },
              },
            },
          };
          final transport = DynamicTransport([item]);
          final api = BiliApiClient(transport: transport);
          final value = home
              ? (await HomeClient(api).load(
                  channel: 'dynamic',
                  section: '全部',
                  page: 1,
                )).items.single.dynamicPost
              : (await ProfileClient(
                  api,
                ).loadDynamics('2')).items.single.dynamicPost;
          expect(value?.text, '图文正文\n第二行[表情]');
          expect(value?.title, '图文标题');
          expect(value?.linkTitle, isEmpty);
          expect(
            transport.requests.single.queryParameters['features'],
            'itemOpusStyle',
          );
          expect(value?.spans.length, 2);
          expect(value?.spans.last.kind, ApiDynamicTextKind.emoji);
          expect(value?.spans.last.emojiSize, 2);
          expect(value?.imageUrls.length, 1);
          expect(value?.unavailable, false);
        }
      },
    );
  }

  for (final home in [true, false]) {
    test(
      '${home ? 'all' : 'space'} ignores null none union members for normal content',
      () async {
        final nodes = [
          {'type': 'RICH_TEXT_NODE_TYPE_TEXT', 'text': '正常正文'},
          {
            'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
            'text': '[表情]',
            'emoji': {'icon_url': '//i0.hdslb.com/emoji.png', 'size': 1},
          },
        ];
        final archive = post(
          id: '11',
          nodes: nodes,
          major: {
            'type': 'MAJOR_TYPE_ARCHIVE',
            'none': null,
            'archive': {'bvid': 'BV1234567890', 'title': '视频'},
          },
        );
        final draw = post(
          id: '12',
          nodes: nodes,
          major: {
            'type': 'MAJOR_TYPE_DRAW',
            'none': null,
            'draw': {
              'items': [
                {'src': '//i0.hdslb.com/draw.png'},
              ],
            },
          },
        );
        final opus = {
          'id_str': '13',
          'type': 'DYNAMIC_TYPE_DRAW',
          'orig': null,
          'modules': {
            'module_dynamic': {
              'desc': null,
              'major': {
                'type': 'MAJOR_TYPE_OPUS',
                'none': null,
                'opus': {
                  'summary': {'text': '正常正文[表情]', 'rich_text_nodes': nodes},
                  'pics': [
                    {'src': '//i0.hdslb.com/opus.png'},
                  ],
                },
              },
            },
          },
        };
        final api = BiliApiClient(
          transport: DynamicTransport([archive, draw, opus]),
        );
        final List<ApiDynamicPost?> posts = home
            ? (await HomeClient(api).load(
                channel: 'dynamic',
                section: '全部',
                page: 1,
              )).items.map((e) => e.dynamicPost).toList()
            : (await ProfileClient(
                api,
              ).loadDynamics('2')).items.map((e) => e.dynamicPost).toList();
        for (final value in posts) {
          expect(value?.unavailable, false);
          expect(value?.original, isNull);
          expect(value?.text, '正常正文[表情]');
          expect(value?.spans.last.kind, ApiDynamicTextKind.emoji);
        }
        expect(posts[0]?.video?.bvid, 'BV1234567890');
        expect(posts[1]?.imageUrls.length, 1);
        expect(posts[2]?.imageUrls.length, 1);
      },
    );
  }

  for (final home in [true, false]) {
    test(
      '${home ? 'all' : 'space'} preserves ordered rich nodes and bounded images',
      () async {
        final t = DynamicTransport([
          post(
            nodes: [
              {'type': 'RICH_TEXT_NODE_TYPE_TEXT', 'text': '前'},
              {
                'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
                'text': '[大]',
                'emoji': {'icon_url': 'http://i0.hdslb.com/e.png', 'size': 2},
              },
              {
                'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
                'text': '[坏]',
                'emoji': {'icon_url': 'javascript:alert(1)'},
              },
              {'type': 'UNKNOWN', 'text': '未知'},
              {'type': 'RICH_TEXT_NODE_TYPE_AT', 'text': '@用户', 'rid': '123'},
              {
                'type': 'RICH_TEXT_NODE_TYPE_TOPIC',
                'text': '#话题#',
                'rid': '456',
              },
              {
                'type': 'RICH_TEXT_NODE_TYPE_WEB',
                'text': '链接',
                'jump_url': 'file:///secret',
              },
            ],
            major: {
              'draw': {
                'items': List.generate(
                  12,
                  (i) => {'src': '//i0.hdslb.com/$i.jpg'},
                ),
              },
            },
          ),
        ]);
        final api = BiliApiClient(transport: t);
        final p = home
            ? (await HomeClient(api).load(
                channel: 'dynamic',
                section: '全部',
                page: 1,
              )).items.single.dynamicPost!
            : (await ProfileClient(
                api,
              ).loadDynamics('2')).items.single.dynamicPost!;
        expect(p.id, '900719925474099312345');
        expect(p.authorId, '900719925474099312346');
        expect(p.text, '前[大][坏]未知@用户#话题#链接');
        expect(p.spans[1].kind, ApiDynamicTextKind.emoji);
        expect(p.spans[1].emojiSize, 2);
        expect(p.spans[1].imageUrl?.scheme, 'https');
        expect(p.spans[2].kind, ApiDynamicTextKind.plain);
        expect(p.spans[4].userId, '123');
        expect(p.spans[5].userId, isNull);
        expect(p.spans[6].linkUrl, isNull);
        expect(p.imageUrls.length, 9);
        expect(p.likeCount, isNull);
        expect(p.commentCount, 4);
        expect(() => p.imageUrls.clear(), throwsUnsupportedError);
      },
    );
  }
  test(
    'opus rich summary archive statistics and forward depth are preserved',
    () async {
      final opus = {
        'id_str': '5',
        'modules': {
          'module_dynamic': {
            'major': {
              'opus': {
                'title': '图文',
                'summary': {
                  'rich_text_nodes': [
                    {
                      'type': 'RICH_TEXT_NODE_TYPE_EMOJI',
                      'text': '[小]',
                      'emoji': {'icon_url': '//i0.hdslb.com/s.png', 'size': 1},
                    },
                  ],
                },
                'pics': [
                  {'src': 'data:x'},
                ],
              },
            },
          },
        },
      };
      var original = post(id: '4', original: opus);
      original = post(id: '3', original: original);
      final t = DynamicTransport([
        post(
          original: original,
          major: {
            'archive': {
              'bvid': 'BV1234567890',
              'title': '视频',
              'duration_text': '01:03',
              'stat': {'play': '1.2万', 'danmaku': 7},
            },
          },
        ),
      ]);
      final p = (await ProfileClient(
        BiliApiClient(transport: t),
      ).loadDynamics('2')).items.single.dynamicPost!;
      expect(p.video?.playCount, 12000);
      expect(p.video?.danmakuCount, 7);
      expect(p.video?.duration, Duration(seconds: 63));
      expect(p.original?.original?.original?.unavailable, true);
      final direct = (await ProfileClient(
        BiliApiClient(transport: DynamicTransport([opus])),
      ).loadDynamics('2')).items.single.dynamicPost!;
      expect(direct.text, '[小]');
      expect(direct.spans.single.emojiSize, 1);
      expect(direct.imageUrls, isEmpty);
    },
  );
  test(
    'deleted original and article unsafe links use readable official fallback',
    () async {
      final t = DynamicTransport([
        post(
          original: {'type': 'DYNAMIC_TYPE_NONE'},
          major: {
            'article': {'title': '文章', 'jump_url': 'https://evil.example/x'},
          },
        ),
      ]);
      final p = (await ProfileClient(
        BiliApiClient(transport: t),
      ).loadDynamics('2')).items.single.dynamicPost!;
      expect(p.original?.unavailable, true);
      expect(p.original?.text, isNotEmpty);
      expect(p.linkTitle, '文章');
      expect(p.linkUrl?.host, 't.bilibili.com');
    },
  );
  test('live recommendation JSON exposes safe public title and room', () async {
    final t = DynamicTransport([
      post(
        major: {
          'live_rcmd': {
            'content': jsonEncode({
              'live_play_info': {
                'room_id': 12,
                'title': '直播标题',
                'cover': '//i0.hdslb.com/live.png',
              },
            }),
          },
        },
      ),
    ]);
    final p = (await ProfileClient(
      BiliApiClient(transport: t),
    ).loadDynamics('2')).items.single.dynamicPost!;
    expect(p.linkTitle, '直播标题');
    expect(p.linkUrl.toString(), 'https://live.bilibili.com/12');
  });
  test(
    'node count and text capacity are bounded and malformed IDs fail',
    () async {
      final nodes = List.generate(
        400,
        (_) => {'type': 'UNKNOWN', 'text': 'x' * 1000},
      );
      final api = BiliApiClient(
        transport: DynamicTransport([post(nodes: nodes)]),
      );
      final p = (await ProfileClient(
        api,
      ).loadDynamics('2')).items.single.dynamicPost!;
      expect(p.spans.length, lessThanOrEqualTo(256));
      expect(p.text.length, 32768);
      final invalid = {...post(), 'id_str': 9007199254740992.0};
      await expectLater(
        ProfileClient(
          BiliApiClient(transport: DynamicTransport([invalid])),
        ).loadDynamics('2'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  test('unknown empty content and deleted items remain readable', () async {
    final unknown = {
      'id_str': '9',
      'type': 'FUTURE',
      'modules': <String, Object?>{},
    };
    final deleted = {'id_str': '10', 'type': 'DYNAMIC_TYPE_NONE'};
    final p = await ProfileClient(
      BiliApiClient(transport: DynamicTransport([unknown, deleted])),
    ).loadDynamics('2');
    expect(p.items.first.dynamicPost?.text, contains('暂不支持'));
    expect(p.items.last.dynamicPost?.unavailable, true);
    expect(p.items.last.dynamicPost?.text, contains('删除'));
    final home = await HomeClient(
      BiliApiClient(transport: DynamicTransport([unknown, deleted])),
    ).load(channel: 'dynamic', section: '全部', page: 1);
    expect(home.items.last.dynamicPost?.unavailable, true);
  });
}
