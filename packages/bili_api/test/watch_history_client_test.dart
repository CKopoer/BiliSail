import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'home_client_test.dart' show Transport;

Map<String, Object?> entry({
  String business = 'archive',
  Object progress = 30,
  Object timestamp = 1791324000,
}) => {
  'title': '云端历史',
  'cover': '//i0.hdslb.com/cover.jpg',
  'author_name': '作者',
  'author_mid': '9007199254740993',
  'duration': 100,
  'progress': progress,
  'view_at': timestamp,
  'history': {
    'business': business,
    'bvid': 'BV1234567890',
    'cid': '9007199254740995',
    'epid': 123,
    'page': 2,
    'part': '第二 P',
  },
};

WatchHistoryClient client(Map<String, Object?> data) => WatchHistoryClient(
  BiliApiClient(transport: Transport((_) => {'code': 0, 'data': data})),
);

void main() {
  test(
    'cloud cursor retains IDs, seconds, watch time and part identity',
    () async {
      final transport = Transport(
        (_) => {
          'code': 0,
          'data': {
            'list': [entry()],
            'cursor': {
              'max': '9007199254740997',
              'view_at': 1791324000,
              'business': 'archive',
            },
          },
        },
      );
      final page = await WatchHistoryClient(
        BiliApiClient(transport: transport),
      ).load();
      expect(transport.requests.single.path, '/x/web-interface/history/cursor');
      expect(transport.requests.single.queryParameters, {
        'ps': '20',
        'max': '0',
        'view_at': '0',
        'business': '',
      });
      final item = page.items.single;
      expect(item.cid, '9007199254740995');
      expect(item.authorMid, '9007199254740993');
      expect(item.page, 2);
      expect(item.position, const Duration(seconds: 30));
      expect(
        item.watchedAt,
        DateTime.fromMillisecondsSinceEpoch(1791324000000, isUtc: true),
      );
      expect(item.coverUrl?.scheme, 'https');
      expect(page.nextCursor, '9007199254740997:1791324000:archive');
      expect(page.hasMore, true);
    },
  );

  test('sends all three cursor fields unchanged', () async {
    final transport = Transport(
      (_) => {
        'code': 0,
        'data': {'list': []},
      },
    );
    final page = await WatchHistoryClient(
      BiliApiClient(transport: transport),
    ).load(cursor: '9007199254740997:1791324000:pgc');
    expect(transport.requests.single.queryParameters, {
      'ps': '20',
      'max': '9007199254740997',
      'view_at': '1791324000',
      'business': 'pgc',
    });
    expect(page.hasMore, false);
  });

  for (final progress in [-1, 0, 200]) {
    test('progress $progress is completed/zero/clamped in seconds', () async {
      final page = await client({
        'list': [entry(progress: '$progress')],
        'cursor': {'max': 0, 'view_at': 0, 'business': ''},
      }).load();
      expect(page.items.single.position.inSeconds, progress == 0 ? 0 : 100);
      expect(page.hasMore, false);
    });
  }

  test('PGC preserves episode identity without a BVID/cid', () async {
    final raw = entry(business: 'pgc');
    raw['history'] = {
      'business': 'pgc',
      'bvid': '',
      'cid': 0,
      'epid': '9007199254740993',
    };
    final page = await client({
      'list': [raw],
      'cursor': {'max': 0, 'view_at': 0, 'business': ''},
    }).load();
    expect(page.items.single.episodeId, '9007199254740993');
    expect(page.items.single.cid, '');
  });

  test(
    'unsupported business still advances the mixed history cursor',
    () async {
      final page = await client({
        'list': [entry(business: 'live')],
        'cursor': {'max': 42, 'view_at': 1791324000, 'business': 'live'},
      }).load();
      expect(page.items, isEmpty);
      expect(page.hasMore, true);
    },
  );

  for (final data in <Map<String, Object?>>[
    {'list': 'bad'},
    {
      'list': [entry(timestamp: 0)],
    },
    {
      'list': [entry(progress: -2)],
    },
    {
      'list': [entry()],
      'cursor': {'max': 1.5, 'view_at': 1, 'business': 'archive'},
    },
  ]) {
    test('malformed response is a protocol failure: $data', () async {
      await expectLater(
        client(data).load(),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }

  test(
    'stalled cursor and malformed input cannot create pagination loops',
    () async {
      final history = client({
        'list': [entry()],
        'cursor': {'max': 1, 'view_at': 2, 'business': 'archive'},
      });
      await expectLater(
        history.load(cursor: '1:2:archive'),
        throwsA(isA<ApiFailure>()),
      );
      await expectLater(
        history.load(cursor: '1:2:archive&foo=bar'),
        throwsArgumentError,
      );
    },
  );
}
