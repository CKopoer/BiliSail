import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _aid = '9007199254740993123';
const _feedback = ApiRecommendationFeedback(
  aid: _aid,
  goto: 'av',
  trackId: 'opaque +&% context',
  ownerMid: '9007199254740993124',
);

ApiHttpResponse _response(Object? data, {int status = 200, int code = 0}) =>
    ApiHttpResponse(
      status,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': code, 'data': data}))),
      const {},
    );

void main() {
  late _Transport transport;
  late BiliApiClient api;
  late _Session session;
  setUp(() {
    transport = _Transport();
    session = _Session();
    api = BiliApiClient(
      transport: transport,
      sessionProvider: session,
      cookieJar:
          ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/'), [
            'SESSDATA=fixture; Path=/; Secure',
            'bili_jct=fixture-csrf; Path=/; Secure',
          ]),
    );
  });
  tearDown(() => api.close());

  test(
    'delete submits numeric aid exactly once with scoped Cookie and CSRF',
    () async {
      await FeedCardActionsClient(api).removeWatchLater(_aid);
      expect(transport.uri?.path, '/x/v2/history/toview/del');
      expect(transport.fields, {'aid': _aid, 'csrf': 'fixture-csrf'});
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      expect(transport.posts, 1);
    },
  );
  test(
    'feedback preserves raw tracking context and official reason without encoding twice',
    () async {
      await FeedCardActionsClient(api).rejectRecommendation(_feedback);
      expect(transport.uri?.path, '/x/web-interface/feedback/dislike');
      expect(transport.fields, {
        'app_id': '100',
        'platform': '5',
        'from_spmid': '',
        'spmid': '333.1007.0.0',
        'goto': 'av',
        'id': _aid,
        'mid': _feedback.ownerMid,
        'track_id': _feedback.trackId,
        'feedback_page': '1',
        'reason_id': '1',
        'csrf': 'fixture-csrf',
      });
    },
  );
  test(
    'official empty tracking default remains a supported feedback context',
    () async {
      await FeedCardActionsClient(api).rejectRecommendation(
        const ApiRecommendationFeedback(
          aid: '42',
          goto: 'av',
          trackId: '',
          ownerMid: '0',
        ),
      );
      expect(transport.fields['track_id'], '');
      expect(transport.posts, 1);
    },
  );
  test(
    'undo sends the original feedback fields and CSRF once to cancel',
    () async {
      await FeedCardActionsClient(api).rejectRecommendation(_feedback);
      final original = Map<String, String>.of(transport.fields);
      await FeedCardActionsClient(api).undoRecommendationFeedback(_feedback);
      expect(transport.uri?.path, '/x/web-interface/feedback/dislike/cancel');
      expect(transport.fields, original);
      expect(transport.headers['Cookie'], contains('SESSDATA=fixture'));
      expect(transport.posts, 2);
    },
  );
  test('failed undo is not retried automatically', () async {
    transport.result = _response(null, status: 503);
    await expectLater(
      FeedCardActionsClient(api).undoRecommendationFeedback(_feedback),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, 1);
  });
  test(
    'recommendation reads carry real aid/goto/owner/tracking with empty defaults',
    () async {
      transport.entries = [
        {
          'id': _aid,
          'goto': 'av',
          'track_id': _feedback.trackId,
          'owner': {'mid': _feedback.ownerMid},
        },
        {'id': 42, 'goto': 'av'},
        {'goto': 'av'},
        {'id': 43.5, 'goto': 'av'},
      ];
      final items = (await api.getRecommended()).items;
      final context = items.first.recommendationFeedback;
      expect(context?.aid, _aid);
      expect(context?.trackId, _feedback.trackId);
      expect(context?.ownerMid, _feedback.ownerMid);
      expect(items[1].recommendationFeedback?.trackId, '');
      expect(items[1].recommendationFeedback?.ownerMid, '0');
      expect(items[2].recommendationFeedback, isNull);
      expect(items[3].recommendationFeedback, isNull);
    },
  );
  for (final failure in [
    _response(null, status: 503),
    _response(null, code: -101),
  ]) {
    test(
      'write failure is never automatically retried: ${failure.statusCode}',
      () async {
        transport.result = failure;
        await expectLater(
          FeedCardActionsClient(api).rejectRecommendation(_feedback),
          throwsA(isA<ApiFailure>()),
        );
        expect(transport.posts, 1);
      },
    );
  }
  test(
    'missing credentials and nonmatching cookie path prevent transmission',
    () async {
      final guest = BiliApiClient(
        transport: transport,
        cookieJar:
            ApiCookieJar()..receive(Uri.https('api.bilibili.com', '/private'), [
              'SESSDATA=fixture; Path=/private; Secure',
              'bili_jct=fixture; Path=/private; Secure',
            ]),
      );
      addTearDown(guest.close);
      await expectLater(
        FeedCardActionsClient(guest).removeWatchLater('42'),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.authentication,
          ),
        ),
      );
      expect(transport.posts, 0);
    },
  );
  test(
    'cancelled, expired or stale epoch contexts cannot send writes',
    () async {
      for (final context in [
        ApiRequestContext(cancellation: ApiCancellation()..cancel()),
        ApiRequestContext(deadline: DateTime(2020)),
        const ApiRequestContext(sessionEpoch: 0),
      ]) {
        await expectLater(
          FeedCardActionsClient(api).removeWatchLater('42', context: context),
          throwsA(isA<ApiFailure>()),
        );
        await expectLater(
          FeedCardActionsClient(
            api,
          ).undoRecommendationFeedback(_feedback, context: context),
          throwsA(isA<ApiFailure>()),
        );
      }
      expect(transport.posts, 0);
    },
  );
  test('account changes discard a late successful mutation reply', () async {
    transport.pending = Completer<ApiHttpResponse>();
    final write = FeedCardActionsClient(
      api,
    ).removeWatchLater('42', context: const ApiRequestContext(sessionEpoch: 1));
    final check = expectLater(
      write,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    session.sessionEpoch++;
    transport.pending?.complete(_response(null));
    await check;
    expect(transport.posts, 1);
  });
}

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  ApiHttpResponse result = _response(null);
  Completer<ApiHttpResponse>? pending;
  List<Map<String, Object?>> entries = [];
  int posts = 0;
  Uri? uri;
  Map<String, String> fields = {}, headers = {};
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path.endsWith('/nav')) {
      return _response({
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      });
    }
    return _response({
      'item': [
        for (final entry in entries)
          {'bvid': 'BV1234567890', 'title': '推荐', ...entry},
      ],
    });
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    this.uri = uri;
    this.fields = fields;
    this.headers = headers;
    posts++;
    return pending?.future ?? result;
  }
}
