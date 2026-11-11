import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

final class FakeTransport implements ApiTransport {
  FakeTransport(this.handler, {this.onRequest});
  final Object Function(Uri) handler;
  final void Function(Uri, Map<String, String>)? onRequest;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    onRequest?.call(uri, headers);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(handler(uri)))),
      const {},
    );
  }
}

ProfileClient client(
  Object Function(Uri) handler, {
  void Function(Uri, Map<String, String>)? onRequest,
}) => ProfileClient(
  BiliApiClient(transport: FakeTransport(handler, onRequest: onRequest)),
);
void main() {
  test(
    'collections distinguish overlapping season/series IDs and page counts',
    () async {
      final page = await client((uri) {
        expect(uri.path, '/x/polymer/web-space/seasons_series_list');
        expect(uri.queryParameters, {
          'mid': '9007199254740993123',
          'page_num': '2',
          'page_size': '10',
        });
        return {
          'code': 0,
          'data': {
            'items_lists': {
              'page': {'total': 61},
              'seasons_list': [
                {
                  'meta': {
                    'season_id': '9007199254740993123',
                    'name': '合集',
                    'total': 12,
                    'cover': '//i0.hdslb.com/cover.png',
                  },
                },
              ],
              'series_list': [
                {
                  'meta': {
                    'series_id': '9007199254740993123',
                    'name': '系列',
                    'total': 3,
                  },
                },
              ],
            },
          },
        };
      }).loadCollections('9007199254740993123', page: 2);
      expect(page.hasMore, true);
      expect(page.items.map((e) => e.id), [
        'season:9007199254740993123',
        'series:9007199254740993123',
      ]);
      expect(page.items.map((e) => e.isSeries), [false, true]);
      expect(page.items.first.coverUrl?.scheme, 'https');
      expect(() => page.items.clear(), throwsUnsupportedError);
    },
  );
  for (final isSeries in [false, true]) {
    test(
      'collection archives map statistics and correct parameters $isSeries',
      () async {
        final page =
            await client((uri) {
              expect(
                uri.path,
                isSeries
                    ? '/x/series/archives'
                    : '/x/polymer/web-space/seasons_archives_list',
              );
              expect(
                uri.queryParameters[isSeries ? 'series_id' : 'season_id'],
                '9007199254740993123',
              );
              expect(uri.queryParameters[isSeries ? 'pn' : 'page_num'], '1');
              expect(
                uri.queryParameters[isSeries ? 'sort' : 'sort_reverse'],
                isSeries ? 'asc' : 'false',
              );
              return {
                'code': 0,
                'data': {
                  'page': {'total': 1},
                  'archives': [
                    {
                      'bvid': 'BV1234567890',
                      'title': '合集投稿',
                      'duration': 123,
                      'pubdate': 1700000000,
                      'stat': {'view': 156, 'danmaku': 7},
                    },
                  ],
                },
              };
            }).loadCollectionVideos(
              '7',
              '9007199254740993123',
              isSeries: isSeries,
              page: 1,
            );
        final video = page.items.single.video;
        expect(page.hasMore, false);
        expect(video?.playCount, 156);
        expect(video?.danmakuCount, 7);
        expect(video?.ownerMid, '7');
        expect(video?.duration.inSeconds, 123);
      },
    );
  }
  for (final cinema in [false, true]) {
    test('followed seasons preserve target ID and paging $cinema', () async {
      final page = await client((uri) {
        expect(uri.path, '/x/space/bangumi/follow/list');
        expect(uri.queryParameters['type'], cinema ? '2' : '1');
        expect(uri.queryParameters['vmid'], '7');
        return {
          'code': 0,
          'data': {
            'total': 31,
            'list': [
              {
                'season_id': '9007199254740993123',
                'title': '番剧标题',
                'new_ep': {'index_show': '更新至第 3 集'},
                'cover': '//i0.hdslb.com/poster.png',
              },
            ],
          },
        };
      }).loadFollowedSeasons('7', cinema: cinema, page: 1);
      expect(page.hasMore, true);
      expect(page.items.single.seasonId, '9007199254740993123');
      expect(page.items.single.kind, ApiProfileEntryKind.season);
      expect(page.items.single.subtitle, '更新至第 3 集');
    });
    test('hidden followed seasons stay permission failures $cinema', () async {
      await expectLater(
        client(
          (_) => {'code': -403},
        ).loadFollowedSeasons('7', cinema: cinema, page: 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.permission,
          ),
        ),
      );
    });
  }
  test('empty libraries stop paging while malformed payloads fail', () async {
    final empty = await client(
      (_) => {
        'code': 0,
        'data': {
          'items_lists': {
            'page': {'total': 0},
            'seasons_list': [],
            'series_list': [],
          },
        },
      },
    ).loadCollections('7', page: 1);
    expect(empty.items, isEmpty);
    expect(empty.hasMore, false);
    for (final data in [
      <String, Object?>{},
      {
        'items_lists': {
          'page': {'total': 0},
        },
      },
    ]) {
      await expectLater(
        client((_) => {'code': 0, 'data': data}).loadCollections('7', page: 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    }
    final followed = await client(
      (_) => {
        'code': 0,
        'data': {'total': 0, 'list': null},
      },
    ).loadFollowedSeasons('7', cinema: false, page: 1);
    expect(followed.hasMore, false);
  });
  test(
    'space details use WBI, reject another user and filter unsafe images',
    () async {
      for (final responseId in ['7', '8']) {
        final request = client(
          (uri) {
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
            expect(uri.path, '/x/space/wbi/acc/info');
            expect(uri.queryParameters['w_rid'], isNotEmpty);
            expect(uri.queryParameters['platform'], 'web');
            expect(uri.queryParameters['web_location'], '1550101');
            return {
              'code': 0,
              'data': {
                'mid': responseId,
                'top_photo': 'javascript:bad',
                'sex': '保密',
                'birthday': '01-02',
              },
            };
          },
          onRequest: (uri, headers) {
            if (uri.path == '/x/space/wbi/acc/info') {
              expect(
                headers['Referer'],
                'https://space.bilibili.com/7/dynamic',
              );
              expect(headers['Origin'], 'https://space.bilibili.com');
              expect(headers['User-Agent'], startsWith('Mozilla/5.0'));
            }
          },
        ).loadDetails('7');
        if (responseId == '7') {
          final details = await request;
          expect(details.bannerUrl, isNull);
          expect(details.gender, '保密');
          expect(details.birthday, '01-02');
        } else {
          await expectLater(request, throwsA(isA<ApiFailure>()));
        }
      }
    },
  );
  for (final status in [0, 1]) {
    for (final roomId in [1024, '9007199254740993123']) {
      test(
        'live lookup preserves room ID $roomId with status $status',
        () async {
          final room = await client((uri) {
            expect(uri.host, 'api.live.bilibili.com');
            expect(uri.path, '/room/v1/Room/getRoomInfoOld');
            expect(uri.queryParameters, {'mid': '9007199254740993123'});
            return {
              'code': 0,
              'data': {
                'roomStatus': 1,
                'roomid': roomId,
                'liveStatus': status,
                'roundStatus': 1,
              },
            };
          }).loadLiveRoom('9007199254740993123');
          expect(room?.roomId, '$roomId');
          expect(room?.isLive, status == 1);
        },
      );
    }
  }
  test('a user without a live room returns a successful null', () async {
    final room = await client(
      (_) => {
        'code': 0,
        'data': {'roomStatus': 0},
      },
    ).loadLiveRoom('1');
    expect(room, isNull);
  });
  test('missing and malformed live fields fail as protocol errors', () async {
    for (final data in [
      <String, Object?>{},
      {'roomStatus': 2},
      {'roomStatus': 1, 'roomid': 0, 'liveStatus': 0},
      {'roomStatus': 1, 'roomid': 123.0, 'liveStatus': 1},
      {'roomStatus': 1, 'roomid': 'bad', 'liveStatus': 1},
      {'roomStatus': 1, 'roomid': 123},
      {'roomStatus': 1, 'roomid': 123, 'liveStatus': 2},
    ]) {
      await expectLater(
        client((_) => {'code': 0, 'data': data}).loadLiveRoom('1'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    }
  });
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
                        20,
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
    expect(page.items.single.imageUrls.length, 18);
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
