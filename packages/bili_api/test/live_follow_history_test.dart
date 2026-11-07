import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'home_client_test.dart' show Transport;
import 'watch_history_client_test.dart' show client, entry;

Map<String, Object?> contentHistory(String business, String id) => {
  ...entry(business: business),
  'duration': null,
  'progress': null,
  'cover': '',
  'covers': ['//i0.hdslb.com/history.jpg'],
  'live_status': 1,
  'history': {'business': business, 'oid': id, 'cid': id, 'epid': id},
};

void main() {
  test('course season links preserve their own target kind', () async {
    final raw = contentHistory('cheese', '0')
      ..['uri'] = 'bilibili://cheese/play/ss123?from=history';
    final page = await client({
      'list': [raw],
      'cursor': {'max': 0, 'view_at': 0, 'business': ''},
    }).load();
    expect(page.items.single.contentId, '123');
    expect(page.items.single.courseSeason, true);
  });
  test(
    'followed live rooms page through the raw online/offline list',
    () async {
      final transport = Transport(
        (uri) => {
          'code': 0,
          'data': {
            'totalPage': 3,
            'count': 52,
            'live_count': 31,
            'list': [
              {'roomid': 1, 'live_status': 0},
              if (uri.queryParameters['page'] != '2')
                {
                  'roomid': '9007199254740993',
                  'live_status': 1,
                  'title': '直播标题',
                  'uname': '主播',
                  'room_cover': '//i0.hdslb.com/live.jpg',
                },
            ],
          },
        },
      );
      final home = HomeClient(BiliApiClient(transport: transport));
      final first = await home.load(channel: 'live', section: '我的关注', page: 1);
      expect(
        transport.requests.single.path,
        '/xlive/web-ucenter/user/following',
      );
      expect(transport.requests.single.queryParameters, {
        'page': '1',
        'page_size': '20',
        'ignoreRecord': '1',
        'hit_ab': 'true',
      });
      expect(first.items.single.id, '9007199254740993');
      expect(first.items.single.coverUrl?.scheme, 'https');
      expect(first.hasMore, true);
      final second = await home.load(channel: 'live', section: '我的关注', page: 2);
      expect(second.items, isEmpty);
      expect(second.hasMore, true);
      final third = await home.load(channel: 'live', section: '我的关注', page: 3);
      expect(third.hasMore, false);
    },
  );

  for (final business in ['live', 'article', 'article-list', 'cheese']) {
    test(
      '$business history retains its own ID, deletion key and cover',
      () async {
        final page = await client({
          'list': [contentHistory(business, '9007199254740993')],
          'cursor': {'max': 1, 'view_at': 1791324000, 'business': business},
        }).load();
        final item = page.items.single;
        expect(item.business, business);
        expect(item.contentId, '9007199254740993');
        expect(item.bvid, '');
        expect(item.position, Duration.zero);
        expect(item.coverUrl?.toString(), 'https://i0.hdslb.com/history.jpg');
        expect(item.deletionKey, '${business}_9007199254740997');
        expect(item.isLive, true);
        expect(page.nextCursor, '1:1791324000:$business');
      },
    );
    test('$business with no destination is a protocol failure', () async {
      final raw = contentHistory(business, '0');
      await expectLater(
        client({
          'list': [raw],
        }).load(),
        throwsA(isA<ApiFailure>()),
      );
    });
  }

  test(
    'course history extracts an episode without retaining remote URL queries',
    () async {
      final raw = contentHistory('cheese', '0')
        ..['uri'] = 'https://www.bilibili.com/cheese/play/ep123?from=history';
      final page = await client({
        'list': [raw],
        'cursor': {'max': 0, 'view_at': 0, 'business': ''},
      }).load();
      expect(page.items.single.contentId, '123');
    },
  );

  test(
    'search maps mixed histories without changing the page-number cursor',
    () async {
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'list': [
              entry(),
              for (final b in ['live', 'article', 'article-list', 'cheese'])
                contentHistory(b, '12'),
            ],
          },
        },
      );
      final page = await WatchHistoryClient(
        BiliApiClient(transport: transport),
      ).load(keyword: '关键词');
      expect(page.items, hasLength(5));
      expect(page.nextCursor, '2');
    },
  );
}
