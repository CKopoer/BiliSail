import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _defaultId = '9007199254740993123';
const _video = <String, Object?>{
  'id': 124,
  'type': 2,
  'bvid': 'BV1234567890',
  'title': '收藏视频',
  'cover': '//i0.hdslb.com/cover.jpg',
  'upper': {'name': '作者', 'mid': '9007199254740993124'},
  'duration': 123,
  'pubtime': 1700000000,
  'cnt_info': {'play': 12345, 'danmaku': 67},
};

final class _Transport implements ApiTransport {
  _Transport(this.handler);
  final Object Function(Uri) handler;
  final requests = <Uri>[];
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
      Uint8List.fromList(utf8.encode(jsonEncode(handler(uri)))),
      const {},
    );
  }
}

Map<String, Object?> _gallery() => {
  'code': 0,
  'data': {
    'default_folder': {
      'folder_detail': {'id': _defaultId, 'title': '改名后的默认夹'},
    },
  },
};

void main() {
  test(
    'a complete collection snapshot stops despite ignoring page size',
    () async {
      final client = HomeClient(
        BiliApiClient(
          transport: _Transport(
            (_) => {
              'code': 0,
              'data': {
                'info': {'media_count': 38},
                'medias': [
                  for (var i = 0; i < 38; i++)
                    {
                      ..._video,
                      'id': i + 1,
                      'bvid': 'BV${i.toString().padLeft(10, '0')}',
                    },
                ],
              },
            },
          ),
        ),
      );
      final result = await client.load(
        channel: 'favorites',
        section: '我的收藏与订阅',
        page: 1,
        mid: '7',
        folderId: 'ugc:42',
      );
      expect(result.items, hasLength(38));
      expect(result.hasMore, isFalse);
    },
  );
  test('default folder uses server ID and carries it through paging', () async {
    final transport = _Transport((uri) {
      if (uri.path.endsWith('/space/v2')) return _gallery();
      expect(uri.path, '/x/v3/fav/resource/list');
      expect(uri.queryParameters['media_id'], _defaultId);
      return {
        'code': 0,
        'data': {
          'info': {'media_count': 21},
          'medias': [_video],
          'has_more': uri.queryParameters['pn'] == '1',
        },
      };
    });
    final client = HomeClient(BiliApiClient(transport: transport));
    final first = await client.load(
      channel: 'favorites',
      section: '默认收藏夹',
      page: 1,
      mid: '7',
    );
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, _defaultId);
    expect(first.totalCount, 21);
    final video = first.items.single;
    expect(video.authorName, '作者');
    expect(video.authorMid, '9007199254740993124');
    expect(video.duration, const Duration(seconds: 123));
    expect(video.playCountText, '12345');
    expect(video.danmakuCountText, '67');
    expect(video.publishedAt?.millisecondsSinceEpoch, 1700000000000);
    expect(video.coverUrl?.scheme, 'https');
    final next = await client.load(
      channel: 'favorites',
      section: '默认收藏夹',
      page: 2,
      mid: '7',
      cursor: first.nextCursor,
    );
    expect(next.hasMore, isFalse);
    expect(transport.requests.length, 3);
    expect(transport.requests.last.queryParameters['pn'], '2');
  });

  test(
    'created folders exclude the default ID and retain server pages',
    () async {
      final transport = _Transport((uri) {
        if (uri.path.endsWith('/space/v2')) return _gallery();
        expect(uri.path, '/x/v3/fav/folder/created/list');
        return {
          'code': 0,
          'data': {
            'count': 21,
            'has_more': uri.queryParameters['pn'] == '1',
            'list': [
              {'id': _defaultId, 'title': '改名后的默认夹'},
              {'id': 42, 'title': '默认收藏夹', 'media_count': 2},
            ],
          },
        };
      });
      final client = HomeClient(BiliApiClient(transport: transport));
      final first = await client.load(
        channel: 'favorites',
        section: '我创建的收藏夹',
        page: 1,
        mid: '7',
      );
      expect(first.items.single.id, '42');
      expect(first.items.single.contentCount, 2);
      expect(first.hasMore, isTrue);
      final next = await client.load(
        channel: 'favorites',
        section: '我创建的收藏夹',
        page: 2,
        mid: '7',
        cursor: first.nextCursor,
      );
      expect(next.hasMore, isFalse);
      expect(transport.requests.length, 3);
    },
  );

  test(
    'subscriptions distinguish collections from folders with equal IDs',
    () async {
      final transport = _Transport((uri) {
        if (uri.path.endsWith('/collected/list')) {
          return {
            'code': 0,
            'data': {
              'count': 2,
              'has_more': false,
              'list': [
                {
                  'id': 42,
                  'title': '订阅合集',
                  'type': 21,
                  'media_count': 38,
                  'view_count': 1635000,
                  'cover': '//i0.hdslb.com/collection.jpg',
                },
                {'id': 42, 'title': '收藏的收藏夹', 'type': 11},
              ],
            },
          };
        }
        expect(uri.path, '/x/space/fav/season/list');
        expect(uri.queryParameters['season_id'], '42');
        expect(uri.queryParameters['mid'], '7');
        expect(uri.queryParameters.containsKey('media_id'), isFalse);
        return {
          'code': 0,
          'data': {
            'info': {'media_count': 21},
            'medias': [_video],
          },
        };
      });
      final client = HomeClient(BiliApiClient(transport: transport));
      final list = await client.load(
        channel: 'favorites',
        section: '我的收藏与订阅',
        page: 1,
        mid: '7',
      );
      expect(list.items.map((e) => e.kind), [
        ApiHomeEntryKind.collection,
        ApiHomeEntryKind.folder,
      ]);
      expect(list.items.first.contentCount, 38);
      expect(list.items.first.viewCount, 1635000);
      final videos = await client.load(
        channel: 'favorites',
        section: '我的收藏与订阅',
        page: 1,
        mid: '7',
        folderId: 'ugc:42',
      );
      expect(videos.items.single.bvid, 'BV1234567890');
      expect(videos.hasMore, isTrue);
      final next = await client.load(
        channel: 'favorites',
        section: '我的收藏与订阅',
        page: 2,
        mid: '7',
        folderId: 'ugc:42',
      );
      expect(next.hasMore, isFalse);
      expect(transport.requests.last.queryParameters['pn'], '2');
    },
  );

  for (final (section, type) in [('我的追番', '1'), ('我的追剧', '2')]) {
    test(
      '$section uses Web follow type $type and total-based pagination',
      () async {
        final transport = _Transport((uri) {
          expect(uri.path, '/x/space/bangumi/follow/list');
          expect(uri.queryParameters, {
            'vmid': '7',
            'type': type,
            'pn': '2',
            'ps': '20',
          });
          return {
            'code': 0,
            'data': {
              'total': 41,
              'list': [
                {
                  'season_id': '9007199254740993',
                  'title': section,
                  'new_ep': {'index_show': '更新至第3集'},
                },
              ],
            },
          };
        });
        final result = await HomeClient(
          BiliApiClient(transport: transport),
        ).load(channel: 'favorites', section: section, page: 2, mid: '7');
        expect(result.items.single.kind, ApiHomeEntryKind.season);
        expect(result.items.single.id, '9007199254740993');
        expect(result.items.single.subtitle, '更新至第3集');
        expect(result.hasMore, isTrue);
      },
    );
  }

  test(
    'unavailable favorites retain cover and do not expose playback',
    () async {
      final transport = _Transport(
        (_) => {
          'code': 0,
          'data': {
            'has_more': false,
            'medias': [
              {..._video, 'attr': 1},
              {..._video, 'title': '已失效视频'},
              {..._video, 'type': 12},
              {'id': 125, 'title': '不可用内容'},
            ],
          },
        },
      );
      final result = await HomeClient(
        BiliApiClient(transport: transport),
      ).load(channel: 'favorites', section: '我的收藏与订阅', page: 1, folderId: '42');
      expect(result.items.every((e) => e.bvid == null), isTrue);
      expect(result.items.first.coverUrl?.scheme, 'https');
    },
  );

  test(
    'explicit empty, malformed responses and permissions remain distinct',
    () async {
      final empty = HomeClient(
        BiliApiClient(
          transport: _Transport(
            (_) => {
              'code': 0,
              'data': {'total': 0, 'list': null},
            },
          ),
        ),
      );
      expect(
        (await empty.load(
          channel: 'favorites',
          section: '我的追剧',
          page: 1,
          mid: '7',
        )).items,
        isEmpty,
      );
      for (final data in [
        {'total': 1, 'list': null},
        {'list': <Object?>[]},
      ]) {
        final bad = HomeClient(
          BiliApiClient(
            transport: _Transport((_) => {'code': 0, 'data': data}),
          ),
        );
        await expectLater(
          bad.load(channel: 'favorites', section: '我的追番', page: 1, mid: '7'),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
      }
      final restricted = _Transport((_) => {'code': -403});
      await expectLater(
        HomeClient(
          BiliApiClient(transport: restricted),
        ).load(channel: 'favorites', section: '我的收藏与订阅', page: 1, mid: '7'),
        throwsA(isA<ApiFailure>()),
      );
      expect(restricted.requests, hasLength(1));
    },
  );

  test('cancellation prevents chained default folder requests', () async {
    final cancellation = ApiCancellation();
    final transport = _Transport((_) {
      cancellation.cancel();
      return _gallery();
    });
    await expectLater(
      HomeClient(BiliApiClient(transport: transport)).load(
        channel: 'favorites',
        section: '默认收藏夹',
        page: 1,
        mid: '7',
        context: ApiRequestContext(cancellation: cancellation),
      ),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    expect(transport.requests, hasLength(1));
  });

  test(
    'missing account and invalid folder identity never reach transport',
    () async {
      final transport = _Transport(
        (_) => throw StateError('Unexpected request'),
      );
      final client = HomeClient(BiliApiClient(transport: transport));
      await expectLater(
        client.load(channel: 'favorites', section: '我的追番', page: 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
      for (final folder in ['ugc:', 'ugc:x', '0', '42:3']) {
        await expectLater(
          client.load(
            channel: 'favorites',
            section: '我的收藏与订阅',
            page: 1,
            folderId: folder,
          ),
          throwsArgumentError,
        );
      }
      expect(transport.requests, isEmpty);
    },
  );
}
