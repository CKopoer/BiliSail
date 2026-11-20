import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _legacy = '/x/article/view';
const _opus = '/x/polymer/web-dynamic/v1/opus/detail';
const _id = '12345678901234567890';

void main() {
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
        expect(article.commentCount, 12000);
        expect(article.commentForbidden, isFalse);
      }
    },
  );

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

final class _Transport implements ApiTransport, ApiHeadTransport {
  _Transport(this.data, {this.location, this.pendingHead});

  final Map<String, Object> data;
  final String? location;
  final Future<ApiHttpResponse>? pendingHead;
  final headCalls = <Uri>[];
  final headHeaders = <Map<String, String>>[];
  final getCalls = <Uri>[];

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
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': value}))),
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
