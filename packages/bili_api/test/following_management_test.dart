import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

import 'message_client_test.dart' show Transport, cookies, response;

void main() {
  late Transport transport;
  late BiliApiClient api;
  setUp(() {
    transport = Transport();
    api = BiliApiClient(transport: transport, cookieJar: cookies());
  });
  tearDown(() => api.close());

  test('following search signs raw text once and uses remote totals', () async {
    transport.handler = (uri) {
      if (uri.path.endsWith('/nav')) {
        return {
          'wbi_img': {
            'img_url':
                'https://i0.hdslb.com/bfs/wbi/7cd084941338484aae1ad9425b84077c.png',
            'sub_url':
                'https://i0.hdslb.com/bfs/wbi/4932caff0ff746eab6f01bf08b70ac45.png',
          },
        };
      }
      expect(uri.path, '/x/relation/followings/search');
      expect(uri.queryParameters['name'], '中文 & + %');
      expect(uri.queryParameters['pn'], '2');
      expect(uri.queryParameters['ps'], '30');
      expect(uri.queryParameters['vmid'], '7');
      expect(uri.queryParameters['w_rid'], matches(r'^[a-f0-9]{32}$'));
      return {
        'total': 61,
        'list': [
          {'mid': '9007199254740993123', 'uname': '搜索结果', 'sign': '简介'},
        ],
      };
    };
    final page = await ProfileClient(
      api,
    ).searchFollowing('7', ' 中文 & + % ', page: 2);
    expect(page.items.single.userMid, '9007199254740993123');
    expect(page.hasMore, true);
    expect(page.nextCursor, '3');
  });

  test('blacklist pages stop at total and allow a null empty list', () async {
    transport.handler = (uri) {
      expect(uri.path, '/x/relation/blacks');
      expect(uri.queryParameters, {'pn': '1', 'ps': '30', 'order': 'desc'});
      return {'total': 0, 'list': null};
    };
    final page = await ProfileClient(api).loadBlacklist(page: 1);
    expect(page.items, isEmpty);
    expect(page.hasMore, false);
    transport.handler = (_) => {
      'total': 31,
      'list': [
        {'mid': '9', 'uname': '用户'},
      ],
    };
    expect((await ProfileClient(api).loadBlacklist(page: 2)).hasMore, false);
  });

  test(
    'following sort preserves existing default request parameters',
    () async {
      transport.handler = (uri) {
        expect(uri.queryParameters['order_type'], 'attention');
        return {'total': 0, 'list': []};
      };
      await ProfileClient(
        api,
      ).loadRelations('7', followers: false, page: 1, orderType: 'attention');
    },
  );

  test('group writes use exact endpoints, raw fields and CSRF', () async {
    final groups = FollowGroupClient(api);
    transport.postResult = response({'tagid': '9007199254740993123'});
    final created = await groups.create(' 中文 & + % ');
    expect(created.id, '9007199254740993123');
    expect(created.name, '中文 & + %');
    expect(transport.uri?.path, '/x/relation/tag/create');
    expect(transport.fields, containsPair('tag', '中文 & + %'));
    expect(transport.fields, containsPair('csrf', 'csrf-fixture'));
    await groups.rename('9007199254740993123', '新名称');
    expect(transport.uri?.path, '/x/relation/tag/update');
    expect(transport.fields['tagid'], '9007199254740993123');
    expect(transport.fields['name'], '新名称');
    await groups.delete('1');
    expect(transport.uri?.path, '/x/relation/tag/del');
    await groups.sort(['2', '1']);
    expect(transport.uri?.path, '/x/relation/tags/update_sort');
    expect(transport.fields['tagids'], '2,1');
    expect(transport.posts, 4);
  });

  test(
    'invalid names, reserved groups and duplicate ordering never write',
    () async {
      final groups = FollowGroupClient(api);
      await expectLater(groups.create(' '), throwsArgumentError);
      await expectLater(groups.create('长' * 17), throwsArgumentError);
      for (final id in ['0', '-10', '01', 'x']) {
        await expectLater(groups.rename(id, '分组'), throwsArgumentError);
        await expectLater(groups.delete(id), throwsArgumentError);
        await expectLater(groups.sort([id]), throwsArgumentError);
      }
      await expectLater(groups.sort(['1', '1']), throwsArgumentError);
      await expectLater(groups.sort([]), throwsArgumentError);
      expect(transport.posts, 0);
    },
  );

  test('failed writes are never automatically repeated', () async {
    transport.postResult = response(null, status: 503);
    await expectLater(
      FollowGroupClient(api).create('分组'),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 1);
  });

  test(
    'creation requires a real positive tag identity without replaying writes',
    () async {
      for (final data in [
        null,
        {},
        {'tagid': 0},
        {'tagid': -1},
        {'tagid': 1.5},
      ]) {
        transport.postResult = response(data);
        final before = transport.posts;
        await expectLater(
          FollowGroupClient(api).create('分组'),
          throwsA(
            isA<ApiFailure>().having(
              (error) => error.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
        expect(transport.posts, before + 1);
      }
    },
  );

  test('malformed relation responses do not become empty success', () async {
    for (final data in [
      <String, Object?>{},
      {'total': 1, 'list': null},
      {
        'total': 1,
        'list': [
          {'mid': 1.5, 'uname': '无效'},
        ],
      },
    ]) {
      transport.handler = (_) => data;
      await expectLater(
        ProfileClient(api).loadBlacklist(page: 1),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    }
  });
}
