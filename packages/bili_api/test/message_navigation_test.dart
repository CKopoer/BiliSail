import 'dart:convert';
import 'dart:typed_data';
import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  for (final type in ['reply', 'video']) {
    test('liked $type uses a comment address only for reply items', () async {
      final transport = _Transport(
        _page(ApiInboxSection.likes, {
          'uri': 'https://www.bilibili.com/video/av170001',
          'type': type,
          'item_id': '202',
          'root_id': '200',
        }),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final entry = (await MessageClient(
        api,
      ).notifications(ApiInboxSection.likes)).items.single;
      expect(
        entry.targetUrl?.queryParameters,
        type == 'reply'
            ? {'comment_root_id': '200', 'comment_secondary_id': '202'}
            : isEmpty,
      );
    });
  }
  for (final section in [
    ApiInboxSection.replies,
    ApiInboxSection.mentions,
    ApiInboxSection.likes,
  ]) {
    test(
      '$section prefers native comment address and preserves exact IDs',
      () async {
        final transport = _Transport({});
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        transport.data = _page(section, {
          'uri': 'https://www.bilibili.com/video/av170001',
          'native_uri':
              'bilibili://video/170001/?comment_root_id=9007199254740993&comment_secondary_id=9007199254740994&cid=999&dm_progress=12000',
        });
        final entry = (await MessageClient(
          api,
        ).notifications(section)).items.single;
        expect(entry.targetUrl?.path, '/video/BV17x411w7KC');
        expect(entry.targetUrl?.queryParameters, {
          'comment_root_id': '9007199254740993',
          'comment_secondary_id': '9007199254740994',
          'cid': '999',
          'dm_progress': '12000',
        });
      },
    );
  }

  test(
    'notification source/root IDs are independent from row and old target IDs',
    () async {
      final transport = _Transport(
        _page(ApiInboxSection.replies, {
          'uri': 'https://www.bilibili.com/video/av170001',
          'business_id': 1,
          'subject_id': '170001',
          'source_id': '202',
          'root_id': '200',
          'target_id': '201',
        }),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final entry = (await MessageClient(
        api,
      ).notifications(ApiInboxSection.replies)).items.single;
      expect(entry.targetUrl?.path, '/video/BV17x411w7KC');
      expect(entry.targetUrl?.queryParameters, {
        'comment_root_id': '200',
        'comment_secondary_id': '202',
      });
    },
  );

  for (final (source, path, query) in [
    (
      'bilibili://comment/msg_fold/1/170001/200/300/?anchor=202',
      '/video/BV17x411w7KC',
      {'comment_root_id': '200', 'comment_secondary_id': '202'},
    ),
    (
      'https://www.bilibili.com/h5/comment/sub?oid=170001&pageType=1&root=200&comment_secondary_id=202',
      '/video/BV17x411w7KC',
      {
        'oid': '170001',
        'pageType': '1',
        'root': '200',
        'comment_root_id': '200',
        'comment_secondary_id': '202',
      },
    ),
    (
      'bilibili://pgc/season/ep/123/?start_progress=9000&comment_root_id=200',
      '/bangumi/play/ep123',
      {'start_progress': '9000', 'comment_root_id': '200'},
    ),
  ]) {
    test('normalizes $source', () async {
      final transport = _Transport(
        _page(ApiInboxSection.likes, {'native_uri': source}),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final entry = (await MessageClient(
        api,
      ).notifications(ApiInboxSection.likes)).items.single;
      expect(entry.targetUrl?.path, path);
      expect(entry.targetUrl?.queryParameters, query);
    });
  }

  test(
    'invalid native target falls back to valid web URL; danmaku is not a comment',
    () async {
      final transport = _Transport(
        _page(ApiInboxSection.replies, {
          'native_uri': 'bilibili://video/extra/170001',
          'uri': 'https://www.bilibili.com/video/av170001?dm_progress=12000',
          'business': '弹幕',
          'source_id': '202',
          'root_id': '200',
        }),
      );
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final entry = (await MessageClient(
        api,
      ).notifications(ApiInboxSection.replies)).items.single;
      expect(entry.targetUrl?.queryParameters, {'dm_progress': '12000'});
      expect(entry.replyContext, isNull);
    },
  );

  test(
    'root read validates identity and retains rich nested content',
    () async {
      final transport = _Transport({
        'root': _comment('200'),
        'upper': {'mid': '7'},
      });
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final root = await api.getVideoCommentRoot('170001', '200');
      expect(root.id, '200');
      expect(root.isUpAuthor, isTrue);
      expect(transport.uris.single.path, '/x/v2/reply/reply');
      expect(transport.uris.single.queryParameters, {
        'oid': '170001',
        'root': '200',
        'type': '1',
        'pn': '1',
        'ps': '20',
      });
      transport.data = {'root': _comment('201')};
      await expectLater(
        api.getVideoCommentRoot('170001', '200'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
      transport.data = {'root': null};
      await expectLater(
        api.getVideoCommentRoot('170001', '200'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.notFound,
          ),
        ),
      );
    },
  );
}

Map<String, Object?> _comment(String id) => {
  'rpid_str': id,
  'root': 0,
  'member': {'uname': '作者', 'mid': '7'},
  'content': {'message': '评论'},
};
Object _page(ApiInboxSection section, Object item) {
  final data = {
    'items': [
      {'id': '999', 'item': item},
    ],
    'cursor': {'id': '999', 'time': '1', 'is_end': true},
  };
  return section == ApiInboxSection.likes ? {'total': data} : data;
}

final class _Transport implements ApiTransport {
  _Transport(this.data);
  Object data;
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
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
