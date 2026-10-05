import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class _FakeTransport implements ApiTransport {
  _FakeTransport(this.handler);
  final Future<ApiHttpResponse> Function(Uri, Map<String, String>) handler;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) => handler(uri, headers);
}

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

ApiHttpResponse _jsonResponse(
  Object payload, {
  Map<String, List<String>>? headers,
}) => ApiHttpResponse(
  200,
  Uint8List.fromList(utf8.encode(jsonEncode(payload))),
  headers ?? const {},
);

void main() {
  test(
    'recommendation reasons preserve optional text without invented labels',
    () async {
      final reasons = <Object?>[
        {'content': ' 3万点赞 '},
        '已关注',
        null,
        {},
        {'content': 12},
        {'content': ' '},
        [],
      ];
      final client = BiliApiClient(
        transport: _FakeTransport(
          (_, _) async => _jsonResponse({
            'code': 0,
            'data': {
              'list': [
                for (final reason in reasons)
                  {
                    'bvid': 'BV1234567890',
                    'title': '视频',
                    'rcmd_reason': reason,
                  },
              ],
              'no_more': true,
            },
          }),
        ),
      );
      final page = await client.getPopular();
      expect(page.items.map((video) => video.recommendationReason), [
        '3万点赞',
        '已关注',
        null,
        null,
        null,
        null,
        null,
      ]);
    },
  );
  test(
    'rich comments decode optional metadata and reject unsafe media',
    () async {
      final client = BiliApiClient(
        transport: _FakeTransport(
          (uri, _) async => _jsonResponse({
            'code': 0,
            'data': {
              'page': {'num': 1, 'size': 20, 'count': 1},
              'replies': [
                {
                  'rpid': 10,
                  'member': {
                    'uname': 'reader',
                    'level_info': {'current_level': 6},
                    'official_verify': {'type': 1},
                    'vip': {
                      'vipStatus': 1,
                      'label': {'text': '年度大会员'},
                    },
                    'fans_detail': {'medal_name': 'medal', 'level': 5},
                    'user_sailing': {
                      'cardbg': {
                        'image': '//i0.hdslb.com/card.png',
                        'name': '装扮名称',
                        'fan': {'num_desc': '0014931', 'color': '#abcdef'},
                      },
                    },
                  },
                  'content': {
                    'message': 'hello[笑]',
                    'emote': {
                      '[笑]': {'url': '//i0.hdslb.com/e.png'},
                      '[坏]': {'url': 'file:///secret'},
                    },
                    'pictures': [
                      {'img_src': 'http://i0.hdslb.com/p.png'},
                      {'img_src': 'https://user:pass@example.com/a'},
                    ],
                  },
                  'replies': [
                    {
                      'rpid': 11,
                      'member': {
                        'uname': 'nested',
                        'level_info': {'current_level': 3},
                      },
                      'content': {
                        'message': 'reply',
                        'pictures': [
                          {'img_src': '//i0.hdslb.com/n.png'},
                        ],
                      },
                    },
                  ],
                },
              ],
            },
          }),
        ),
      );
      final c = (await client.getVideoComments('42')).items.single;
      expect(c.level, 6);
      expect(c.verifyType, 1);
      expect(c.vipLabel, '年度大会员');
      expect(c.medalLevel, 5);
      expect(c.decorationImageUrl, Uri.https('i0.hdslb.com', '/card.png'));
      expect(c.decorationName, '装扮名称');
      expect(c.decorationFanNumber, '0014931');
      expect(c.decorationFanColor, 0xabcdef);
      expect(c.emotes.keys, ['[笑]']);
      expect(c.emotes.values.single.scheme, 'https');
      expect(c.pictures.length, 1);
      expect(c.pictures.single.scheme, 'https');
      expect(c.replies.single.level, 3);
      expect(c.replies.single.pictures.length, 1);
    },
  );
  test(
    'comment decoration rejects unsafe images and malformed fan colors',
    () async {
      final values = <Object?>[null, -1, 0x1000000, 1.5, 'bad', {}, []];
      final client = BiliApiClient(
        transport: _FakeTransport(
          (_, _) async => _jsonResponse({
            'code': 0,
            'data': {
              'page': {'num': 1, 'size': 20, 'count': values.length},
              'replies': [
                for (var index = 0; index < values.length; index++)
                  {
                    'rpid': index + 1,
                    'member': {
                      'uname': 'reader',
                      'user_sailing': {
                        'cardbg': {
                          'image':
                              index.isEven
                                  ? 'file:///secret'
                                  : 'https://user:pass@example.com/card.png',
                          'fan': {'color': values[index], 'num_desc': 123},
                        },
                      },
                    },
                    'content': {'message': 'comment'},
                  },
              ],
            },
          }),
        ),
      );
      final page = await client.getVideoComments('42');
      for (final comment in page.items) {
        expect(comment.decorationImageUrl, isNull);
        expect(comment.decorationFanNumber, isNull);
        expect(comment.decorationFanColor, isNull);
      }
    },
  );
  test(
    'reply decoration preserves fan serial text and decimal or hex RGB',
    () async {
      final colors = <Object?>[0, '11259375', '#ABCdef', 'abcdef'];
      final client = BiliApiClient(
        transport: _FakeTransport((uri, _) async {
          expect(uri.path, '/x/v2/reply/reply');
          return _jsonResponse({
            'code': 0,
            'data': {
              'page': {'num': 1, 'size': 20, 'count': colors.length},
              'replies': [
                for (var index = 0; index < colors.length; index++)
                  {
                    'rpid': index + 1,
                    'member': {
                      'uname': 'reader',
                      'user_sailing': {
                        'cardbg': {
                          'image': 'http://i0.hdslb.com/card.png',
                          'fan': {'color': colors[index], 'num_desc': '000123'},
                        },
                      },
                    },
                    'content': {'message': 'reply'},
                  },
                {
                  'rpid': 10,
                  'member': {'uname': 'no decoration', 'user_sailing': null},
                  'content': {'message': 'reply'},
                },
              ],
            },
          });
        }),
      );
      final page = await client.getVideoReplies('42', '10');
      expect(page.items.take(4).map((c) => c.decorationFanColor), [
        0,
        0xabcdef,
        0xabcdef,
        0xabcdef,
      ]);
      expect(
        page.items.take(4).map((c) => c.decorationFanNumber),
        everyElement('000123'),
      );
      expect(page.items.first.decorationImageUrl?.scheme, 'https');
      expect(page.items.last.decorationImageUrl, isNull);
    },
  );
  test(
    'emote panel uses reply business and bounds untrusted packages',
    () async {
      final client = BiliApiClient(
        transport: _FakeTransport((uri, _) async {
          expect(uri.path, '/x/emote/user/panel/web');
          expect(uri.queryParameters, {'business': 'reply'});
          return _jsonResponse({
            'code': 0,
            'data': {
              'packages': List.generate(
                60,
                (i) => {
                  'text': 'package',
                  'emote': List.generate(
                    220,
                    (j) => {
                      'text': '[emote$j]',
                      'url': j == 0 ? 'javascript:bad' : '//i0.hdslb.com/e.png',
                      'type': j == 1 ? 4 : 1,
                    },
                  ),
                },
              ),
            },
          });
        }),
      );
      final p = await client.getCommentEmotes();
      expect(p.length, 50);
      expect(p.first.items.length, 200);
      expect(p.first.items.first.imageUrl, isNull);
      expect(p.first.items[1].imageUrl, isNull);
      expect(p.first.items[1].text, '[emote1]');
      expect(p.first.items[2].imageUrl?.scheme, 'https');
    },
  );

  test(
    'home endpoints keep distinct requests, fields and paging semantics',
    () async {
      final requests = <Uri>[];
      const entry = {
        'bvid': 'BV1234567890',
        'title': 'Home video',
        'duration': 60,
        'owner': {'name': 'Creator'},
        'stat': {'view': 42, 'danmaku': 2},
      };
      final client = BiliApiClient(
        transport: _FakeTransport((uri, _) async {
          requests.add(uri);
          if (uri.path.endsWith('/nav')) {
            return _jsonResponse({
              'code': -101,
              'data': {
                'wbi_img': {
                  'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                  'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
                },
              },
            });
          }
          return _jsonResponse({
            'code': 0,
            'data': switch (uri.path) {
              '/x/web-interface/index/top/feed/rcmd' => {
                'item': [
                  {
                    ...entry,
                    'goto': 'av',
                    'rcmd_reason': {'content': '已关注'},
                  },
                  {'goto': 'live', 'title': 'Live card'},
                ],
              },
              '/x/web-interface/newlist' => {
                'archives': [entry],
                'page': {'count': 41},
              },
              '/x/web-interface/ranking/v2' => {
                'list': [entry],
              },
              _ => throw StateError('Unexpected endpoint'),
            },
          });
        }),
      );
      final recommended = await client.getRecommended(page: 2);
      expect(recommended.items.single.title, 'Home video');
      expect(recommended.items.single.recommendationReason, '已关注');
      expect(recommended.hasMore, isTrue);
      expect(recommended.nextCursor, '3');
      expect(requests.last.queryParameters['fresh_idx'], '2');
      expect(requests.last.queryParameters['w_rid'], isNotNull);
      final region = await client.getRegionalVideos(categoryId: '3', page: 2);
      expect(region.hasMore, isTrue);
      expect(requests.last.queryParameters['rid'], '3');
      expect(requests.last.queryParameters['pn'], '2');
      expect(
        (await client.getRegionalVideos(categoryId: '3', page: 3)).hasMore,
        isFalse,
      );
      final ranking = await client.getRanking(categoryId: '4');
      expect(ranking.items.single.playCount, 42);
      expect(ranking.hasMore, isFalse);
      expect(requests.last.queryParameters['rid'], '4');
      expect(requests.last.queryParameters['type'], 'all');
      expect(requests.last.queryParameters['w_rid'], isNotNull);
      expect(requests.any((uri) => uri.path.endsWith('/popular')), isFalse);
    },
  );

  test(
    'ranking rate limit stops without retries or popularity fallback',
    () async {
      var rankingCalls = 0;
      final client = BiliApiClient(
        transport: _FakeTransport((uri, _) async {
          if (uri.path.endsWith('/nav')) {
            return _jsonResponse({
              'code': -101,
              'data': {
                'wbi_img': {
                  'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                  'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
                },
              },
            });
          }
          expect(uri.path, '/x/web-interface/ranking/v2');
          rankingCalls++;
          return _jsonResponse({'code': -352, 'data': null});
        }),
      );
      await expectLater(
        client.getRanking(),
        throwsA(
          isA<ApiFailure>().having(
            (failure) => failure.category,
            'category',
            ApiFailureCategory.rateLimited,
          ),
        ),
      );
      expect(rankingCalls, 1);
    },
  );

  test('popular and detail expose stable fields and string IDs', () async {
    final client = BiliApiClient(
      transport: _FakeTransport((uri, _) async {
        if (uri.path.endsWith('popular')) {
          return _jsonResponse({
            'code': 0,
            'data': {
              'no_more': false,
              'list': [
                {
                  'bvid': 'BV1234567890',
                  'title': 'Example',
                  'pic': 'http://i0.hdslb.com/a.jpg',
                  'duration': 90,
                  'owner': {'name': 'Creator'},
                  'stat': {'view': 1234, 'danmaku': 56},
                  'pubdate': 1700000000,
                },
              ],
            },
          });
        }
        return _jsonResponse({
          'code': 0,
          'data': {
            'aid': 9007199254740991,
            'bvid': 'BV1234567890',
            'title': 'Example',
            'desc': '',
            'owner': {'name': 'Creator'},
            'pic': 'http://i1.hdslb.com/b.jpg',
            'stat': {'view': 4567, 'danmaku': 89},
            'pubdate': 1700000001,
            'pages': [
              {'cid': 12345, 'page': 1, 'part': 'P1', 'duration': 90},
            ],
          },
        });
      }),
    );
    final popular = await client.getPopular();
    expect(popular.items.single.bvid, 'BV1234567890');
    expect(popular.items.single.coverUrl?.scheme, 'https');
    expect(popular.items.single.playCount, 1234);
    expect(popular.items.single.danmakuCount, 56);
    expect(
      popular.items.single.publishedAt,
      DateTime.utc(2023, 11, 14, 22, 13, 20),
    );
    expect(popular.nextCursor, '2');
    final detail = await client.getVideoDetail('BV1234567890');
    expect(detail.aid, '9007199254740991');
    expect(detail.pages.single.cid, '12345');
    expect(detail.coverUrl?.scheme, 'https');
    expect(detail.playCount, 4567);
    expect(detail.danmakuCount, 89);
    expect(detail.publishedAt, DateTime.utc(2023, 11, 14, 22, 13, 21));
  });

  test(
    'search leaves abbreviated count unknown and parses plain count',
    () async {
      final client = BiliApiClient(
        transport: _FakeTransport((uri, _) async {
          if (uri.path == '/x/web-interface/nav') {
            return _jsonResponse({
              'code': -101,
              'data': {
                'wbi_img': {
                  'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                  'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
                },
              },
            });
          }
          return _jsonResponse({
            'code': 0,
            'data': {
              'numPages': 1,
              'result': [
                {
                  'bvid': 'BV1234567890',
                  'title': 'Example',
                  'duration': '1:30',
                  'author': 'Creator',
                  'play': '1.2万',
                  'video_review': '300',
                  'pic': 'http://i0.hdslb.com/a.jpg',
                  'pubdate': 1700000000,
                },
              ],
            },
          });
        }),
      );
      final item = (await client.searchVideos('sample')).items.single;
      expect(item.playCount, isNull);
      expect(item.danmakuCount, 300);
      expect(item.duration, const Duration(seconds: 90));
      expect(item.coverUrl?.scheme, 'https');
    },
  );

  test('QR poll captures scoped cookies and maps state', () async {
    final jar = ApiCookieJar();
    final client = BiliApiClient(
      cookieJar: jar,
      transport: _FakeTransport(
        (uri, _) async => _jsonResponse(
          {
            'code': 0,
            'data': {'code': 0},
          },
          headers: {
            'set-cookie': [
              'SESSDATA=secret; Domain=.bilibili.com; Path=/; Secure',
            ],
          },
        ),
      ),
    );
    expect((await client.pollQr('test-key')).status, ApiQrStatus.confirmed);
    expect(
      jar.headerFor(Uri.https('api.bilibili.com', '/x')),
      'SESSDATA=secret',
    );
    expect(jar.headerFor(Uri.https('example.com', '/x')), isNull);
  });

  test('old session response is discarded', () async {
    final session = _Session();
    final client = BiliApiClient(
      sessionProvider: session,
      transport: _FakeTransport((uri, _) async {
        session.sessionEpoch++;
        return _jsonResponse({
          'code': 0,
          'data': {'list': []},
        });
      }),
    );
    await expectLater(
      client.getPopular(context: const ApiRequestContext(sessionEpoch: 1)),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });

  test('missing required detail field is protocol failure', () async {
    final client = BiliApiClient(
      transport: _FakeTransport(
        (uri, _) async => _jsonResponse({
          'code': 0,
          'data': {'bvid': 'BV1234567890', 'title': 'Broken', 'pages': []},
        }),
      ),
    );
    await expectLater(
      client.getVideoDetail('BV1234567890'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
  });

  test('guest WBI key is fetched once for concurrent searches', () async {
    var navCalls = 0;
    final client = BiliApiClient(
      transport: _FakeTransport((uri, _) async {
        if (uri.path == '/x/web-interface/nav') {
          navCalls++;
          return _jsonResponse({
            'code': -101,
            'data': {
              'isLogin': false,
              'wbi_img': {
                'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
              },
            },
          });
        }
        return _jsonResponse({
          'code': 0,
          'data': {'result': [], 'numPages': 0},
        });
      }),
    );
    await Future.wait([client.searchVideos('one'), client.searchVideos('two')]);
    expect(navCalls, 1);
  });

  test('5xx read is retried within a bounded count', () async {
    var calls = 0;
    final client = BiliApiClient(
      transport: _FakeTransport((uri, _) async {
        calls++;
        if (calls < 3) return ApiHttpResponse(503, Uint8List(0), const {});
        return _jsonResponse({
          'code': 0,
          'data': {'list': [], 'no_more': true},
        });
      }),
    );
    expect((await client.getPopular()).items, isEmpty);
    expect(calls, 3);
  });

  test('small danmaku protobuf is decoded and truncated data fails', () {
    // DmSegMobileReply.elems = field 1; DanmakuElem.progress = 2,
    // mode = 3, content = 7. This fixture is handwritten and contains no user data.
    final bytes = Uint8List.fromList([
      10,
      13,
      8,
      1,
      16,
      232,
      7,
      24,
      1,
      58,
      4,
      116,
      101,
      115,
      116,
    ]);
    final item = decodeDanmakuSegment(bytes).single;
    expect(item.progress, const Duration(seconds: 1));
    expect(item.content, 'test');
    expect(
      () => decodeDanmakuSegment(Uint8List.fromList([10, 8, 58])),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('large danmaku segment decodes off isolate boundary', () async {
    final bytes = _largeDanmakuBytes();
    final client = BiliApiClient(
      transport: _FakeTransport(
        (_, _) async => ApiHttpResponse(200, bytes, const {}),
      ),
    );
    final items = await client.getDanmakuSegment('12345', 1);
    expect(items.length, 2500);
    expect(items.last.content, 'test');
  });

  test('completed decode is discarded after source cancellation', () async {
    final bytes = _largeDanmakuBytes();
    final entered = Completer<void>();
    final release = Completer<List<ApiDanmakuItem>>();
    final cancellation = ApiCancellation();
    final client = BiliApiClient(
      transport: _FakeTransport(
        (_, _) async => ApiHttpResponse(200, bytes, const {}),
      ),
      danmakuDecoder: (_) {
        entered.complete();
        return release.future;
      },
    );
    final request = client.getDanmakuSegment(
      '12345',
      1,
      context: ApiRequestContext(cancellation: cancellation),
    );
    await entered.future;
    cancellation.cancel();
    release.complete(const []);
    await expectLater(
      request,
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });

  test(
    'queued decode is bounded and cancellation discards old result',
    () async {
      final bytes = _largeDanmakuBytes();
      final started = Completer<void>();
      final releases = [
        Completer<List<ApiDanmakuItem>>(),
        Completer<List<ApiDanmakuItem>>(),
      ];
      var active = 0;
      var highest = 0;
      var calls = 0;
      final client = BiliApiClient(
        transport: _FakeTransport(
          (_, _) async => ApiHttpResponse(200, bytes, const {}),
        ),
        danmakuDecoder: (_) {
          final index = calls++;
          active++;
          if (active > highest) highest = active;
          if (active == 2) started.complete();
          return releases[index].future.whenComplete(() => active--);
        },
      );
      final first = client.getDanmakuSegment('12345', 1);
      final second = client.getDanmakuSegment('12345', 2);
      await started.future;
      final cancellation = ApiCancellation();
      final third = client.getDanmakuSegment(
        '12345',
        3,
        context: ApiRequestContext(cancellation: cancellation),
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      await expectLater(
        third,
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      releases[0].complete(const []);
      releases[1].complete(const []);
      await Future.wait([first, second]);
      expect(calls, 2);
      expect(highest, 2);
    },
  );

  test('decode queue rejects work beyond four waiting segments', () async {
    final bytes = _largeDanmakuBytes();
    final started = Completer<void>();
    final firstTwo = [
      Completer<List<ApiDanmakuItem>>(),
      Completer<List<ApiDanmakuItem>>(),
    ];
    var calls = 0;
    final client = BiliApiClient(
      transport: _FakeTransport(
        (_, _) async => ApiHttpResponse(200, bytes, const {}),
      ),
      danmakuDecoder: (_) {
        final index = calls++;
        if (index == 1) started.complete();
        return index < 2 ? firstTwo[index].future : Future.value(const []);
      },
    );
    final active = [
      client.getDanmakuSegment('12345', 1),
      client.getDanmakuSegment('12345', 2),
    ];
    await started.future;
    final queued = [
      for (var i = 3; i <= 6; i++) client.getDanmakuSegment('12345', i),
    ];
    await Future<void>.delayed(Duration.zero);
    await expectLater(
      client.getDanmakuSegment('12345', 7),
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.category,
          'category',
          ApiFailureCategory.unavailable,
        ),
      ),
    );
    firstTwo[0].complete(const []);
    firstTwo[1].complete(const []);
    await Future.wait([...active, ...queued]);
    expect(calls, 6);
  });
}

Uint8List _largeDanmakuBytes() {
  const entry = <int>[
    10,
    13,
    8,
    1,
    16,
    232,
    7,
    24,
    1,
    58,
    4,
    116,
    101,
    115,
    116,
  ];
  return Uint8List.fromList([for (var i = 0; i < 2500; i++) ...entry]);
}
