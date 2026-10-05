import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class _Transport implements ApiTransport {
  _Transport(this.handler);
  final Object Function(Uri) handler;
  final calls = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    calls.add(uri);
    final value =
        uri.path.endsWith('/nav')
            ? {
              'wbi_img': {
                'img_url':
                    'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                'sub_url':
                    'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
              },
            }
            : handler(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': value}))),
      const {},
    );
  }
}

SearchClient _client(Object Function(Uri) handler) =>
    SearchClient(BiliApiClient(transport: _Transport(handler)));

const _video = {
  'type': 'video',
  'bvid': 'BV1abc123456',
  'title': '<em class="keyword">测试</em> &amp; &#x4e2d;',
  'pic': '//i0.hdslb.com/cover.jpg',
  'author': 'UP',
  'mid': '9007199254740993123',
  'duration': '1:02:03',
  'play': 123,
  'video_review': 45,
  'pubdate': 1700000000,
};
const _user = {
  'mid': '9007199254740993123',
  'uname': '测试用户',
  'upic': '//i0.hdslb.com/avatar.jpg',
  'fans': 100000,
  'videos': 20,
  'level': 6,
  'usign': 'signature',
  'official_verify': {'type': 0, 'desc': '认证'},
  'res': [_video],
};
const _media = {
  'season_id': 123,
  'title': '测试番剧',
  'cover': '//i0.hdslb.com/poster.jpg',
  'desc': '描述',
  'areas': '日本',
  'styles': '推理',
  'media_score': {'score': 9.5},
  'new_ep': {'index_show': '更新至12话'},
  'angle_title': '会员',
};
const _live = {
  'roomid': 321,
  'uid': 123,
  'title': '测试直播',
  'uname': '主播',
  'user_cover': '//i0.hdslb.com/live.jpg',
  'cate_name': '游戏',
  'online': 456,
  'live_status': 1,
};
const _article = {
  'id': '9007199254740993123',
  'title': '测试专栏',
  'mid': 123,
  'author': '作者',
  'desc': '<em>文字</em>',
  'category_name': '科技',
  'image_urls': ['//i0.hdslb.com/article.jpg'],
  'view': 100,
  'like': 10,
  'reply': 2,
};

