import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _legacy = '/x/article/view';
const _opus = '/x/polymer/web-dynamic/v1/opus/detail';
const _id = '12345678901234567890';

void main() {
  test(
    'collection preserves server order, decimal IDs and empty collections',
    () async {
      const path = '/x/article/list/web/articles';
      final transport = _Transport({
        path: {
          'list': {'id': '17', 'name': '目录', 'read': '1.2万'},
          'author': {'mid': 42, 'name': '作者'},
          'articles': [
            {
              'id': 12,
              'dyn_id_str': _id,
              'title': '图文',
              'image_urls': ['//i0.hdslb.com/image.jpg'],
            },
            {'id': '33', 'title': '专栏'},
            {'id': -1, 'title': '无效'},
          ],
        },
      });
      final client = ArticleClient(BiliApiClient(transport: transport));
      final collection = await client.collection('17');
      expect(collection.name, '目录');
      expect(collection.authorMid, '42');
      expect(collection.views, 12000);
      expect(collection.entries.map((e) => (e.id, e.opus)), [
        (_id, true),
        ('33', false),
      ]);
      expect(collection.entries.first.cover?.scheme, 'https');
      expect(transport.getCalls.single.queryParameters['id'], '17');
      transport.data[path] = {
        'list': {'id': 17},
        'articles': null,
      };
      expect((await client.collection('17')).entries, isEmpty);
      await expectLater(client.collection('18'), throwsA(isA<ApiFailure>()));
    },
  );

  test(
    'view info reads personal state separately from public totals',
    () async {
      final transport = _Transport({
        '/x/article/viewinfo': {
          'like': 0,
          'favorite': true,
          'stats': {'like': 1, 'favorite': 20, 'reply': 9, 'share': 4},
        },
      });
      final info = await ArticleClient(
        BiliApiClient(transport: transport),
      ).viewInfo('12');
      expect(
        (
          info.liked,
          info.likes,
          info.favorited,
          info.favorites,
          info.comments,
          info.forwards,
        ),
        (false, 1, true, 20, 9, 4),
      );
      expect(transport.getCalls.last.queryParameters['w_rid'], isNotEmpty);
    },
  );

  test(
    'favorites select CV form or opus JSON, use CSRF and send each write once',
    () async {
      final transport = _Transport({});
      final api = BiliApiClient(transport: transport);
      final client = ArticleClient(api);
      await expectLater(
        client.setFavorite(_id, opus: true, favorite: true),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, isEmpty);
      api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
        'SESSDATA=fixture; Path=/; Secure',
        'bili_jct=fixture-csrf; Path=/; Secure',
      ]);
      for (final add in [true, false]) {
        await client.setFavorite('12', opus: false, favorite: add);
        expect(
          transport.posts.last.$1.path,
          '/x/article/favorites/${add ? 'add' : 'del'}',
        );
        expect(transport.posts.last.$2, {'id': '12', 'csrf': 'fixture-csrf'});
        await client.setFavorite(_id, opus: true, favorite: add);
        expect(
          transport.posts.last.$1.path,
          '/x/community/cosmo/interface/simple_action',
        );
        expect(transport.posts.last.$1.queryParameters, {
          'csrf': 'fixture-csrf',
        });
        expect(transport.posts.last.$2, {
          'action': add ? 3 : 4,
          'entity': {
            'object_id_str': _id,
            'type': {'biz': 2},
          },
        });
      }
      expect(transport.posts, hasLength(4));
    },
  );

  test('reads text nodes in an unrecognized opus paragraph', () async {
    final client = ArticleClient(
      BiliApiClient(
        transport: _Transport({
          _opus: {
            'item': {
              'id_str': _id,
              'modules': [
                {
                  'module_content': {
                    'paragraphs': [
                      {'para_type': 99},
                      {
                        'para_type': 99,
                        'text': {
                          'nodes': [
                            {
                              'word': {
                                'words': '可读正文',
                                'style': {'bold': true},
                              },
                            },
                          ],
                        },
                      },
                    ],
                  },
                },
              ],
            },
          },
        }),
      ),
    );
    final article = await client.read(_id, opus: true);
    final block = article.blocks.single;
    expect(block.kind, ApiArticleBlockKind.paragraph);
    expect(block.text.single.text, '可读正文');
    expect(block.text.single.bold, isTrue);
  });

  test(
    'upgrades unsigned public article image URLs and keeps source order',
    () async {
      final transport = _Transport({
        _opus: {
          'item': {
            'id_str': _id,
            'modules': [
              {
                'module_content': {
                  'paragraphs': [
                    {
                      'para_type': 2,
                      'pic': {
                        'pics': [
                          {
                            'url':
                                'http://i0.hdslb.com/bfs/new_dyn/article.png',
                            'width': 1080,
                            'height': 1920,
                          },
                          {'url': 'http://i0.hdslb.com:8080/bfs/blocked.png'},
                          {
                            'url':
                                'http://i0.hdslb.com.bad.test/bfs/blocked.png',
                          },
                          {'url': 'https://fake.biliimg.com/bfs/blocked.png'},
                        ],
                      },
                    },
                    {
                      'para_type': 3,
                      'line': {
                        'pic': {
                          'url': '//i0.hdslb.com/bfs/article/line.png',
                          'width': 800,
                          'height': 20,
                        },
                      },
                    },
                    {'para_type': 3},
                  ],
                },
              },
            ],
          },
        },
      });
      final article = await ArticleClient(
        BiliApiClient(transport: transport),
      ).read(_id, opus: true);
      expect(article.blocks.map((block) => block.kind), [
        ApiArticleBlockKind.image,
        ApiArticleBlockKind.image,
        ApiArticleBlockKind.divider,
      ]);
      expect(
        article.blocks[0].image.toString(),
        'https://i0.hdslb.com/bfs/new_dyn/article.png',
      );
      expect(article.blocks[0].aspectRatio, 1080 / 1920);
      expect(
        article.blocks[1].image.toString(),
        'https://i0.hdslb.com/bfs/article/line.png',
      );
    },
  );

  test(
    'uses valid HTML image sources and recovers untransformed originals',
    () async {
      final transport = _Transport({
        _legacy: {
          'id': '123',
          'content':
              '<img data-src="data:image/png;base64,fake" '
              'src="http://i0.hdslb.com/bfs/article/a.png@640w_1e.webp">'
              '<img data-src="//album.biliimg.com/bfs/album/b.jpg" '
              'src="//i0.hdslb.com/bfs/placeholder.png">'
              '<img src="https://i0.hdslb.com/bfs/article/c.png@640w.webp?sign=fixture">',
        },
      });
      final article = await ArticleClient(
        BiliApiClient(transport: transport),
      ).read('123', opus: false);
      expect(article.blocks.map((block) => block.image.toString()), [
        'https://i0.hdslb.com/bfs/article/a.png',
        'https://album.biliimg.com/bfs/album/b.jpg',
        'https://i0.hdslb.com/bfs/article/c.png@640w.webp?sign=fixture',
      ]);
    },
  );

  test('reads legacy HTML into inert, ordered document blocks', () async {
    final transport = _Transport({
      _legacy: {
        'id': '123',
        'dyn_id_str': _id,
        'title': '旧版标题',
        'author': {'mid': '42', 'name': '作者', 'face': '//i0.hdslb.com/f.jpg'},
        'publish_time': 1700000000,
        'content':
            '<h2>开篇</h2><p>标题 &amp; <strong>说明</strong>'
            '<a href="javascript:alert(1)">链接</a>'
            '<a href="/read/cv456">另一篇</a></p>'
            '<script>unknown()</script><iframe src="https://x.invalid">hidden</iframe>'
            '<img src="https://x.invalid/pixel.png">'
            '<img data-src="//i0.hdslb.com/bfs/photo.jpg" width="800" height="400">'
            '<blockquote><p>引用</p></blockquote>',
      },
    });
    final api = BiliApiClient(transport: transport);
    api.cookieJar.receive(Uri.https('www.bilibili.com', '/'), [
      'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
    ]);
    final document = await ArticleClient(api).read('123', opus: false);
    expect(document.title, '旧版标题');
    expect(document.authorMid, '42');
    expect(document.dynamicId, _id);
    expect(document.authorAvatar?.host, 'i0.hdslb.com');
    expect(document.publishedAt?.millisecondsSinceEpoch, 1700000000000);
    expect(document.url.path, '/read/cv123');
    expect(document.commentOid, '123');
    expect(document.commentType, 12);
    expect(document.commentCount, isNull);
    expect(document.commentForbidden, isFalse);
    expect(document.blocks.map((block) => block.kind), [
      ApiArticleBlockKind.heading,
      ApiArticleBlockKind.paragraph,
      ApiArticleBlockKind.image,
      ApiArticleBlockKind.quote,
    ]);
    final paragraph = document.blocks[1].text;
    expect(paragraph.map((value) => value.text).join(), '标题 & 说明链接另一篇');
    expect(paragraph[1].bold, isTrue);
    expect(paragraph[2].link, isNull);
    expect(paragraph[3].link?.path, '/read/cv456');
    expect(document.blocks[2].aspectRatio, 2);
    expect(transport.headCalls.single.path, '/read/cv123/');
    expect(
      transport.headHeaders.single.keys.map((key) => key.toLowerCase()),
      isNot(contains('cookie')),
    );
    expect(transport.getCalls.last.queryParameters, containsPair('id', '123'));
    expect(
      transport.getCalls.last.queryParameters,
      containsPair('gaia_source', 'main_web'),
    );
    expect(transport.getCalls.last.queryParameters['w_rid'], isNotEmpty);
  });

  test(
    'migrated cv and direct opus select the signed structured reader',
    () async {
      final transport = _Transport({
        _opus: {
          'item': {
            'id_str': _id,
            'basic': {
              'rid_str': '123',
              'comment_id_str': '9007199254740993123',
              'comment_type': '17',
            },
            'modules': [
              {
                'module_collection': {'id': '17', 'name': '作品集', 'count': '2篇'},
                'module_title': {'text': '图文标题'},
              },
              {
                'module_author': {
                  'name': '作者',
                  'mid': 42,
                  'pub_ts': 1700000000,
                },
              },
              {
                'module_content': {'paragraphs': _paragraphs},
              },
              {
                'module_stat': {
                  'comment': {'count': '1.2万', 'forbidden': false},
                  'forward': {'count': 5, 'forbidden': true},
                  'favorite': {'count': 8, 'status': true},
                  'like': {'count': 15, 'status': 'STATE_LIKE'},
                },
              },
            ],
          },
        },
      }, location: '/opus/$_id?spm_id_from=333');
      final client = ArticleClient(BiliApiClient(transport: transport));
      final migrated = await client.read('123', opus: false);
      final direct = await client.read(_id, opus: true);
      expect(transport.headCalls, hasLength(1));
      expect(
        transport.getCalls
            .where((uri) => uri.path == _opus)
            .map((uri) => uri.queryParameters['id']),
        [_id, _id],
      );
      expect(
        transport.getCalls.last.queryParameters,
        containsPair('timezone_offset', '-480'),
      );
      expect(
        transport.getCalls.last.queryParameters['features'],
        contains('htmlNewStyle'),
      );
      expect(transport.getCalls.last.queryParameters['w_rid'], isNotEmpty);
      expect(migrated.url.path, '/opus/$_id');
      expect(migrated.title, '图文标题');
      expect(migrated.blocks.map((block) => block.kind), [
        ApiArticleBlockKind.paragraph,
        ApiArticleBlockKind.image,
        ApiArticleBlockKind.code,
      ]);
      expect(direct.blocks.first.text.single.text, '图文正文');
      for (final article in [migrated, direct]) {
        expect(article.commentOid, '9007199254740993123');
        expect(article.commentType, 17);
        expect(article.dynamicId, _id);
        expect(article.collection, (id: '17', name: '作品集', count: '2篇'));
        expect(article.stats?.forwardForbidden, isTrue);
        expect(article.stats?.liked, isTrue);
        expect(article.stats?.favorited, isTrue);
        expect(article.commentCount, 12000);
        expect(article.commentForbidden, isFalse);
      }
    },
  );

  test(
    'uses the resolved opus when the anonymous CV redirect has no target',
    () async {
      final transport = _Transport({
        _legacy: {
          'id': 123,
          'opus': {
            'opus_id': _id,
            'content': {
              'paragraphs': [
                {'para_type': 1, 'text': <String, Object?>{}},
              ],
            },
          },
        },
        _opus: {
          'item': {
            'id_str': _id,
            'modules': [
              {
                'module_content': {'paragraphs': _paragraphs},
              },
            ],
          },
        },
      });
      final article = await ArticleClient(
        BiliApiClient(transport: transport),
      ).read('123', opus: false);
      expect(article.url.path, '/opus/$_id');
      expect(article.blocks.first.text.single.text, '图文正文');
      expect(transport.headCalls, hasLength(1));
      expect(transport.getCalls.map((call) => call.path), [
        '/x/web-interface/nav',
        _legacy,
        _opus,
      ]);
    },
  );

  test(
    'reads ordered CV paragraphs when opus detail is rate limited',
    () async {
      final transport = _Transport({
        _opus: const ApiFailure(
          ApiFailureCategory.rateLimited,
          'opus_detail',
          businessCode: -352,
        ),
        _legacy: {
          'id': 123,
          'dyn_id_str': _id,
          'opus': {
            'opus_id': _id,
            'content': {'paragraphs': _paragraphs},
          },
        },
      }, location: '/opus/$_id');
      final client = ArticleClient(BiliApiClient(transport: transport));
      final article = await client.read('123', opus: false);
      expect(article.dynamicId, _id);
      expect(article.commentOid, '123');
      expect(article.blocks.map((block) => block.kind), [
        ApiArticleBlockKind.paragraph,
        ApiArticleBlockKind.image,
        ApiArticleBlockKind.code,
      ]);
      expect(transport.getCalls.map((call) => call.path), [
        '/x/web-interface/nav',
        _opus,
        _legacy,
      ]);
    },
  );

  test(
    'reuses the CV response when its opus falls back to the same CV',
    () async {
      final transport = _Transport({
        _legacy: {
          'id': 123,
          'opus': {'opus_id': _id},
          'content': '<p>旧版正文</p>',
        },
        _opus: {
          'fallback': {'id': '123'},
        },
      });
      final article = await ArticleClient(
        BiliApiClient(transport: transport),
      ).read('123', opus: false);
      expect(article.url.path, '/read/cv123');
      expect(article.blocks.single.text.single.text, '旧版正文');
      expect(transport.headCalls, hasLength(1));
      expect(transport.getCalls.map((call) => call.path), [
        '/x/web-interface/nav',
        _legacy,
        _opus,
      ]);
    },
  );

  test('does not resolve an opus from a mismatched CV response', () async {
    final transport = _Transport({
      _legacy: {
        'id': 456,
        'opus': {'opus_id': _id},
      },
    });
    await expectLater(
      ArticleClient(
        BiliApiClient(transport: transport),
      ).read('123', opus: false),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
    expect(transport.getCalls.map((call) => call.path), [
      '/x/web-interface/nav',
      _legacy,
    ]);
  });

  test(
    'opus fallback reads legacy structured body without probing again',
    () async {
      final transport = _Transport({
        _opus: {
          'fallback': {'id': '456'},
        },
        _legacy: {
          'id': 456,
          'opus': {
            'content': {'paragraphs': _paragraphs},
          },
        },
      }, location: '/opus/$_id');
      final doc = await ArticleClient(
        BiliApiClient(transport: transport),
      ).read('123', opus: false);
      expect(transport.headCalls, hasLength(1));
      expect(transport.getCalls.map((call) => call.path), [
        '/x/web-interface/nav',
        _opus,
        _legacy,
      ]);
      expect(doc.url.path, '/read/cv456');
      expect(doc.blocks.first.text.single.text, '图文正文');
      expect(doc.commentOid, '456');
      expect(doc.commentType, 12);
    },
  );

  test(
    'ignores an off-site redirect and reads legacy Quill operations',
    () async {
      final transport = _Transport({
        _legacy: {
          'type': 3,
          'ops': [
            {'insert': '笔记标题'},
            {
              'insert': '\n',
              'attributes': {'header': 1},
            },
            {
              'insert': '笔记正文\n',
              'attributes': {'bold': true},
            },
          ],
        },
      }, location: 'https://external.invalid/opus/$_id');
      final doc = await ArticleClient(
        BiliApiClient(transport: transport),
      ).read('123', opus: false);
      expect(transport.getCalls.where((uri) => uri.path == _opus), isEmpty);
      expect(doc.blocks.first.kind, ApiArticleBlockKind.heading);
      expect(doc.blocks.last.text.single.bold, isTrue);
    },
  );

  test(
    'keeps blocked opus metadata and discards an unexpected identity',
    () async {
      final response = {
        'item': {
          'id_str': _id,
          'basic': {'comment_id_str': '123', 'comment_type': 12},
          'modules': [
            {
              'module_blocked': {'title': '内容受限', 'hint_message': '请先登录'},
            },
            {
              'module_content': {'paragraphs': _paragraphs},
            },
            {
              'module_stat': {
                'comment': {'count': 7},
              },
            },
          ],
        },
      };
      final client = ArticleClient(
        BiliApiClient(transport: _Transport({_opus: response})),
      );
      final blocked = await client.read(_id, opus: true);
      expect(blocked.accessMessage, '内容受限\n请先登录');
      expect(blocked.blocks, isEmpty);
      expect(blocked.commentOid, isNull);
      expect(blocked.commentType, isNull);
      expect(blocked.commentCount, isNull);
      await expectLater(
        client.read('123', opus: true),
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

  test(
    'reads a closed opus comment flag without discarding the article',
    () async {
      final client = ArticleClient(
        BiliApiClient(
          transport: _Transport({
            _opus: {
              'item': {
                'id_str': _id,
                'basic': {'comment_id_str': '123', 'comment_type': 12},
                'modules': [
                  {
                    'module_content': {'paragraphs': _paragraphs},
                  },
                  {
                    'module_stat': {
                      'comment': {'count': 0, 'forbidden': true},
                    },
                  },
                ],
              },
            },
          }),
        ),
      );
      final document = await client.read(_id, opus: true);
      expect(document.commentForbidden, isTrue);
      expect(document.commentOid, '123');
      expect(document.commentType, 12);
      expect(document.commentCount, 0);
      expect(document.blocks, isNotEmpty);
    },
  );

  test(
    'opus never guesses a missing, malformed or unsupported comment target',
    () async {
      for (final basic in [
        null,
        {'rid_str': '123'},
        {'rid_str': '123', 'comment_type': 12},
        {'comment_id_str': '123'},
        {'comment_id_str': '123', 'comment_type': 99},
        {'comment_id_str': '12.3', 'comment_type': 12},
      ]) {
        final client = ArticleClient(
          BiliApiClient(
            transport: _Transport({
              _opus: {
                'item': {
                  'id_str': _id,
                  'basic': basic,
                  'modules': [
                    {
                      'module_content': {'paragraphs': _paragraphs},
                    },
                  ],
                },
              },
            }),
          ),
        );
        final document = await client.read(_id, opus: true);
        expect(document.commentOid, isNull);
        expect(document.commentType, isNull);
        expect(document.commentCount, isNull);
        expect(document.commentForbidden, isFalse);
        expect(document.blocks, isNotEmpty);
      }
    },
  );

  test('cancelling the migration lookup never starts a body request', () async {
    final response = Completer<ApiHttpResponse>();
    final transport = _Transport(const {}, pendingHead: response.future);
    final client = ArticleClient(BiliApiClient(transport: transport));
    final cancellation = ApiCancellation();
    final request = client.read(
      '123',
      opus: false,
      context: ApiRequestContext(cancellation: cancellation),
    );
    final result = expectLater(
      request,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    cancellation.cancel();
    await result;
    expect(transport.headCalls, hasLength(1));
    expect(transport.getCalls, isEmpty);
  });
}

const _paragraphs = [
  {
    'para_type': 1,
    'text': {
      'nodes': [
        {
          'word': {'words': '图文正文'},
        },
      ],
    },
  },
  {
    'para_type': 2,
    'pic': {
      'pics': [
        {'url': '//i0.hdslb.com/bfs/photo.jpg'},
      ],
    },
  },
  {
    'para_type': 7,
    'code': {'content': 'final value = 1;'},
  },
];

final class _Transport
    implements
        ApiTransport,
        ApiHeadTransport,
        ApiFormTransport,
        ApiJsonTransport {
  _Transport(this.data, {this.location, this.pendingHead});

  final Map<String, Object> data;
  final String? location;
  final Future<ApiHttpResponse>? pendingHead;
  final headCalls = <Uri>[];
  final headHeaders = <Map<String, String>>[];
  final getCalls = <Uri>[];

  final posts = <(Uri, Map<String, Object?>)>[];
  ApiHttpResponse _record(Uri uri, Map<String, Object?> body) {
    posts.add((uri, body));
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode('{"code":0}')),
      const {},
    );
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => _record(uri, fields);

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => _record(uri, body);

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    getCalls.add(uri);
    final value = uri.path == '/x/web-interface/nav' ? _nav : data[uri.path];
    if (value == null) throw StateError('Unexpected request to ${uri.path}');
    final body = value is ApiFailure
        ? {
            'code': value.businessCode,
            if (value.requiresVerification) 'v_voucher': 'fixture',
          }
        : {'code': 0, 'data': value};
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(body))),
      const {},
    );
  }

  @override
  Future<ApiHttpResponse> head(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    headCalls.add(uri);
    headHeaders.add(headers);
    return pendingHead ??
        ApiHttpResponse(location == null ? 200 : 302, Uint8List(0), {
          if (location case final target?) 'location': [target],
        });
  }
}

const _nav = {
  'wbi_img': {
    'img_url':
        'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
    'sub_url':
        'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
  },
};
