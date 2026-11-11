import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _id = '9007199254740993123';
Map<String, Object?> _info() => {
  'vote_id': _id,
  'title': '测试投票',
  'desc': '选择一至两项',
  'choice_cnt': 2,
  'end_time': 2000000000,
  'join_num': 5,
  'options': [
    {'opt_idx': 4, 'opt_desc': '文字选项', 'cnt': 2},
    {
      'opt_idx': 9,
      'opt_desc': '图片选项',
      'cnt': 3,
      'img_url': '//i0.hdslb.com/test.jpg',
    },
  ],
};

void main() {
  late _Transport transport;
  late DynamicPollClient client;
  setUp(() {
    transport = _Transport();
    client = DynamicPollClient(
      BiliApiClient(
        transport: transport,
        cookieJar: ApiCookieJar()
          ..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Path=/; Secure',
            'bili_jct=fixture-csrf; Path=/; Secure',
          ]),
      ),
    );
  });

  test(
    'detail reads separated my_votes and preserves server option identities',
    () async {
      final poll = await client.detail(_id);
      expect(transport.uri?.path, '/x/vote/vote_info');
      expect(transport.uri?.queryParameters, {'vote_id': _id});
      expect(poll.id, _id);
      expect(poll.myVotes, {9});
      expect(poll.options.map((o) => o.index), [4, 9]);
      expect(
        poll.options.last.imageUrl.toString(),
        'https://i0.hdslb.com/test.jpg',
      );
      expect(poll.endsAt.millisecondsSinceEpoch, 2000000000000);
      expect(() => poll.myVotes.add(4), throwsUnsupportedError);
    },
  );

  test(
    'one JSON vote carries exact integer IDs, choices, anonymity and scoped CSRF',
    () async {
      transport.data = {
        'vote_info': {
          ..._info(),
          'my_votes': [4, 9],
        },
      };
      final poll = await client.vote(
        id: _id,
        voterId: '7',
        choices: [4, 9],
        anonymous: true,
        dynamicId: '9007199254740993124',
      );
      expect(poll.myVotes, {4, 9});
      expect(transport.uri?.path, '/x/vote/do_vote');
      expect(transport.uri?.queryParameters, {'csrf': 'fixture-csrf'});
      expect(transport.body, {
        'vote_id': int.parse(_id),
        'voter_uid': 7,
        'votes': [4, 9],
        'status': 1,
        'op_bit': 0,
        'dynamic_id': 9007199254740993124,
        'csrf': 'fixture-csrf',
        'csrf_token': 'fixture-csrf',
      });
      expect(jsonDecode(jsonEncode(transport.body))['vote_id'].toString(), _id);
      expect(transport.posts, 1);
    },
  );

  test(
    'confirmed success without my_votes still records submitted choices',
    () async {
      transport.data = {'vote_info': _info()};
      final poll = await client.vote(
        id: _id,
        voterId: '7',
        choices: [9],
        anonymous: false,
      );
      expect(poll.myVotes, {9});
      expect(transport.body['status'], 0);
      expect(transport.body['dynamic_id'], 0);
    },
  );

  test(
    'mismatched, duplicate, oversized or invalid option data fails closed',
    () async {
      for (final info in [
        {..._info(), 'vote_id': '8'},
        {..._info(), 'choice_cnt': 3},
        {..._info(), 'end_time': 0},
        {
          ..._info(),
          'options': List.filled(21, {'opt_idx': 1, 'opt_desc': 'x'}),
        },
        {
          ..._info(),
          'options': [
            {'opt_idx': 1, 'opt_desc': 'a'},
            {'opt_idx': 1, 'opt_desc': 'b'},
          ],
        },
        {
          ..._info(),
          'options': [
            {'opt_idx': 1.2, 'opt_desc': 'a'},
            {'opt_idx': 2, 'opt_desc': 'b'},
          ],
        },
      ]) {
        transport.data = {'vote_info': info};
        await expectLater(client.detail(_id), throwsA(isA<ApiFailure>()));
      }
      transport.data = {
        'vote_info': _info(),
        'my_votes': [42],
      };
      await expectLater(client.detail(_id), throwsA(isA<ApiFailure>()));
    },
  );

  test('invalid input and guests never send a vote', () async {
    for (final choices in [
      <int>[],
      [1, 1],
      [-1],
      List.generate(21, (i) => i),
    ]) {
      await expectLater(
        client.vote(id: _id, voterId: '7', choices: choices, anonymous: false),
        throwsArgumentError,
      );
    }
    await expectLater(
      client.vote(id: '1.2', voterId: '7', choices: [4], anonymous: false),
      throwsArgumentError,
    );
    await expectLater(
      DynamicPollClient(
        BiliApiClient(transport: transport),
      ).vote(id: _id, voterId: '7', choices: [4], anonymous: false),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 0);
  });

  test(
    'uncertain writes are single attempt and account changes reject late success',
    () async {
      transport.status = 503;
      await expectLater(
        client.vote(id: _id, voterId: '7', choices: [4], anonymous: false),
        throwsA(isA<ApiFailure>()),
      );
      expect(transport.posts, 1);
      final session = _Session();
      final scoped = DynamicPollClient(
        BiliApiClient(
          transport: transport,
          cookieJar: client.api.cookieJar,
          sessionProvider: session,
        ),
      );
      transport.status = 200;
      transport.data = {
        'vote_info': {
          ..._info(),
          'my_votes': [4],
        },
      };
      transport.pending = Completer<ApiHttpResponse>();
      final pending = scoped.vote(
        id: _id,
        voterId: '7',
        choices: [4],
        anonymous: false,
        context: ApiRequestContext(sessionEpoch: 1),
      );
      await Future<void>.delayed(Duration.zero);
      session.epoch++;
      transport.pending!.complete(transport.response());
      await expectLater(
        pending,
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.cancelled,
          ),
        ),
      );
      expect(transport.posts, 2);
    },
  );
}

final class _Session implements ApiSessionProvider {
  int epoch = 1;
  @override
  int get sessionEpoch => epoch;
}

final class _Transport implements ApiTransport, ApiJsonTransport {
  Uri? uri;
  int posts = 0, status = 200;
  Map<String, Object?> body = {};
  Object? data = {
    'vote_info': _info(),
    'my_votes': [9],
  };
  Completer<ApiHttpResponse>? pending;
  ApiHttpResponse response() => ApiHttpResponse(
    status,
    Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
    const {},
  );
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    return response();
  }

  @override
  Future<ApiHttpResponse> postJson(
    Uri uri, {
    required Map<String, Object?> body,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.body = body;
    posts++;
    return pending?.future ?? response();
  }
}
