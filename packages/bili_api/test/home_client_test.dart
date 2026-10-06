import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class Transport implements ApiTransport {
  Transport(this.handler, {this.statusCode = 200});
  final Object? Function(Uri) handler;
  final int statusCode;
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
      statusCode,
      Uint8List.fromList(utf8.encode(jsonEncode(handler(uri)))),
      {},
    );
  }
}

void main() {
  test(
    'live homepage snapshot combines recommendation modules and deduplicates rooms',
    () async {
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'recommend_room_list': [
              {
                'roomid': 12,
                'title': '推荐直播',
                'uname': '主播',
                'online': 123,
                'area_v2_name': '单机',
                'face': '//i0.hdslb.com/face.jpg',
              },
            ],
            'room_list': [
              {
                'module_info': {'title': '分区'},
                'list': [
                  {'roomid': 12, 'title': '重复房间'},
                  {'roomid': '13', 'title': '另一直播'},
                  {'roomid': 14, 'title': '广告', 'is_ad': true},
                  {'title': '非房间卡片'},
                ],
              },
              {
                'module_info': {'title': '空模块'},
              },
            ],
          },
        },
      );
      final page = await HomeClient(
        BiliApiClient(transport: transport),
      ).load(channel: 'live', section: '推荐直播', page: 1);
      expect(
        transport.requests.single.path,
        '/xlive/web-interface/v1/index/getList',
      );
      expect(transport.requests.single.queryParameters, {'platform': 'web'});
      expect(page.items.map((item) => item.id), ['12', '13']);
      expect(page.items.first.title, '推荐直播');
      expect(page.items.first.areaName, '单机');
      expect(page.items.first.authorAvatarUrl?.scheme, 'https');
      expect(page.hasMore, false);
    },
  );

  test(
    'dynamic archive maps typed metadata without losing publication text',
    () async {
      final client = HomeClient(
        BiliApiClient(
          transport: Transport(
            (_) => {
              'code': 0,
              'data': {
                'has_more': false,
                'items': [
                  {
                    'id_str': '42',
                    'modules': {
                      'module_author': {
                        'name': '作者',
                        'mid': 789,
                        'face': '//i0.hdslb.com/face.jpg',
                        'pub_ts': 1700000000,
                        'pub_time': '今天',
                      },
                      'module_dynamic': {
                        'major': {
                          'archive': {
                            'bvid': 'BV1234567890',
                            'title': '视频',
                            'duration_text': '01:02:03',
                            'stat': {'play': '1.2万', 'danmaku': 35},
                          },
                        },
                      },
                    },
                  },
                ],
              },
            },
          ),
        ),
      );
      final entry =
          (await client.load(
            channel: 'videoDynamic',
            section: '最新视频',
            page: 1,
          )).items.single;
      expect(entry.authorName, '作者');
      expect(entry.authorMid, '789');
      expect(entry.authorAvatarUrl.toString(), 'https://i0.hdslb.com/face.jpg');
      expect(entry.duration, const Duration(hours: 1, minutes: 2, seconds: 3));
      expect(entry.publishedAt?.millisecondsSinceEpoch, 1700000000000);
      expect(entry.publishText, '今天');
      expect(entry.playCountText, '1.2万');
      expect(entry.danmakuCountText, '35');
    },
  );
  test(
    'live parents retain children and selected child reaches transport',
    () async {
      final transport = Transport(
        (uri) =>
            uri.path == '/room/v1/Area/getList'
                ? {
                  'code': 0,
                  'data': [
                    {
                      'id': 2,
                      'name': '游戏',
                      'list': [
                        {'id': '21', 'name': '单机'},
                      ],
                    },
                  ],
                }
                : {
                  'code': 0,
                  'data': {
                    'count': 1,
                    'list': [
                      {
                        'roomid': 123,
                        'title': '直播',
                        'uname': '主播',
                        'online': 12000,
                        'area_name': '单机',
                      },
                    ],
                  },
                },
      );
      final client = HomeClient(BiliApiClient(transport: transport));
      final areas = await client.load(
        channel: 'live',
        section: '全部分区',
        page: 1,
      );
      expect(areas.items.single.children.single.id, '2:21');
      final rooms = await client.load(
        channel: 'live',
        section: '推荐直播',
        page: 1,
        folderId: areas.items.single.children.single.id,
      );
      expect(transport.requests.last.queryParameters['parent_area_id'], '2');
      expect(transport.requests.last.queryParameters['area_id'], '21');
      expect(transport.requests.last.path, '/room/v3/Area/getRoomList');
      expect(transport.requests.last.queryParameters['page_size'], '36');
      expect(rooms.items.single.popularityText, '12000');
      expect(rooms.items.single.areaName, '单机');
    },
  );
  test(
    'live parent uses all children and count-based one-based pages',
    () async {
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'count': 37,
            // The room-list endpoint has no has_more field.
            'list': [
              {
                'roomid': 123,
                'uid': '9007199254740993',
                'title': '分区直播',
                'cover': '',
                'user_cover': '//i0.hdslb.com/room.jpg',
                'face': '//i0.hdslb.com/face.jpg',
                'area_v2_name': '单机',
              },
            ],
          },
        },
      );
      final client = HomeClient(BiliApiClient(transport: transport));
      final first = await client.load(
        channel: 'live',
        section: '推荐',
        page: 1,
        folderId: '2',
      );
      expect(transport.requests.single.queryParameters, {
        'platform': 'web',
        'parent_area_id': '2',
        'area_id': '0',
        'sort_type': 'online',
        'page': '1',
        'page_size': '36',
      });
      expect(first.hasMore, isTrue);
      expect(first.items.single.authorMid, '9007199254740993');
      expect(
        first.items.single.coverUrl.toString(),
        'https://i0.hdslb.com/room.jpg',
      );
      expect(first.items.single.authorAvatarUrl?.scheme, 'https');
      expect(first.items.single.areaName, '单机');
      final second = await client.load(
        channel: 'live',
        section: '推荐',
        page: 2,
        folderId: '2',
      );
      expect(transport.requests.last.queryParameters['page'], '2');
      expect(second.hasMore, isFalse);
    },
  );
  test('empty live areas require a valid count and list', () async {
    final valid = HomeClient(
      BiliApiClient(
        transport: Transport(
          (_) => {
            'code': 0,
            'data': {'count': 0, 'list': <Object?>[]},
          },
        ),
      ),
    );
    final empty = await valid.load(
      channel: 'live',
      section: '推荐',
      page: 1,
      folderId: '2',
    );
    expect(empty.items, isEmpty);
    expect(empty.hasMore, isFalse);
    for (final data in [
      {'list': <Object?>[]},
      {'count': -1, 'list': <Object?>[]},
      {'count': 0},
    ]) {
      final client = HomeClient(
        BiliApiClient(transport: Transport((_) => {'code': 0, 'data': data})),
      );
      await expectLater(
        client.load(channel: 'live', section: '推荐', page: 1, folderId: '2'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    }
  });
  test(
    'live area failures do not switch endpoints or become empty success',
    () async {
      final transport = Transport(
        (_) => {'code': -352, 'message': 'restricted'},
      );
      final client = HomeClient(BiliApiClient(transport: transport));
      await expectLater(
        client.load(channel: 'live', section: '推荐', page: 1, folderId: '2:21'),
        throwsA(
          isA<ApiFailure>()
              .having(
                (e) => e.category,
                'category',
                ApiFailureCategory.rateLimited,
              )
              .having((e) => e.businessCode, 'businessCode', -352),
        ),
      );
      expect(transport.requests, hasLength(1));
      expect(transport.requests.single.path, '/room/v3/Area/getRoomList');
    },
  );
  test(
    'HTTP 429 live area response is retained as a failure without retry',
    () async {
      final transport = Transport((_) => {}, statusCode: 429);
      await expectLater(
        HomeClient(
          BiliApiClient(transport: transport),
        ).load(channel: 'live', section: '推荐', page: 1, folderId: '2'),
        throwsA(
          isA<ApiFailure>()
              .having(
                (e) => e.category,
                'category',
                ApiFailureCategory.rateLimited,
              )
              .having((e) => e.httpStatus, 'httpStatus', 429),
        ),
      );
      expect(transport.requests, hasLength(1));
    },
  );
  test('invalid live area identity is rejected before requesting', () async {
    final transport = Transport((_) => throw StateError('Must not request'));
    final client = HomeClient(BiliApiClient(transport: transport));
    for (final id in ['2:21:3', '2:', ':21', '2:x', '-1', '0', '2:0']) {
      await expectLater(
        client.load(channel: 'live', section: '推荐', page: 1, folderId: id),
        throwsArgumentError,
      );
    }
    expect(transport.requests, isEmpty);
  });
  test('PGC index uses content types and timeline result arrays', () async {
    final transport = Transport(
      (uri) =>
          uri.path.endsWith('timeline')
              ? {
                'code': 0,
                'result': [
                  {
                    'date': '10-5',
                    'episodes': [
                      {
                        'season_id': 12,
                        'episode_id': 22,
                        'title': '剧集',
                        'pub_time': '12:00',
                        'pub_index': '第2话',
                      },
                    ],
                  },
                ],
              }
              : {
                'code': 0,
                'data': {
                  'list': [
                    {'season_id': 12, 'title': '剧集'},
                  ],
                  'has_next': 1,
                },
              },
    );
    final client = HomeClient(BiliApiClient(transport: transport));
    final result = await client.load(
      channel: 'guochuang',
      section: '国创索引',
      page: 2,
    );
    expect(result.items.single.kind, ApiHomeEntryKind.season);
    expect(
      result.items.single.url.toString(),
      'https://www.bilibili.com/bangumi/play/ss12',
    );
    expect(transport.requests.single.queryParameters['season_type'], '4');
    expect(transport.requests.single.queryParameters['page'], '2');
    expect(result.hasMore, true);
    final timeline = await client.load(
      channel: 'bangumi',
      section: '时间表',
      page: 1,
    );
    expect(timeline.items.single.subtitle, '10-5 12:00 · 第2话');
    expect(timeline.hasMore, false);
  });
  test('dynamic preserves text and opaque offset across pages', () async {
    final transport = Transport(
      (uri) => {
        'code': 0,
        'data': {
          'items': [
            {
              'id_str': '9007199254740993',
              'type': 'DYNAMIC_TYPE_DRAW',
              'modules': {
                'module_author': {'name': '作者'},
                'module_dynamic': {
                  'desc': {'text': '图文正文'},
                  'major': {
                    'draw': {
                      'items': [
                        {'src': 'https://i0.hdslb.com/image.jpg'},
                      ],
                    },
                  },
                },
              },
            },
          ],
          'offset': 'opaque&next=1',
          'has_more': true,
        },
      },
    );
    final client = HomeClient(BiliApiClient(transport: transport));
    final result = await client.load(
      channel: 'dynamic',
      section: '图文',
      page: 1,
    );
    expect(result.items.single.description, '图文正文');
    expect(result.items.single.bvid, isNull);
    expect(result.nextCursor, 'opaque&next=1');
    await client.load(
      channel: 'dynamic',
      section: '图文',
      page: 2,
      cursor: 'previous',
    );
    expect(transport.requests.last.queryParameters['offset'], 'previous');
    expect(transport.requests.last.queryParameters['type'], 'all');
    await expectLater(
      client.load(
        channel: 'dynamic',
        section: '图文',
        page: 3,
        cursor: 'opaque&next=1',
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
  });
  test(
    'favorites expand resource paging and retain unavailable items',
    () async {
      final transport = Transport(
        (uri) => {
          'code': 0,
          'data': {
            'medias': [
              {'id': 123, 'title': '已失效视频'},
              {
                'id': 124,
                'bvid': 'BV1234567890',
                'title': '可观看',
                'upper': {'name': 'UP'},
              },
            ],
            'has_more': false,
          },
        },
      );
      final client = HomeClient(BiliApiClient(transport: transport));
      final result = await client.load(
        channel: 'favorites',
        section: '我的收藏夹',
        page: 2,
        folderId: '42',
      );
      expect(result.items.length, 2);
      expect(result.items.first.bvid, isNull);
      expect(result.items.last.bvid, 'BV1234567890');
      expect(transport.requests.single.queryParameters['media_id'], '42');
      expect(transport.requests.single.queryParameters['pn'], '2');
    },
  );
  for (final section in ['全部', '未看完']) {
    test('watch later $section reads view counts including zero', () async {
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'list': [
              {
                'bvid': 'BV1234567890',
                'title': '有播放量',
                'progress': 30,
                'stat': {'view': 12345, 'danmaku': 178},
              },
              {
                'bvid': 'BV1234567891',
                'title': '零播放量',
                'progress': 0,
                'stat': {'view': 0, 'play': 999, 'danmaku': 0},
              },
              {
                'bvid': 'BV1234567892',
                'title': '缺少播放量',
                'progress': 0,
                'stat': {'danmaku': 3},
              },
            ],
          },
        },
      );
      final result = await HomeClient(
        BiliApiClient(transport: transport),
      ).load(channel: 'watchLater', section: section, page: 1);
      expect(result.items.map((item) => item.playCountText), [
        '12345',
        '0',
        '',
      ]);
      expect(result.items.map((item) => item.danmakuCountText), [
        '178',
        '0',
        '3',
      ]);
      expect(transport.requests.single.path, '/x/v2/history/toview');
    });
    test('watch later $section retains optional count fields', () async {
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'list': [
              {
                'bvid': 'BV1234567890',
                'title': '字符串计数',
                'progress': 0,
                'stat': {'view': '12345', 'danmaku': '0'},
              },
              {'bvid': 'BV1234567891', 'title': '缺少全部计数', 'progress': 0},
              {
                'bvid': 'BV1234567892',
                'title': '仅播放量',
                'progress': 0,
                'stat': {'view': 12},
              },
              {
                'bvid': 'BV1234567893',
                'title': '仅弹幕数',
                'progress': 0,
                'stat': {'danmaku': 3},
              },
            ],
          },
        },
      );
      final result = await HomeClient(
        BiliApiClient(transport: transport),
      ).load(channel: 'watchLater', section: section, page: 1);
      expect(result.items.map((item) => item.playCountText), [
        '12345',
        '',
        '12',
        '',
      ]);
      expect(result.items.map((item) => item.danmakuCountText), [
        '0',
        '',
        '',
        '3',
      ]);
      expect(result.items, hasLength(4));
      expect(result.hasMore, isFalse);
      expect(transport.requests.single.path, '/x/v2/history/toview');
    });
    test('watch later $section keeps decimal aid distinct from bvid', () async {
      final identities = <(Object?, String?)>[
        (123, '123'),
        (9007199254740993, '9007199254740993'),
        ('9007199254740993123', '9007199254740993123'),
        (null, null),
        (0, null),
        (-1, null),
        (123.0, null),
        ('BV1234567890', null),
        ('0123', null),
      ];
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'list': [
              for (var i = 0; i < identities.length; i++)
                {
                  'bvid': 'BV${i.toString().padLeft(10, '0')}',
                  'title': '标识$i',
                  'progress': 0,
                  if (identities[i].$1 != null) 'aid': identities[i].$1,
                  'stat': {'aid': 999, 'view': 12, 'danmaku': 3},
                },
            ],
          },
        },
      );
      final result = await HomeClient(
        BiliApiClient(transport: transport),
      ).load(channel: 'watchLater', section: section, page: 1);
      expect(result.items.map((item) => item.aid), [
        for (final identity in identities) identity.$2,
      ]);
      expect(result.items.map((item) => item.id), [
        for (var i = 0; i < identities.length; i++)
          'BV${i.toString().padLeft(10, '0')}',
      ]);
      expect(
        result.items.map((item) => item.playCountText),
        everyElement('12'),
      );
      expect(
        result.items.map((item) => item.danmakuCountText),
        everyElement('3'),
      );
    });
    test(
      'watch later $section retains unavailable archive identities',
      () async {
        final transport = Transport(
          (_) => {
            'code': 0,
            'data': {
              'list': [
                {
                  'aid': 123,
                  'bvid': 'BV1234567890',
                  'title': '可播放视频',
                  'progress': 0,
                },
                {
                  'aid': '9007199254740993123',
                  'title': '已失效视频',
                  'pic': '//i0.hdslb.com/unavailable.jpg',
                  'owner': {'mid': 7, 'name': '原作者'},
                  'duration': 125,
                  'progress': 0,
                  'stat': {'view': 12345, 'danmaku': 3},
                },
                {'aid': 456, 'bvid': '', 'progress': 0},
              ],
            },
          },
        );
        final result = await HomeClient(
          BiliApiClient(transport: transport),
        ).load(channel: 'watchLater', section: section, page: 1);
        expect(result.items.map((item) => item.id), [
          'BV1234567890',
          'aid:9007199254740993123',
          'aid:456',
        ]);
        expect(result.items.map((item) => item.aid), [
          '123',
          '9007199254740993123',
          '456',
        ]);
        final unavailable = result.items[1];
        expect(unavailable.kind, ApiHomeEntryKind.video);
        expect(unavailable.bvid, isNull);
        expect(unavailable.title, '已失效视频');
        expect(unavailable.coverUrl?.scheme, 'https');
        expect(unavailable.authorName, '原作者');
        expect(unavailable.authorMid, '7');
        expect(unavailable.duration, const Duration(seconds: 125));
        expect(unavailable.playCountText, '12345');
        expect(unavailable.danmakuCountText, '3');
        expect(result.items.last.title, '已失效内容');
      },
    );
    test('watch later $section rejects an unidentifiable archive', () async {
      final client = HomeClient(
        BiliApiClient(
          transport: Transport(
            (_) => {
              'code': 0,
              'data': {
                'list': [
                  {'title': '缺少视频标识', 'progress': 0, 'aid': 123.0},
                ],
              },
            },
          ),
        ),
      );
      await expectLater(
        client.load(channel: 'watchLater', section: section, page: 1),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }
  test(
    'watch later unfinished filter does not replace content source',
    () async {
      final transport = Transport(
        (uri) => {
          'code': 0,
          'data': {
            'list': [
              {'bvid': 'BV1234567890', 'title': '已完成', 'progress': -1},
              {'bvid': 'BV1234567891', 'title': '未完成', 'progress': 30},
            ],
          },
        },
      );
      final result = await HomeClient(
        BiliApiClient(transport: transport),
      ).load(channel: 'watchLater', section: '未看完', page: 1);
      expect(result.items.single.title, '未完成');
      expect(result.hasMore, false);
      expect(transport.requests.single.path, '/x/v2/history/toview');
    },
  );
  test(
    'malformed key fields fail instead of appearing as empty success',
    () async {
      final client = HomeClient(
        BiliApiClient(
          transport: Transport(
            (_) => {
              'code': 0,
              'data': {
                'list': [
                  {'title': '缺少season id'},
                ],
              },
            },
          ),
        ),
      );
      await expectLater(
        client.load(channel: 'bangumi', section: '推荐', page: 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    },
  );
}
