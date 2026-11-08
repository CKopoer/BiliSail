import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test('portal and uplist preserve server order and decimal IDs', () async {
    final transport = _Transport(
      (uri) => uri.path.endsWith('portal')
          ? {
              'up_list': {
                'items': [
                  _author('9007199254740993123'),
                  _author(7),
                  _author(7),
                ],
                'has_more': true,
                'offset': 'opaque+&cursor',
              },
            }
          : {
              'items': [_author(8)],
              'has_more': false,
            },
    );
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    final client = HomeClient(api);
    final first = await client.dynamicAuthors();
    expect(first.items.map((item) => item.mid), ['9007199254740993123', '7']);
    expect(
      first.items.first.avatarUrl.toString(),
      'https://i0.hdslb.com/avatar.jpg',
    );
    expect(first.items.first.hasUpdate, isTrue);
    expect(transport.uris.first.queryParameters['up_list_more'], '1');
    final next = await client.dynamicAuthors(cursor: first.nextCursor);
    expect(next.items.single.mid, '8');
    expect(transport.uris.last.path, '/x/polymer/web-dynamic/v1/uplist');
    expect(transport.uris.last.queryParameters['offset'], 'opaque+&cursor');
  });

  for (final malformed in <Map<String, Object?>>[
    {},
    {'items': 'bad'},
    {
      'items': [_author(1.5)],
    },
    {
      'items': [_author('0')],
    },
    {
      'items': [_author('-1')],
    },
    {'items': [], 'has_more': true},
    {'items': [], 'has_more': true, 'offset': 'same'},
  ]) {
    test('rejects malformed author response $malformed', () async {
      final api = BiliApiClient(transport: _Transport((_) => malformed));
      addTearDown(api.close);
      await expectLater(
        HomeClient(api).dynamicAuthors(cursor: 'same'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }

  for (final (channel, section, ids) in [
    ('dynamic', '全部', ['1', '2', '3']),
    ('dynamic', '图文', ['1', '2']),
    ('dynamic', '视频', ['3']),
    ('videoDynamic', '最新视频', ['3']),
  ]) {
    test(
      '$channel $section filters every page for the selected author',
      () async {
        final transport = _Transport(
          (_) => {
            'items': [_post('1', 'WORD'), _post('2', 'DRAW'), _post('3', 'AV')],
            'has_more': true,
            'offset': 'next',
          },
        );
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        final result = await HomeClient(api).load(
          channel: channel,
          section: section,
          page: 2,
          cursor: 'old+&cursor',
          authorId: '9007199254740993123',
        );
        expect(result.items.map((item) => item.id), ids);
        expect(result.nextCursor, 'next');
        expect(
          transport.uris.single.queryParameters,
          containsPair('host_mid', '9007199254740993123'),
        );
        expect(transport.uris.single.queryParameters['offset'], 'old+&cursor');
        expect(
          transport.uris.single.queryParameters['features'],
          'itemOpusStyle',
        );
        expect(
          transport.uris.single.queryParameters.containsKey('type'),
          isFalse,
        );
      },
    );
  }

  test(
    'an author page with no matching videos still advances its cursor',
    () async {
      final api = BiliApiClient(
        transport: _Transport(
          (_) => {
            'items': [_post('1', 'WORD')],
            'has_more': true,
            'offset': 'next',
          },
        ),
      );
      addTearDown(api.close);
      final result = await HomeClient(
        api,
      ).load(channel: 'videoDynamic', section: '最新视频', page: 1, authorId: '7');
      expect(result.items, isEmpty);
      expect(result.hasMore, isTrue);
      expect(result.nextCursor, 'next');
    },
  );

  test('invalid requested author is rejected before HTTP', () async {
    final transport = _Transport((_) => {});
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    await expectLater(
      HomeClient(api).load(
        channel: 'dynamic',
        section: '全部',
        page: 1,
        authorId: '7&host_mid=8',
      ),
      throwsArgumentError,
    );
    expect(transport.uris, isEmpty);
  });
}

Map<String, Object?> _author(Object mid) => {
  'mid': mid,
  'uname': '测试 UP 主',
  'face': '//i0.hdslb.com/avatar.jpg',
  'has_update': true,
};

Map<String, Object?> _post(String id, String type) => {
  'id_str': id,
  'type': 'DYNAMIC_TYPE_$type',
  'modules': {
    'module_author': {'mid': '9007199254740993123', 'name': '测试 UP 主'},
    'module_dynamic': {
      'desc': {'text': '动态正文'},
      if (type == 'AV')
        'major': {
          'archive': {'bvid': 'BV1234567890', 'title': '视频'},
        },
    },
  },
};

final class _Transport implements ApiTransport {
  _Transport(this.response);
  final Map<String, Object?> Function(Uri) response;
  final uris = <Uri>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    return ApiHttpResponse(
      200,
      Uint8List.fromList(
        utf8.encode(jsonEncode({'code': 0, 'data': response(uri)})),
      ),
      const {},
    );
  }
}
