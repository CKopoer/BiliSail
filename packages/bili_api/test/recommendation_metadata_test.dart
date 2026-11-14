import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'desktop uses signed PC parameters for initial, refresh and pagination',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      for (final (index, loadMore, freshType) in [
        (0, false, '0'),
        (1, false, '3'),
        (2, true, '4'),
      ]) {
        final page = await api.getDesktopRecommended(
          freshIndex: index,
          loadMore: loadMore,
        );
        final request = transport.requests.last;
        expect(request.host, 'api.bilibili.com');
        expect(request.path, '/x/web-interface/wbi/index/top/feed/rcmd');
        final query = Map.of(request.queryParameters);
        expect(query.remove('w_rid'), matches(RegExp(r'^[0-9a-f]{32}$')));
        expect(int.tryParse(query.remove('wts') ?? ''), isNotNull);
        expect(query, {
          'plat': '1',
          'feed_version': 'V1',
          'ps': '30',
          'fresh_idx': '$index',
          'fresh_type': freshType,
          'x_num': '3',
          'y_num': '4',
          'pc_wx_install': '0',
          'pc_wx_gm_install': '0',
        });
        expect(page.items.single.bvid, 'BV1234567890');
        expect(page.hasMore, isTrue);
        expect(page.nextCursor, '${index + 1}');
      }
      final before = transport.requests.length;
      await expectLater(
        api.getDesktopRecommended(freshIndex: -1),
        throwsArgumentError,
      );
      expect(transport.requests.length, before);
    },
  );

  test('desktop preserves video metadata and excludes non-video ads', () async {
    final transport = _Transport()..includeAds = true;
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    final item = (await api.getDesktopRecommended(freshIndex: 0)).items.single;
    expect(item.title, '视频');
    expect(item.duration, const Duration(seconds: 60));
    expect(item.recommendationReason, '已关注');
    expect(item.isFollowed, isNull);
    transport.onlyAds = true;
    final empty = await api.getDesktopRecommended(freshIndex: 1);
    expect(empty.items, isEmpty);
    expect(empty.hasMore, isFalse);
    expect(empty.nextCursor, isNull);
  });

  test(
    'Web recommendation text stays independent of explicit follow status',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      for (final (value, expected) in <(Object?, String?)>[
        ({'content': ' 3万点赞 ', 'reason_type': 1}, '3万点赞'),
        ({'content': '关注的人也在看'}, '关注的人也在看'),
        (' 新关注 ', '新关注'),
        (null, null),
        ({}, null),
        ({'content': ' '}, null),
        ({'content': 12}, null),
        ([], null),
      ]) {
        transport.reason = value;
        for (final followed in [null, 0, 1]) {
          transport.followed = followed;
          final item = (await api.getRecommended()).items.single;
          expect(item.recommendationReason, expected);
          expect(item.isFollowed, followed == null ? null : followed == 1);
          expect(item.likeCount, isNull);
        }
      }
    },
  );

  test(
    'optional metadata keeps unknown counts and explicit follow status',
    () async {
      final transport = _Transport();
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      for (final (value, expected) in <(Object?, bool?)>[
        (null, null),
        (1, true),
        (0, false),
        (true, true),
        (false, false),
        ('1', null),
        ('已关注', null),
      ]) {
        transport.followed = value;
        final item = (await api.getRelatedVideos('BV1234567890')).single;
        expect(item.isFollowed, expected);
        expect(item.likeCount, isNull);
        expect(item.playCount, isNull);
        expect(item.categoryName, isNull);
      }
    },
  );
}

final class _Transport implements ApiTransport {
  final requests = <Uri>[];
  bool includeAds = false;
  bool onlyAds = false;
  Object? followed;
  Object? reason = const {'content': '已关注'};
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
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'code': 0,
            'data': uri.path.endsWith('/nav')
                ? {
                    'wbi_img': {
                      'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                      'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
                    },
                  }
                : uri.path.endsWith('/rcmd')
                ? {'item': _items}
                : _items,
          }),
        ),
      ),
      const {},
    );
  }

  List<Map<String, Object?>> get _items => [
    if (includeAds) {'goto': 'ad_av'},
    if (includeAds) {'goto': 'live'},
    if (!onlyAds)
      {
        'bvid': 'BV1234567890',
        'title': '视频',
        'duration': 60,
        'is_followed': followed,
        'rcmd_reason': reason,
      },
  ];
}
