import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class FakeTransport implements ApiTransport {
  FakeTransport(this.handler);
  final Object Function(Uri) handler;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode(handler(uri)))),
    const {},
  );
}

ProfileClient client(Object Function(Uri) handler) =>
    ProfileClient(BiliApiClient(transport: FakeTransport(handler)));
void main() {
  for (final (following, followers) in [(0, 0), (1, 0), (0, 1), (1, 1)]) {
    test(
      'relation privacy flags are independent: $following / $followers',
      () async {
        final privacy = await client((uri) {
          expect(uri.path, '/x/space/setting');
          expect(uri.queryParameters['mid'], '9007199254740993123');
          return {
            'code': 0,
            'data': {
              'privacy': {
                'disable_following': following,
                'disable_show_fans': followers,
              },
            },
          };
        }).loadRelationPrivacy('9007199254740993123');
        expect(privacy.followingHidden, following == 1);
        expect(privacy.followersHidden, followers == 1);
      },
    );
  }
  test(
    'malformed privacy fails instead of treating the lists as public',
    () async {
      for (final value in [null, 2, true, 'bad']) {
        await expectLater(
          client(
            (_) => {
              'code': 0,
              'data': {
                'privacy': {'disable_following': value, 'disable_show_fans': 0},
              },
            },
          ).loadRelationPrivacy('1'),
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
  test(
    'favorite videos retain statistics and unavailable media is disabled',
    () async {
      final page = await client(
        (_) => {
          'code': 0,
          'data': {
            'info': {'media_count': 3},
            'medias': [
              {
                'id': 12,
                'bvid': 'BV1234567890',
                'type': 2,
                'title': '收藏视频',
                'duration': 125,
                'pubtime': 1700000000,
                'upper': {'mid': '9007199254740993', 'name': '作者'},
                'cnt_info': {'play': 12345, 'danmaku': 67},
              },
              {'id': 13, 'bvid': 'BV1234567891', 'type': 2, 'title': '已失效视频'},
              {
                'id': 14,
                'bvid': 'BV1234567892',
                'type': 2,
                'title': '失效资源',
                'attr': 1,
              },
            ],
          },
        },
      ).loadFolderVideos('42', page: 1);
      final video = page.items.first.video;
      expect(video?.ownerMid, '9007199254740993');
      expect(video?.duration, const Duration(seconds: 125));
      expect(video?.playCount, 12345);
      expect(video?.danmakuCount, 67);
      expect(video?.publishedAt?.millisecondsSinceEpoch, 1700000000000);
      expect(page.items.skip(1).every((e) => e.video == null), isTrue);
    },
  );
  test(
    'profile preserves a large decimal string ID and optional metadata',
    () async {
      const mid = '9007199254740993123';
      final profile = await client((uri) {
        expect(uri.queryParameters['mid'], mid);
        return {
          'code': 0,
          'data': {
            'card': {
              'mid': mid,
              'name': 'user',
              'sign': 'signature',
              'fans': 2,
            },
            'archive_count': 3,
          },
        };
      }).loadProfile(mid);
      expect(profile.mid, mid);
      expect(profile.videoCount, 3);
    },
  );
  test('missing card ID fails instead of producing empty success', () async {
    await expectLater(
      client(
        (_) => {
          'code': 0,
          'data': {
            'card': {'name': 'user'},
          },
        },
      ).loadProfile('1'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.protocol,
        ),
      ),
    );
  });
  test('videos sign raw keywords exactly once and stop an empty page', () async {
    var signed = false;
    final page = await client((uri) {
      if (uri.path.endsWith('/nav')) {
        return {
          'code': 0,
          'data': {
            'wbi_img': {
              'img_url':
                  'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
              'sub_url':
                  'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
            },
          },
        };
      }
      expect(uri.queryParameters['keyword'], '中文 & + %');
      expect(uri.queryParameters['w_rid'], isNotEmpty);
      signed = true;
      return {
        'code': 0,
        'data': {
          'list': {'vlist': []},
          'page': {'count': 99},
        },
      };
    }).loadVideos('1', page: 1, keyword: '中文 & + %');
    expect(signed, isTrue);
    expect(page.hasMore, isFalse);
    expect(
      () => page.items.add(
        ApiProfileEntry(id: '1', kind: ApiProfileEntryKind.folder, title: 'x'),
      ),
      throwsUnsupportedError,
    );
  });
  test('dynamic opaque cursor stops when server makes no progress', () async {
    final page = await client((uri) {
      expect(uri.queryParameters['offset'], 'opaque:cursor');
      return {
        'code': 0,
        'data': {'items': [], 'has_more': true, 'offset': 'opaque:cursor'},
      };
    }).loadDynamics('1', cursor: 'opaque:cursor');
    expect(page.hasMore, isFalse);
  });
  test('empty folders and relation pages are explicit', () async {
    final api = client(
      (uri) => {
        'code': 0,
        'data': uri.path.contains('folder')
            ? {'count': 0, 'list': null}
            : {'total': 0, 'list': []},
      },
    );
    expect((await api.loadFolders('1', page: 1)).items, isEmpty);
    expect(
      (await api.loadRelations('1', followers: true, page: 1)).hasMore,
      isFalse,
    );
  });
  test('permission and cancellation retain pipeline classification', () async {
    await expectLater(
      client((_) => {'code': -403}).loadProfile('1'),
      throwsA(isA<ApiFailure>()),
    );
    final cancel = ApiCancellation()..cancel();
    await expectLater(
      client(
        (_) => throw StateError('should not request'),
      ).loadProfile('1', context: ApiRequestContext(cancellation: cancel)),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });
  test('invalid IDs and pages fail before network', () async {
    final api = client((_) => throw StateError('network'));
    await expectLater(api.loadProfile('0'), throwsArgumentError);
    await expectLater(api.loadVideos('1', page: 0), throwsArgumentError);
  });
  test('relation pagination carries decimal IDs and immutable items', () async {
    final page = await client(
      (_) => {
        'code': 0,
        'data': {
          'total': 31,
          'list': [
            {'mid': '9007199254740993123', 'uname': 'u', 'sign': 's'},
          ],
        },
      },
    ).loadRelations('1', followers: false, page: 1);
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, '2');
    expect(page.items.single.userMid, '9007199254740993123');
  });
  test(
    'malformed list fails and rate limits do not automatically retry',
    () async {
      await expectLater(
        client(
          (_) => {
            'code': 0,
            'data': {'list': 'bad', 'total': 0},
          },
        ).loadRelations('1', followers: true, page: 1),
        throwsA(isA<ApiFailure>()),
      );
      var requests = 0;
      await expectLater(
        client((_) {
          requests++;
          return {'code': -352};
        }).loadProfile('1'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.rateLimited,
          ),
        ),
      );
      expect(requests, 1);
    },
  );
  test('WBI rate limits are not re-signed or retried', () async {
    var navRequests = 0, videoRequests = 0;
    await expectLater(
      client((uri) {
        if (uri.path.endsWith('/nav')) {
          navRequests++;
          return {
            'code': 0,
            'data': {
              'wbi_img': {
                'img_url':
                    'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
                'sub_url':
                    'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
              },
            },
          };
        }
        videoRequests++;
        return {'code': -352};
      }).loadVideos('1', page: 1),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.rateLimited,
        ),
      ),
    );
    expect(navRequests, 1);
    expect(videoRequests, 1);
  });
  test('Web opus shape preserves title summary and bounded images', () async {
    final page = await client(
      (_) => {
        'code': 0,
        'data': {
          'has_more': 1,
          'offset': 'opaque-next',
          'items': [
            {
              'id_str': '123',
              'modules': {
                'module_author': {'mid': '1', 'pub_ts': 1700000000},
                'module_dynamic': {
                  'major': {
                    'opus': {
                      'title': '图文',
                      'summary': {'text': '正文'},
                      'pics': List.generate(
                        12,
                        (i) => {'src': 'http://i0.hdslb.com/$i.jpg'},
                      ),
                    },
                  },
                },
              },
            },
          ],
        },
      },
    ).loadDynamics('1');
    expect(page.items.single.title, '图文');
    expect(page.items.single.subtitle, '正文');
    expect(page.items.single.imageUrls.length, 9);
    expect(page.items.single.imageUrls.first.scheme, 'https');
    expect(page.hasMore, isTrue);
    expect(page.nextCursor, 'opaque-next');
  });
  test(
    'folder retains unavailable entries and parses playable owners',
    () async {
      final page = await client(
        (_) => {
          'code': 0,
          'data': {
            'info': {'media_count': 31},
            'medias': [
              {'id': 1, 'type': 12, 'title': 'other'},
              {
                'id': 2,
                'type': 2,
                'bvid': 'BV1xx411c7mD',
                'title': 'video',
                'upper': {'mid': '42', 'name': 'UP'},
                'duration': 60,
              },
            ],
          },
        },
      ).loadFolderVideos('1', page: 1);
      expect(page.items.first.video, isNull);
      expect(page.items.last.video?.ownerMid, '42');
      expect(page.hasMore, isTrue);
      expect(page.totalCount, 31);
    },
  );
}
