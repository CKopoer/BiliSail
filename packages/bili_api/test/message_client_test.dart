import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

ApiHttpResponse response(Object? data, {int code = 0, int status = 200}) =>
    ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );
Map<String, Object?> message({
  String sequence = '9007199254740993123',
  int type = 1,
  int status = 0,
  String? content,
}) => {
  'sender_uid': '123',
  'msg_type': type,
  'msg_seqno': sequence,
  'msg_key': sequence,
  'timestamp': 1700000000,
  'msg_status': status,
  'content': content ?? jsonEncode({'content': '中文 & + %'}),
};
ApiCookieJar cookies({String domain = '.bilibili.com'}) =>
    ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
      'SESSDATA=fixture; Domain=$domain; Path=/; Secure',
      'bili_jct=csrf-fixture; Domain=$domain; Path=/; Secure',
    ]);

final class Transport implements ApiTransport, ApiFormTransport {
  Object? Function(Uri) handler = (_) => {};
  ApiHttpResponse postResult = response({});
  int posts = 0, gets = 0;
  Map<String, String> fields = {}, headers = {};
  Uri? uri;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    gets++;
    return response(handler(uri));
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts++;
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    return postResult;
  }
}

void main() {
  late Transport transport;
  late MessageClient client;
  setUp(() {
    transport = Transport();
    client = MessageClient(
      BiliApiClient(transport: transport, cookieJar: cookies()),
    );
  });
  test(
    'sessions keep microsecond cursor, large IDs and keyed user cards',
    () async {
      transport.handler = (uri) {
        if (uri.path.endsWith('/cards')) {
          return {
            '9007199254740993123': {'mid': '9007199254740993123', 'name': '甲'},
          };
        }
        expect(uri.host, 'api.vc.bilibili.com');
        expect(uri.queryParameters['end_ts'], '1700000000000000');
        return {
          'session_list': [
            {
              'talker_id': '9007199254740993123',
              'session_type': 1,
              'session_ts': '1690000000000000',
              'unread_count': 2,
              'max_seqno': '9007199254740993123',
              'last_msg': message(),
            },
          ],
          'has_more': 1,
        };
      };
      final result = await client.sessions(cursor: '1700000000000000');
      expect(result.items.single.title, '甲');
      expect(result.items.single.userMid, '9007199254740993123');
      expect(result.nextCursor, '1690000000000000');
      expect(result.items.single.unread, 2);
      expect(result.hasMore, isTrue);
    },
  );
  test(
    'empty sessions stop without fetching cards; malformed responses fail',
    () async {
      transport.handler = (_) => {'session_list': null, 'has_more': 1};
      expect((await client.sessions()).hasMore, isFalse);
      expect(transport.gets, 1);
      transport.handler = (_) => {};
      await expectLater(client.sessions(), throwsA(isA<ApiFailure>()));
    },
  );
  test('thread sorts decimal sequences without float conversion', () async {
    transport.handler = (uri) {
      expect(uri.queryParameters['end_seqno'], '9007199254740993999');
      return {
        'messages': [
          {...message(sequence: '9007199254740993124'), 'msg_key': 0},
          {...message(), 'msg_key': 0},
        ],
        'has_more': 1,
      };
    };
    final page = await client.thread('123', 1, cursor: '9007199254740993999');
    expect(page.items.first.sequence, '9007199254740993123');
    expect(page.items.map((item) => item.id).toSet().length, 2);
    expect(page.nextCursor, '9007199254740993123');
    transport.handler = (_) => {
      'messages': [message()],
      'has_more': 1,
    };
    expect(
      (await client.thread('123', 1, cursor: '9007199254740993123')).hasMore,
      isFalse,
    );
  });
  test('recalled text and pictures are never exposed', () async {
    transport.handler = (_) => {
      'messages': [
        message(status: 1, type: 2, content: 'private malformed content'),
      ],
      'has_more': 0,
    };
    final entry = (await client.thread('123', 1)).items.single;
    expect(entry.text, '消息已撤回');
    expect(entry.imageUrl, isNull);
    expect(entry.targetUrl, isNull);
  });
  test('unknown message types degrade visibly; malformed JSON fails', () async {
    transport.handler = (_) => {
      'messages': [message(type: 99, content: '{}')],
      'has_more': 0,
    };
    expect((await client.thread('123', 1)).items.single.text, contains('99'));
    transport.handler = (_) => {
      'messages': [message(content: '{bad')],
      'has_more': 0,
    };
    await expectLater(client.thread('123', 1), throwsA(isA<ApiFailure>()));
  });
  test('reply cursor keeps exact ID/time; empty notices are valid', () async {
    transport.handler = (uri) {
      expect(uri.queryParameters['id'], '9007199254740993123');
      expect(uri.queryParameters['reply_time'], '1700000000');
      return {
        'items': [],
        'cursor': {'id': 0, 'time': 0, 'is_end': true},
      };
    };
    expect(
      (await client.notifications(
        ApiInboxSection.replies,
        cursor: '9007199254740993123:1700000000',
      )).hasMore,
      isFalse,
    );
  });
  test('likes merge latest and total without duplicates', () async {
    final item = {
      'id': '9',
      'users': [
        {'mid': '123', 'nickname': '甲'},
      ],
      'item': {
        'title': '视频',
        'uri': 'http://www.bilibili.com/video/BV1234567890',
      },
      'like_time': 1700000000,
    };
    transport.handler = (_) => {
      'latest': {
        'items': [item],
      },
      'total': {
        'items': [item],
        'cursor': {'id': 9, 'time': 1700000000, 'is_end': true},
      },
    };
    final list = (await client.notifications(ApiInboxSection.likes)).items;
    expect(list.length, 1);
    expect(list.single.targetUrl?.scheme, 'https');
  });
  test('system notices use message host and accept formatted dates', () async {
    transport.handler = (uri) {
      expect(uri.host, 'message.bilibili.com');
      return {
        'system_notify_list': [
          {
            'id': 9,
            'title': '通知',
            'content': '正文',
            'time_at': '2026-10-05 12:00:00',
          },
        ],
      };
    };
    expect(
      (await client.notifications(ApiInboxSection.system)).items.single.time,
      isNotNull,
    );
  });
  test(
    'empty system response is a verified empty page, not an invented cursor',
    () async {
      transport.handler = (_) => {};
      expect(
        (await client.notifications(ApiInboxSection.system)).items,
        isEmpty,
      );
      await expectLater(
        client.notifications(ApiInboxSection.system, cursor: '123'),
        throwsArgumentError,
      );
    },
  );
  test(
    'send preserves raw Unicode/form text and destination-scoped CSRF',
    () async {
      await client.sendText('123', '456', '中文 & + %\n第二行');
      expect(transport.uri?.host, 'api.vc.bilibili.com');
      expect(
        jsonDecode(transport.fields['msg[content]'] ?? '')['content'],
        '中文 & + %\n第二行',
      );
      expect(transport.fields['csrf'], 'csrf-fixture');
      expect(transport.fields['csrf_token'], 'csrf-fixture');
      expect(transport.headers['Origin'], 'https://message.bilibili.com');
      expect(transport.posts, 1);
    },
  );
  test(
    'send failures never retry and host-only cookies cannot leak to VC',
    () async {
      transport.postResult = response(null, status: 503);
      await expectLater(
        client.sendText('123', '456', 'hello'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
      final scoped = MessageClient(
        BiliApiClient(
          transport: transport,
          cookieJar: cookies(domain: 'api.bilibili.com'),
        ),
      );
      await expectLater(
        scoped.sendText('123', '456', 'hello'),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
    },
  );
  test('cancelled sends and invalid input never reach transport', () async {
    await expectLater(
      client.sendText(
        '123',
        '456',
        'hello',
        context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(client.sendText('123', '456', ''), throwsArgumentError);
    await expectLater(
      client.sendText('123', '456', '啊' * 1001),
      throwsArgumentError,
    );
    expect(transport.posts, 0);
  });
  test('ack preserves sequence and is sent once', () async {
    await client.markRead('123', 1, '9007199254740993123');
    expect(transport.fields['ack_seqno'], '9007199254740993123');
    expect(transport.posts, 1);
  });
  test('overview handles full level and unavailable next experience', () async {
    transport.handler = (uri) => uri.path.endsWith('/stat')
        ? {'following': 80, 'follower': 10, 'dynamic_count': 29}
        : {
            'isLogin': true,
            'mid': 123,
            'level_info': {
              'current_level': 6,
              'current_exp': 43362,
              'next_exp': '--',
            },
          };
    final data = await AccountClient(
      BiliApiClient(transport: transport),
    ).overview('123');
    expect(data.level, 6);
    expect(data.nextExperience, isNull);
    expect(data.dynamics, 29);
  });
}