void main() {
  test(
    'all search decodes six content types, previews and server counts',
    () async {
      final result = await _client((uri) {
        expect(uri.queryParameters['keyword'], '中文 & + %');
        expect(uri.queryParameters['w_rid'], isNotEmpty);
        if (uri.path.endsWith('/type')) {
          expect(uri.queryParameters['search_type'], 'video');
          return {
            'numResults': 1000,
            'numPages': 50,
            'result': [_video],
          };
        }
        expect(uri.path, '/x/web-interface/wbi/search/all/v2');
        return {
          'pageinfo': {
            'video': {'numResults': 1000, 'numPages': 50},
            'bili_user': {'numResults': 1},
            'media_bangumi': {'numResults': 0},
            'live_room': {'numResults': 7},
          },
          'result': [
            {
              'result_type': 'bili_user',
              'data': [_user],
            },
            {
              'result_type': 'media_bangumi',
              'data': [_media],
            },
            {
              'result_type': 'media_ft',
              'data': [_media],
            },
            {
              'result_type': 'live_room',
              'data': [_live],
            },
            {
              'result_type': 'article',
              'data': [_article],
            },
            {'result_type': 'future_ad', 'data': 'unsupported'},
            {
              'result_type': 'video',
              'data': [_video],
            },
          ],
        };
      }).search(' 中文 & + % ');
      expect(result.items.length, 6);
      expect(result.counts[ApiSearchType.live], 7);
      expect(result.counts[ApiSearchType.bangumi], 0);
      expect(result.counts.containsKey(ApiSearchType.article), isFalse);
      final user = result.items.whereType<ApiSearchUser>().single;
      expect(user.mid, '9007199254740993123');
      expect(user.signature, '认证');
      expect(user.videos.single.title, '测试 & 中');
      expect(user.videos.single.duration.inSeconds, 3723);
      expect(user.videos.single.ownerMid, user.mid);
      final media = result.items.whereType<ApiSearchMedia>().first;
      expect(media.score, 9.5);
      expect(media.coverUrl?.scheme, 'https');
      expect(
        result.items.whereType<ApiSearchArticle>().single.id,
        '9007199254740993123',
      );
      expect(result.hasMore, isTrue);
      expect(() => result.items.clear(), throwsUnsupportedError);
      expect(() => result.counts.clear(), throwsUnsupportedError);
    },
  );

  test(
    'all subsequent pages use independently ranked video pagination',
    () async {
      final result = await _client((uri) {
        expect(uri.path, '/x/web-interface/wbi/search/type');
        expect(uri.queryParameters['search_type'], 'video');
        expect(uri.queryParameters['order'], 'pubdate');
        return {
          'numPages': 2,
          'result': [_video],
        };
      }).search('query', page: 2, order: 'pubdate');
      expect(result.items.single, isA<ApiSearchVideo>());
      expect(result.hasMore, isFalse);
    },
  );

  test(
    'all sorting/filtering preserves user preview and replaces unranked videos',
    () async {
      for (final (order, duration) in [
        ('totalrank', 0),
        ('click', 0),
        ('totalrank', 4),
      ]) {
        final page = await _client((uri) {
          if (uri.path.endsWith('/all/v2')) {
            expect(uri.queryParameters['order'], 'totalrank');
            expect(uri.queryParameters['duration'], '0');
            return {
              'pageinfo': {
                'bili_user': {'numResults': 1},
              },
              'result': [
                {
                  'result_type': 'bili_user',
                  'data': [_user],
                },
                {
                  'result_type': 'video',
                  'data': [_video],
                },
              ],
            };
          }
          expect(uri.queryParameters['order'], order);
          expect(uri.queryParameters['duration'], '$duration');
          return {
            'numPages': 2,
            'numResults': 25,
            'result': [
              {..._video, 'title': 'ranked'},
            ],
          };
        }).search('query', order: order, duration: duration);
        expect(
          page.items.whereType<ApiSearchUser>().single.videos,
          hasLength(1),
        );
        expect(
          page.items.whereType<ApiSearchVideo>().single.video.title,
          'ranked',
        );
        expect(page.counts[ApiSearchType.video], 25);
        expect(page.hasMore, isTrue);
      }
    },
  );

  test(
    'video sort, duration and page are signed without double encoding',
    () async {
      final result = await _client((uri) {
        expect(uri.queryParameters['search_type'], 'video');
        expect(uri.queryParameters['order'], 'stow');
        expect(uri.queryParameters['duration'], '4');
        expect(uri.queryParameters['page'], '3');
        expect(uri.queryParameters['keyword'], '中文 & + %');
        return {
          'numPages': 3,
          'numResults': 55,
          'result': [
            _video,
            {'type': 'live', 'bvid': '', 'roomid': 123},
          ],
        };
      }).search(
        '中文 & + %',
        type: ApiSearchType.video,
        order: 'stow',
        duration: 4,
        page: 3,
      );
      expect(result.items.length, 1);
      expect(result.hasMore, isFalse);
      expect(result.counts[ApiSearchType.video], 55);
    },
  );

  test(
    'live nested results use room count and pageinfo instead of top-level total',
    () async {
      final page = await _client((uri) {
        expect(uri.queryParameters['search_type'], 'live');
        expect(uri.queryParameters['cover_type'], 'user_cover');
        return {
          'numPages': 999,
          'numResults': 10000,
          'pageinfo': {
            'live_room': {'numResults': 21, 'numPages': 2},
          },
          'result': {
            'live_room': [_live],
            'live_user': [],
          },
        };
      }).search('query', type: ApiSearchType.live, page: 2);
      expect(page.hasMore, isFalse);
      expect(page.counts[ApiSearchType.live], 21);
      final live = page.items.single as ApiSearchLive;
      expect(live.roomId, '321');
      expect(live.isLive, isTrue);
    },
  );

  test('user and article have distinct order parameters', () async {
    await _client((uri) {
      expect(uri.queryParameters['order'], 'fans');
      expect(uri.queryParameters['order_sort'], '1');
      expect(uri.queryParameters['user_type'], '1');
      return {
        'result': [_user],
        'numPages': 1,
      };
    }).search(
      'query',
      type: ApiSearchType.user,
      order: 'fans',
      orderSort: 1,
      userType: 1,
    );
    await _client((uri) {
      expect(uri.queryParameters['order'], 'scores');
      expect(uri.queryParameters.containsKey('duration'), isFalse);
      return {
        'result': [_article],
        'numPages': 1,
      };
    }).search('query', type: ApiSearchType.article, order: 'scores');
  });

  test('PGC search type and season IDs stay distinct from media IDs', () async {
    for (final type in [ApiSearchType.bangumi, ApiSearchType.film]) {
      final page = await _client((uri) {
        expect(
          uri.queryParameters['search_type'],
          type == ApiSearchType.bangumi ? 'media_bangumi' : 'media_ft',
        );
        return {
          'result': [
            {..._media, 'media_id': 999},
          ],
          'numPages': 1,
        };
      }).search('query', type: type);
      expect((page.items.single as ApiSearchMedia).seasonId, '123');
    }
  });

  test(
    'known empty pages stop even if numPages claims there is more',
    () async {
      final page = await _client(
        (_) => {'numResults': 0, 'numPages': 99, 'result': null},
      ).search('query', type: ApiSearchType.user);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
      final all = await _client(
        (_) => {
          'pageinfo': {
            'video': {'numResults': 0},
          },
          'result': [],
        },
      ).search('query');
      expect(all.hasMore, isFalse);
    },
  );

  test(
    'malformed recognized entries are protocol failures, not empty success',
    () async {
      for (final data in <Map<String, Object?>>[
        {},
        {
          'result': [
            {
              'result_type': 'bili_user',
              'data': [
                {'uname': 'missing id'},
              ],
            },
          ],
        },
        {
          'result': [
            {
              'result_type': 'video',
              'data': [
                {'title': 'missing bvid'},
              ],
            },
          ],
        },
      ]) {
        await expectLater(
          _client((_) => data).search('query'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
      }
    },
  );

  test('invalid combinations and cancellation never reach transport', () async {
    final client = _client((_) => throw StateError('must not request'));
    await expectLater(
      client.search('query', type: ApiSearchType.bangumi, order: 'click'),
      throwsArgumentError,
    );
    await expectLater(
      client.search('query', type: ApiSearchType.article, duration: 1),
      throwsArgumentError,
    );
    await expectLater(
      client.search(
        'query',
        context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });
}
