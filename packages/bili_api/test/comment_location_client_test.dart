import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _oid = '170001', _root = '9007199254740993', _reply = '9007199254740994';

void main() {
  for (final (jumpPage, replyPage) in [
    (1, 1),
    (2, 1),
    (3, 2),
    (58, 29),
    (100003, 50002),
  ]) {
    test(
      'comment ID resolves jump page $jumpPage directly to page $replyPage',
      () async {
        final transport = _Transport(jumpPage: jumpPage, replyPage: replyPage);
        final cookies = ApiCookieJar()
          ..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Domain=.bilibili.com; Path=/; Secure',
          ]);
        final api = BiliApiClient(transport: transport, cookieJar: cookies);
        addTearDown(api.close);
        final located = await api.getVideoCommentLocation(
          _oid,
          _root,
          replyId: _reply,
        );
        expect(located.root.id, _root);
        expect(located.page.items.single.id, _reply);
        expect(located.page.items.single.rootId, _root);
        expect(located.page.hasMore, isTrue);
        expect(located.pageNumber, replyPage);
        expect(located.page.nextCursor, '${replyPage + 1}');
        expect(transport.uris.map((uri) => uri.path), [
          '/x/v2/reply/jump',
          '/x/v2/reply/reply',
        ]);
        expect(transport.uris.first.queryParameters, {
          'oid': _oid,
          'type': '1',
          'rpid': _reply,
        });
        expect(transport.uris.last.queryParameters, {
          'oid': _oid,
          'type': '1',
          'root': _root,
          'pn': '$replyPage',
          'ps': '20',
        });
        expect(
          transport.headers.every(
            (headers) => headers['Cookie'] == 'SESSDATA=fixture',
          ),
          isTrue,
        );
      },
    );
  }

  test(
    'root-only location reads its first reply page without scanning',
    () async {
      final transport = _Transport()
        ..jump = {
          'replies': [_comment(_root)],
        };
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final located = await api.getVideoCommentLocation(_oid, _root);
      expect(transport.uris.first.queryParameters['rpid'], _root);
      expect(located.pageNumber, 1);
      expect(located.root.isUpAuthor, isFalse);
      expect(transport.uris, hasLength(2));
    },
  );

  for (final page in [null, 0, -1, 'not-a-page', 1.5, 0x80000000]) {
    test(
      'malformed server reply page $page does not start another read',
      () async {
        final transport = _Transport()
          ..jump = {
            'replies': [_comment(_root)],
            'page': {'rt_num': page},
          };
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        await expectLater(
          api.getVideoCommentLocation(_oid, _root, replyId: _reply),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.protocol,
            ),
          ),
        );
        expect(transport.uris, hasLength(1));
      },
    );
  }

  for (final (kind, root, category) in [
    ('missing root', null, ApiFailureCategory.notFound),
    (
      'wrong subject',
      {..._comment(_root), 'oid_str': '2'},
      ApiFailureCategory.protocol,
    ),
    (
      'wrong type',
      {..._comment(_root), 'type': 17},
      ApiFailureCategory.protocol,
    ),
    (
      'nested root',
      {..._comment(_root), 'root_str': '100'},
      ApiFailureCategory.protocol,
    ),
  ]) {
    test('$kind cannot select another thread', () async {
      final transport = _Transport()
        ..jump = {
          'replies': [?root],
          'page': {'rt_num': 1},
        };
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      await expectLater(
        api.getVideoCommentLocation(_oid, _root, replyId: _reply),
        throwsA(
          isA<ApiFailure>().having((e) => e.category, 'category', category),
        ),
      );
      expect(transport.uris, hasLength(1));
    });
  }

  for (final replies in [
    <Object?>[],
    [_comment('100', root: _root)],
    [_comment(_reply, root: '100')],
  ]) {
    test(
      'target absent or in another root is reported without fallback scanning: $replies',
      () async {
        final transport = _Transport()
          ..replyData = {
            'replies': replies,
            'page': {'count': 10000, 'size': 20},
          };
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        await expectLater(
          api.getVideoCommentLocation(_oid, _root, replyId: _reply),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.notFound,
            ),
          ),
        );
        expect(transport.uris, hasLength(2));
      },
    );
  }

  for (final code in [12006, 12022]) {
    test(
      'deleted or invisible comment $code is a non-retried not-found result',
      () async {
        final transport = _Transport()..code = code;
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        await expectLater(
          api.getVideoCommentLocation(_oid, _root, replyId: _reply),
          throwsA(
            isA<ApiFailure>()
                .having(
                  (e) => e.category,
                  'category',
                  ApiFailureCategory.notFound,
                )
                .having((e) => e.businessCode, 'businessCode', code),
          ),
        );
        expect(transport.uris, hasLength(1));
      },
    );
  }

  test('both reads retain the original deadline and exact identity', () async {
    var now = DateTime.utc(2026, 11, 14);
    final deadline = now.add(const Duration(seconds: 3));
    final transport = _Transport()
      ..afterJump = () => now = now.add(const Duration(seconds: 2));
    final api = BiliApiClient(transport: transport, clock: () => now);
    addTearDown(api.close);
    await api.getVideoCommentLocation(
      _oid,
      _root,
      replyId: _reply,
      context: ApiRequestContext(deadline: deadline),
    );
    expect(transport.timeouts, [
      const Duration(seconds: 2),
      const Duration(seconds: 1),
    ]);
  });

  for (final epochChange in [false, true]) {
    test(
      'cancellation or account change stops before the target page epoch=$epochChange',
      () async {
        final session = _Session();
        final cancellation = ApiCancellation();
        final transport = _Transport()
          ..afterJump = () {
            if (epochChange) {
              session.sessionEpoch++;
            } else {
              cancellation.cancel();
            }
          };
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: session,
        );
        addTearDown(api.close);
        await expectLater(
          api.getVideoCommentLocation(
            _oid,
            _root,
            replyId: _reply,
            context: ApiRequestContext(
              cancellation: cancellation,
              sessionEpoch: 0,
            ),
          ),
          throwsA(
            isA<ApiFailure>().having(
              (e) => e.category,
              'category',
              ApiFailureCategory.cancelled,
            ),
          ),
        );
        expect(transport.uris, hasLength(1));
      },
    );
  }
}

Map<String, Object?> _comment(String id, {String? root}) => {
  'rpid_str': id,
  'oid_str': _oid,
  'type': 1,
  'root_str': root ?? '0',
  'member': {'mid': '7', 'uname': '作者'},
  'content': {'message': '回复'},
};

class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

class _Transport implements ApiTransport {
  _Transport({this.jumpPage = 1, this.replyPage = 1});
  final int jumpPage, replyPage;
  Object? jump, replyData;
  int code = 0;
  void Function()? afterJump;
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  final timeouts = <Duration>[];
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    uris.add(uri);
    this.headers.add(headers);
    timeouts.add(timeout);
    final isJump = uri.path.endsWith('/jump');
    final data = isJump
        ? jump ??
              {
                'replies': [_comment(_root)],
                'page': {'rt_num': jumpPage, 'size': 20},
              }
        : replyData ??
              {
                'root': _comment(_root),
                'replies': [_comment(_reply, root: _root)],
                'page': {'count': (replyPage + 1) * 20, 'size': 20},
              };
    if (isJump) afterJump?.call();
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );
  }
}
