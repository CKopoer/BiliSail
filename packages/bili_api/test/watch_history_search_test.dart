import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'home_client_test.dart' show Transport;
import 'watch_history_client_test.dart' show entry;

void main() {
  test('search sends a trimmed keyword once and uses numbered pages', () async {
    final transport = Transport(
      (_) => {
        'code': 0,
        'data': {
          'list': [entry(), entry(business: 'pgc')],
        },
      },
    );
    final client = WatchHistoryClient(BiliApiClient(transport: transport));
    const keyword = '中文 & + % / ?';
    final first = await client.load(keyword: '  $keyword  ');
    expect(transport.requests.single.path, '/x/web-interface/history/search');
    expect(transport.requests.single.queryParameters, {
      'keyword': keyword,
      'pn': '1',
      'business': 'all',
    });
    expect(first.items, hasLength(2));
    expect(first.items.first.deletionKey, 'archive_9007199254740997');
    expect(first.items.last.episodeId, '123');
    expect(first.items.first.position, const Duration(seconds: 30));
    expect(first.nextCursor, '2');
    expect(first.hasMore, true);
    final second = await client.load(
      keyword: keyword,
      cursor: first.nextCursor,
    );
    expect(transport.requests.last.queryParameters['pn'], '2');
    expect(second.nextCursor, '3');
  });

  for (final list in [null, <Object?>[]]) {
    test('empty search $list ends paging without a cursor object', () async {
      final client = WatchHistoryClient(
        BiliApiClient(
          transport: Transport(
            (_) => {
              'code': 0,
              'data': {'list': list},
            },
          ),
        ),
      );
      final page = await client.load(keyword: '没有结果', cursor: '3');
      expect(page.items, isEmpty);
      expect(page.hasMore, false);
      expect(page.nextCursor, isNull);
    });
  }

  test('non-video results advance the raw search page', () async {
    final client = WatchHistoryClient(
      BiliApiClient(
        transport: Transport(
          (_) => {
            'code': 0,
            'data': {
              'list': [entry(business: 'live')],
            },
          },
        ),
      ),
    );
    final page = await client.load(keyword: '直播');
    expect(page.items, isEmpty);
    expect(page.hasMore, true);
    expect(page.nextCursor, '2');
  });

  for (final cursor in ['0', '-1', '01', '1:2:archive', 'bad']) {
    test('invalid search cursor $cursor makes no request', () async {
      final transport = Transport((_) => {});
      final client = WatchHistoryClient(BiliApiClient(transport: transport));
      await expectLater(
        client.load(keyword: '视频', cursor: cursor),
        throwsArgumentError,
      );
      expect(transport.requests, isEmpty);
    });
  }

  for (final data in <Map<String, Object?>>[
    {},
    {'list': 'bad'},
    {
      'list': [entry(progress: -2)],
    },
    {'list': List.filled(101, entry())},
  ]) {
    test(
      'malformed search results fail instead of appearing empty: ${data.keys}',
      () async {
        final client = WatchHistoryClient(
          BiliApiClient(transport: Transport((_) => {'code': 0, 'data': data})),
        );
        await expectLater(
          client.load(keyword: '视频'),
          throwsA(isA<ApiFailure>()),
        );
      },
    );
  }

  test('blank keyword restores the cloud cursor endpoint', () async {
    final transport = Transport(
      (_) => {
        'code': 0,
        'data': {'list': []},
      },
    );
    await WatchHistoryClient(
      BiliApiClient(transport: transport),
    ).load(keyword: '  ');
    expect(transport.requests.single.path, '/x/web-interface/history/cursor');
  });
}
