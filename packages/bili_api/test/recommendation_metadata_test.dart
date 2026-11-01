import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
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
  Object? followed;
  Object? reason = const {'content': '已关注'};
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
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

  List<Map<String, Object?>> get _items => [
    {
      'bvid': 'BV1234567890',
      'title': '视频',
      'duration': 60,
      'is_followed': followed,
      'rcmd_reason': reason,
    },
  ];
}
