import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

class _Transport implements ApiTransport {
  _Transport(this.reply);
  final FutureOr<Object> Function(Uri) reply;
  final requests = <Uri>[];
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
      Uint8List.fromList(utf8.encode(jsonEncode(await reply(uri)))),
      const {},
    );
  }
}

void main() {
  test(
    'comment mentions preserve string IDs and fall back to members',
    () async {
      final content = {
        'message': '回复 @reader :comment',
        'at_name_to_mid_str': {'reader': '9007199254740993'},
        'at_name_to_mid': {'reader': 42, 'numeric': 43},
        'members': [
          {'uname': 'reader', 'mid': '44'},
          {'uname': 'member', 'mid': '45'},
        ],
      };
      final api = BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'page': {'count': 1, 'size': 20},
              'replies': [
                {
                  'rpid': '10',
                  'member': {'uname': 'author'},
                  'content': content,
                  'replies': [
                    {
                      'rpid': '11',
                      'member': {'uname': 'reply author'},
                      'content': content,
                    },
                  ],
                },
              ],
            },
          },
        ),
      );
      addTearDown(api.close);
      for (final page in [
        await api.getVideoComments('42'),
        await api.getVideoReplies('42', '10'),
      ]) {
        for (final comment in [
          page.items.single,
          page.items.single.replies.single,
        ]) {
          expect(comment.mentionedUsers, {
            'reader': '9007199254740993',
            'numeric': '43',
            'member': '45',
          });
          expect(() => comment.mentionedUsers.clear(), throwsUnsupportedError);
        }
      }
    },
  );

  test('optional malformed mention fields do not remove comments', () async {
    for (final fields in <Map<String, Object?>>[
      {},
      {'at_name_to_mid_str': [], 'at_name_to_mid': 'invalid', 'members': {}},
      {
        'at_name_to_mid_str': {'zero': '0', 'float': 42.0, 'invalid': 'abc'},
        'at_name_to_mid': {'': 42, ' \n ': 43, 'negative': -1, 'null': null},
        'members': [
          null,
          'invalid',
          {},
          {'uname': 'reader', 'mid': 0},
        ],
      },
    ]) {
      final api = BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'page': {'count': 1, 'size': 20},
              'replies': [
                {
                  'rpid': '10',
                  'member': {'uname': 'author'},
                  'content': {'message': 'reply', ...fields},
                },
              ],
            },
          },
        ),
      );
      addTearDown(api.close);
      final comment = (await api.getVideoComments('42')).items.single;
      expect(comment.message, 'reply');
      expect(comment.mentionedUsers, isEmpty);
    }
  });

  test('comment mention metadata has a bounded size', () async {
    final api = BiliApiClient(
      transport: _Transport(
        (_) => {
          'code': 0,
          'data': {
            'page': {'count': 1, 'size': 20},
            'replies': [
              {
                'rpid': '10',
                'member': {'uname': 'author'},
                'content': {
                  'message': 'reply',
                  'at_name_to_mid_str': {
                    for (var i = 1; i <= 120; i++) 'user$i': '$i',
                  },
                  'members': [
                    {'uname': 'extra', 'mid': '121'},
                  ],
                },
              },
            ],
          },
        },
      ),
    );
    addTearDown(api.close);
    expect(
      (await api.getVideoComments('42')).items.single.mentionedUsers,
      hasLength(100),
    );
  });

  test('comment locations map for roots, previews and reply pages', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'data': {
          'page': {'count': 1, 'size': 20},
          'replies': [
            {
              'rpid': '10',
              'member': {'uname': 'reader'},
              'content': {'message': 'comment'},
              'reply_control': {'location': ' IP属地：广东 '},
              'replies': [
                {
                  'rpid': '11',
                  'member': {'uname': 'reply author'},
                  'content': {'message': 'reply'},
                  'reply_control': {'location': 'IP属地：上海'},
                },
              ],
            },
          ],
        },
      },
    );
    final api = BiliApiClient(transport: transport);
    for (final page in [
      await api.getVideoComments('42'),
      await api.getVideoReplies('42', '10'),
    ]) {
      expect(page.items.single.ipLocation, 'IP属地：广东');
      expect(page.items.single.replies.single.ipLocation, 'IP属地：上海');
    }
    expect(transport.requests.map((uri) => uri.path), [
      '/x/v2/reply',
      '/x/v2/reply/reply',
    ]);
  });

  test('missing or malformed optional locations preserve comments', () async {
    for (final control in <Object?>[
      null,
      'invalid',
      <Object?>[],
      <String, Object?>{},
      {'location': null},
      {'location': 42},
      {'location': ''},
      {'location': ' \n '},
    ]) {
      final api = BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'page': {'count': 1, 'size': 20},
              'replies': [
                {
                  'rpid': '10',
                  'member': {'uname': 'reader'},
                  'content': {'message': 'comment'},
                  'reply_control': control,
                },
              ],
            },
          },
        ),
      );
      final comment = (await api.getVideoComments('42')).items.single;
      expect(comment.ipLocation, isNull);
      expect(comment.message, 'comment');
    }
  });

  test(
    'video tags preserve names, deduplicate and use the video bvid',
    () async {
      final transport = _Transport(
        (_) => {
          'code': 0,
          'data': [
            {'tag_name': ' Flutter & Dart/中文+测试 ', 'tag_type': 'topic'},
            {'tag_name': 'Flutter & Dart/中文+测试'},
            {'tag_name': '编程'},
            {'tag_name': '  '},
          ],
        },
      );
      final tags = await BiliApiClient(
        transport: transport,
      ).getVideoTags('BV1234567890');
      expect(tags, ['Flutter & Dart/中文+测试', '编程']);
      expect(transport.requests.single.path, '/x/tag/archive/tags');
      expect(transport.requests.single.queryParameters, {
        'bvid': 'BV1234567890',
      });
      expect(() => tags.add('other'), throwsUnsupportedError);
    },
  );

  test('video tags accept empty lists and bound the response', () async {
    final empty = BiliApiClient(
      transport: _Transport((_) => {'code': 0, 'data': <Object?>[]}),
    );
    expect(await empty.getVideoTags('BV1234567890'), isEmpty);
    final bounded = BiliApiClient(
      transport: _Transport(
        (_) => {
          'code': 0,
          'data': List.generate(120, (index) => {'tag_name': '标签$index'}),
        },
      ),
    );
    expect(await bounded.getVideoTags('BV1234567890'), hasLength(100));
  });

  test('malformed video tags fail explicitly', () async {
    for (final data in <Object?>[
      null,
      <String, Object?>{},
      [null],
      [<String, Object?>{}],
      [
        {'tag_name': 12},
      ],
    ]) {
      final api = BiliApiClient(
        transport: _Transport((_) => {'code': 0, 'data': data}),
      );
      await expectLater(
        api.getVideoTags('BV1234567890'),
        throwsA(
          isA<ApiFailure>().having(
            (error) => error.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    }
  });

  test('cancelled video tags discard a late transport response', () async {
    final reply = Completer<Object>();
    final signal = ApiCancellation();
    final api = BiliApiClient(transport: _Transport((_) => reply.future));
    final result = api.getVideoTags(
      'BV1234567890',
      context: ApiRequestContext(cancellation: signal),
    );
    final expectation = expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (error) => error.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    signal.cancel();
    reply.complete({
      'code': 0,
      'data': [
        {'tag_name': '旧标签'},
      ],
    });
    await expectation;
  });

  test('legacy latest guest empty page is an explicit empty success', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'data': {
          'page': {'num': 0, 'size': 0, 'count': 0, 'acount': 0},
          'replies': null,
          'control': {'input_disable': false},
        },
      },
    );
    final result = await BiliApiClient(
      transport: transport,
    ).getVideoComments('42', sort: ApiCommentSort.latest);
    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
    expect(result.totalCount, 0);
    expect(transport.requests.single.queryParameters['sort'], '0');
  });

  test('sorting, pinned dedup and bounded nested replies', () async {
    Map<String, Object?> comment(
      String id, {
      List<Object?> replies = const [],
    }) => {
      'rpid_str': id,
      'member': {
        'uname': 'Reader',
        'mid': id == '23' ? 123 : '9007199254740993',
      },
      'content': {'message': 'Comment'},
      'action': 1,
      'rcount': 32,
      'root_str': '0',
      'replies': replies,
    };
    final top = comment(
      '9007199254740993',
      replies: [
        comment('23', replies: [comment('24')]),
      ],
    );
    final transport = _Transport(
      (_) => {
        'code': 0,
        'data': {
          'upper': {'top': top},
          'replies': [top],
          'page': {'count': 32, 'size': 20},
        },
      },
    );
    final api = BiliApiClient(transport: transport);
    final result = await api.getVideoComments(
      '42',
      sort: ApiCommentSort.latest,
    );
    expect(transport.requests.last.queryParameters['sort'], '0');
    expect(result.items, hasLength(1));
    expect(result.totalCount, 32);
    expect(result.items.single.authorMid, '9007199254740993');
    expect(result.items.single.replies.single.authorMid, '123');
    expect(result.items.single.liked, isTrue);
    expect(result.items.single.replyCount, 32);
    expect(result.items.single.rootId, isNull);
    expect(result.items.single.replies.single.replies, isEmpty);
    await api.getVideoReplies('42', '9007199254740993', page: 2);
    expect(transport.requests.last.path, '/x/v2/reply/reply');
    expect(transport.requests.last.queryParameters['root'], '9007199254740993');
    expect(transport.requests.last.queryParameters['pn'], '2');
  });

  test('collection preserves nested parts and deduplicates episodes', () async {
    final episode = {
      'bvid': 'BV1234567890',
      'title': 'Episode',
      'arc': {'duration': 30},
      'pages': [
        {'cid': '9007199254740993', 'page': 1, 'part': 'Part', 'duration': 30},
      ],
    };
    final api = BiliApiClient(
      transport: _Transport(
        (_) => {
          'code': 0,
          'data': {
            'aid': '42',
            'bvid': 'BV1234567890',
            'title': 'Video',
            'pages': episode['pages'],
            'ugc_season': {
              'id': '9007199254740994',
              'title': 'Collection',
              'stat': {'view': 12340000},
              'sections': [
                {
                  'episodes': [
                    episode,
                    episode,
                    {'bvid': 'BV0987654321', 'title': 'Other'},
                  ],
                },
              ],
            },
          },
        },
      ),
    );
    final detail = await api.getVideoDetail('BV1234567890');
    expect(detail.collection?.id, '9007199254740994');
    expect(detail.collection?.entries, hasLength(2));
    expect(detail.collection?.playCount, 12340000);
    expect(
      detail.collection?.entries.first.duration,
      const Duration(seconds: 30),
    );
    expect(detail.collection?.entries.last.duration, isNull);
    expect(
      detail.collection?.entries.first.pages.single.cid,
      '9007199254740993',
    );
    expect(detail.collection?.entries.last.pages, isEmpty);
  });

  test('related endpoint parses list payload and immutable results', () async {
    final transport = _Transport(
      (uri) => {
        'code': 0,
        'data': [
          {
            'bvid': 'BV1234567890',
            'title': 'Related',
            'duration': 72,
            'owner': {'name': 'Creator', 'mid': 456},
            'stat': {'view': 42},
          },
        ],
      },
    );
    final entries = await BiliApiClient(
      transport: transport,
    ).getRelatedVideos('BV0987654321');
    expect(transport.requests.single.path, '/x/web-interface/archive/related');
    expect(transport.requests.single.queryParameters, {'bvid': 'BV0987654321'});
    expect(entries.single.ownerMid, '456');
    expect(entries.single.duration, const Duration(seconds: 72));
    expect(() => entries.clear(), throwsUnsupportedError);
  });

  test('comments preserve string IDs and server paging', () async {
    final transport = _Transport(
      (uri) => {
        'code': 0,
        'data': {
          'page': {'count': 50, 'size': 20},
          'replies': [
            {
              'rpid_str': '90071992547409931',
              'member': {
                'uname': 'Reader',
                'avatar': '//i0.hdslb.com/avatar.jpg',
              },
              'content': {'message': 'A comment'},
              'like': 3,
              'ctime': 1700000000,
            },
          ],
        },
      },
    );
    final client = BiliApiClient(transport: transport);
    final first = await client.getVideoComments('90071992547409932');
    expect(first.items.single.id, '90071992547409931');
    expect(first.items.single.avatarUrl?.scheme, 'https');
    expect(first.hasMore, isTrue);
    expect(first.nextCursor, '2');
    final last = await client.getVideoComments('90071992547409932', page: 3);
    expect(last.hasMore, isFalse);
    expect(transport.requests.last.queryParameters['oid'], '90071992547409932');
    expect(transport.requests.last.queryParameters['sort'], '1');
  });

  test(
    'empty comments accept null replies but malformed entries fail',
    () async {
      var malformed = false;
      final client = BiliApiClient(
        transport: _Transport(
          (_) => {
            'code': 0,
            'data': {
              'page': {'count': 0, 'size': 20},
              'replies': malformed ? [{}] : null,
            },
          },
        ),
      );
      expect((await client.getVideoComments('42')).items, isEmpty);
      malformed = true;
      await expectLater(
        client.getVideoComments('42'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );

  test('risk control is reported without retry or fallback', () async {
    final transport = _Transport((_) => {'code': -352});
    await expectLater(
      BiliApiClient(transport: transport).getVideoComments('42'),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.rateLimited,
        ),
      ),
    );
    expect(transport.requests, hasLength(1));
  });

  test('cancelled comments discard late responses', () async {
    final response = Completer<Object>();
    final transport = _Transport((_) => response.future);
    final cancellation = ApiCancellation();
    final result = BiliApiClient(transport: transport).getVideoComments(
      '42',
      context: ApiRequestContext(cancellation: cancellation),
    );
    cancellation.cancel();
    response.complete({'code': 0, 'data': {}});
    await expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
  });

  test('Web client pipeline supports result and rejects other hosts', () async {
    final transport = _Transport(
      (_) => {
        'code': 0,
        'result': {'list': []},
      },
    );
    final client = BiliApiClient(transport: transport);
    expect(
      await client.requestJson(
        Uri.https('api.bilibili.com', '/pgc/test'),
        'pgc_test',
      ),
      {'list': []},
    );
    expect(
      () => client.requestJson(Uri.https('example.com', '/'), 'test'),
      throwsArgumentError,
    );
    expect(transport.requests, hasLength(1));
  });
}
