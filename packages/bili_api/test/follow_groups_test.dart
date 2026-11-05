import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final includeReserved in [false, true]) {
    test('group picker reserved visibility $includeReserved', () async {
      final api = BiliApiClient(
        transport: _Transport((uri) {
          expect(uri.path, '/x/relation/tags');
          return [
            {'tagid': -10, 'name': '特别关注'},
            {'tagid': 0, 'name': '默认分组'},
            {'tagid': '9007199254740993123', 'name': '自定义分组'},
            {'tagid': 0, 'name': '重复默认分组'},
          ];
        }),
      );
      addTearDown(api.close);
      final groups = await FollowGroupClient(
        api,
      ).groups(includeReserved: includeReserved);
      expect(groups.map((group) => group.id), [
        if (includeReserved) '-10',
        '0',
        '9007199254740993123',
      ]);
      expect(() => groups.clear(), throwsUnsupportedError);
    });
  }

  test(
    'group members use array paging and preserve decimal identities',
    () async {
      final api = BiliApiClient(
        transport: _Transport((uri) {
          expect(uri.path, '/x/relation/tag');
          expect(uri.queryParameters, {
            'mid': '9007199254740993123',
            'tagid': '-10',
            'pn': uri.queryParameters['pn'],
            'ps': '30',
          });
          return uri.queryParameters['pn'] == '1'
              ? List.generate(
                  30,
                  (index) => {
                    'mid': '90071992547409931$index',
                    'uname': '用户$index',
                    'face': '//i0.hdslb.com/avatar.jpg',
                    'sign': '签名',
                  },
                )
              : null;
        }),
      );
      addTearDown(api.close);
      final client = ProfileClient(api);
      final first = await client.loadFollowingGroup(
        '9007199254740993123',
        '-10',
        page: 1,
      );
      expect(first.items.first.userMid, '900719925474099310');
      expect(first.items.first.kind, ApiProfileEntryKind.user);
      expect(first.items.first.coverUrl?.scheme, 'https');
      expect(first.items.first.subtitle, '签名');
      expect(first.hasMore, true);
      expect(first.nextCursor, '2');
      expect(() => first.items.clear(), throwsUnsupportedError);
      final next = await client.loadFollowingGroup(
        '9007199254740993123',
        '-10',
        page: 2,
      );
      expect(next.items, isEmpty);
      expect(next.hasMore, false);
      expect(next.nextCursor, isNull);
    },
  );

  for (final data in <Object>[
    {'list': []},
    [
      {'mid': 1},
    ],
    [
      {'mid': 1.5, 'uname': '无效 ID'},
    ],
  ]) {
    test(
      'malformed group members fail instead of returning empty: $data',
      () async {
        final api = BiliApiClient(transport: _Transport((_) => data));
        addTearDown(api.close);
        await expectLater(
          ProfileClient(api).loadFollowingGroup('7', '0', page: 1),
          throwsA(
            isA<ApiFailure>().having(
              (error) => error.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
      },
    );
  }

  test(
    'short group page ends and invalid parameters never reach transport',
    () async {
      var calls = 0;
      final api = BiliApiClient(
        transport: _Transport((_) {
          calls++;
          return [
            {'mid': '9', 'uname': '用户'},
          ];
        }),
      );
      addTearDown(api.close);
      final client = ProfileClient(api);
      expect(
        (await client.loadFollowingGroup('7', '0', page: 1)).hasMore,
        false,
      );
      for (final group in ['all', '1.5', '01', '']) {
        await expectLater(
          client.loadFollowingGroup('7', group, page: 1),
          throwsArgumentError,
        );
      }
      await expectLater(
        client.loadFollowingGroup('7', '0', page: 0),
        throwsArgumentError,
      );
      expect(calls, 1);
    },
  );
}

final class _Transport implements ApiTransport {
  _Transport(this.data);
  final Object? Function(Uri) data;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async => ApiHttpResponse(
    200,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data(uri)}))),
    const {},
  );
}
