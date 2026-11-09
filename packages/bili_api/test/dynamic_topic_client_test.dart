import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'dynamic_post_test.dart' show post;

final class TopicTransport implements ApiTransport {
  TopicTransport(this.data, {this.code = 0});
  final Map<String, Object?> data;
  final int code;
  final requests = <Uri>[];
  final headers = <Map<String, String>>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    requests.add(uri);
    this.headers.add(headers);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(
          jsonEncode({'code': code, 'message': '服务端错误', 'data': data}),
        ),
      ),
      {},
    );
  }
}

Map<String, Object?> top({Object id = '9007199254740993123'}) => {
  'top_details': {
    'topic_item': {
      'id': id,
      'name': '话题名称',
      'description': '话题简介',
      'view': 123,
      'discuss': 45,
      'fav': 10,
      'is_fav': true,
    },
    'topic_creator': {
      'uid': '9007199254740993124',
      'name': '发起人',
      'face': '//i0.hdslb.com/face.png',
    },
  },
};
Map<String, Object?> feed({
  String? cursor,
  bool more = false,
  List<Object?>? items,
}) => {
  'topic_card_list': {
    'items':
        items ??
        [
          {'topic_type': 'DYNAMIC', 'dynamic_card_item': post(id: '12')},
        ],
    'offset': cursor,
    'has_more': more,
    'topic_sort_by_conf': {
      'show_sort_by': 2,
      'all_sort_by': [
        {'sort_by': 0, 'sort_name': '综合'},
        {'sort_by': 2, 'sort_name': '最新'},
      ],
    },
  },
};

void main() {
  test(
    'an explicitly absent topic feed is a legitimate empty result',
    () async {
      final value = await DynamicTopicClient(
        BiliApiClient(transport: TopicTransport({'topic_card_list': null})),
      ).feed('1');
      expect(value.posts, isEmpty);
      expect(value.hasMore, isFalse);
    },
  );
  test(
    'topic header uses the registered Web read on app host and preserves exact identities',
    () async {
      final transport = TopicTransport(top());
      final api = BiliApiClient(transport: transport);
      final value = await DynamicTopicClient(api).detail('9007199254740993123');
      expect(value.id, '9007199254740993123');
      expect(
        (value.name, value.description, value.viewCount, value.discussCount),
        ('话题名称', '话题简介', 123, 45),
      );
      expect(value.creatorId, '9007199254740993124');
      expect((value.isFavorite, value.favoriteCount), (true, 10));
      expect(value.creatorAvatar?.scheme, 'https');
      expect(transport.requests.single.host, 'app.bilibili.com');
      expect(transport.requests.single.path, '/x/topic/web/details/top');
      expect(transport.requests.single.queryParameters, {
        'topic_id': value.id,
        'source': 'Web',
      });
      expect(
        () => api.requestJson(
          Uri.https('app.bilibili.com', '/arbitrary'),
          'invalid',
        ),
        throwsArgumentError,
      );
    },
  );

  test(
    'header mismatch, missing data and noninteger identity fail explicitly',
    () async {
      for (final data in [<String, Object?>{}, top(id: '2'), top(id: 1.5)]) {
        expect(
          DynamicTopicClient(
            BiliApiClient(transport: TopicTransport(data)),
          ).detail('1'),
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
    'feed retains dynamic content, server sorts, folds and opaque cursor encoding',
    () async {
      const cursor = '页 /?#%&=原样';
      final transport = TopicTransport(
        feed(
          cursor: cursor,
          more: true,
          items: [
            {
              'dynamic_card_item': post(
                id: '12',
                nodes: [
                  {
                    'type': 'RICH_TEXT_NODE_TYPE_TOPIC',
                    'text': '#话题#',
                    'rid': '34',
                  },
                ],
              ),
            },
            {
              'fold_card_item': {'fold_count': 5, 'fold_desc': '查看5条折叠内容'},
            },
            {'topic_type': 'UNKNOWN', 'future': {}},
          ],
        ),
      );
      final value = await DynamicTopicClient(
        BiliApiClient(transport: transport),
      ).feed('1', sort: 2, cursor: cursor);
      expect(value.posts.single.id, '12');
      expect(
        value.posts.single.spans.single.linkUrl?.queryParameters['topic_id'],
        '34',
      );
      expect(value.hasMore, isTrue);
      expect(value.nextCursor, cursor);
      expect(value.selectedSort, 2);
      expect(value.sorts.map((s) => (s.id, s.name)), [(0, '综合'), (2, '最新')]);
      expect(value.foldDescription, '查看5条折叠内容');
      final uri = transport.requests.single;
      expect(uri.host, 'api.bilibili.com');
      expect(uri.path, '/x/polymer/web-dynamic/v1/feed/topic');
      expect(uri.queryParameters['offset'], cursor);
      expect(uri.queryParameters['page_size'], '20');
      expect(uri.queryParameters['features'], 'itemOpusStyle');
      expect(() => value.posts.clear(), throwsUnsupportedError);
      expect(() => value.sorts.clear(), throwsUnsupportedError);
    },
  );

  test('folded content is a separate bounded read', () async {
    final transport = TopicTransport(
      feed(
        items: List.generate(
          100,
          (i) => {'dynamic_card_item': post(id: '${i + 1}')},
        ),
      ),
    );
    final value = await DynamicTopicClient(
      BiliApiClient(transport: transport),
    ).feed('1', sort: 2, folded: true);
    expect(value.posts, hasLength(50));
    expect(transport.requests.single.path, '/x/topic/web/details/fold');
    expect(
      transport.requests.single.queryParameters.containsKey('offset'),
      isFalse,
    );
  });

  test(
    'empty page is distinct from malformed and authentication failures',
    () async {
      final page = await DynamicTopicClient(
        BiliApiClient(transport: TopicTransport(feed(items: []))),
      ).feed('1');
      expect(page.posts, isEmpty);
      expect(page.hasMore, isFalse);
      for (final data in [
        <String, Object?>{},
        {
          'topic_card_list': {'items': 'broken'},
        },
        feed(
          items: [
            {'dynamic_card_item': []},
          ],
        ),
        feed(cursor: 'x' * 2049),
      ]) {
        await expectLater(
          DynamicTopicClient(
            BiliApiClient(transport: TopicTransport(data)),
          ).feed('1'),
          throwsA(isA<ApiFailure>()),
        );
      }
      await expectLater(
        DynamicTopicClient(
          BiliApiClient(transport: TopicTransport({}, code: -101)),
        ).detail('1'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
    },
  );

  test('invalid input never reaches transport', () async {
    final transport = TopicTransport({});
    final client = DynamicTopicClient(BiliApiClient(transport: transport));
    for (final id in ['0', '-1', '1.0', 'x' * 129]) {
      await expectLater(client.detail(id), throwsArgumentError);
      await expectLater(client.feed(id), throwsArgumentError);
    }
    await expectLater(client.feed('1', sort: -1), throwsArgumentError);
    await expectLater(
      client.feed('1', cursor: 'x' * 2049),
      throwsArgumentError,
    );
    expect(transport.requests, isEmpty);
  });
}
