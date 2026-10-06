import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

const _bvid = 'BV1234567890';
const _cid = '9007199254740993';

void main() {
  late _Transport transport;
  late _Session session;
  late BiliApiClient api;
  late PlaybackHistoryClient client;
  setUp(() {
    transport = _Transport();
    session = _Session();
    api = BiliApiClient(
      transport: transport,
      sessionProvider: session,
      cookieJar: ApiCookieJar()
        ..receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture; Path=/; Secure',
          'bili_jct=fixture-csrf; Path=/; Secure',
        ]),
    );
    client = PlaybackHistoryClient(api);
  });
  tearDown(() => api.close());
  Future<void> report({bool completed = false}) => client.report(
    _bvid,
    _cid,
    position: const Duration(milliseconds: 42678),
    duration: const Duration(minutes: 2),
    completed: completed,
    context: ApiRequestContext(sessionEpoch: session.sessionEpoch),
  );

  test('WBI cloud read preserves large CID and millisecond progress', () async {
    expect(await client.read(_bvid, _cid), const Duration(milliseconds: 42678));
    final uri = transport.reads.last;
    expect(uri.path, '/x/player/wbi/v2');
    expect(uri.queryParameters['cid'], _cid);
    expect(uri.queryParameters['bvid'], _bvid);
    expect(uri.queryParameters['w_rid'], isNotEmpty);
  });
  for (final (data, expected) in <(Map<String, Object?>, Duration?)>[
    ({}, null),
    ({'last_play_time': 0, 'last_play_cid': 0}, null),
    ({'last_play_time': 50000, 'last_play_cid': '2'}, null),
    ({'last_play_time': -1, 'last_play_cid': _cid}, Duration.zero),
    ({'last_play_time': 0, 'last_play_cid': _cid}, Duration.zero),
  ]) {
    test('cloud history $data resolves to $expected', () async {
      transport.data = data;
      expect(await client.read(_bvid, _cid), expected);
    });
  }
  for (final data in [
    {'last_play_time': '50000', 'last_play_cid': _cid},
    {'last_play_time': -2, 'last_play_cid': _cid},
    {'last_play_time': 5},
    {'last_play_time': 5, 'last_play_cid': 1.5},
  ]) {
    test('malformed history is classified instead of guessed: $data', () async {
      transport.data = data;
      await expectLater(
        client.read(_bvid, _cid),
        throwsA(
          isA<ApiFailure>().having(
            (e) => e.category,
            'category',
            ApiFailureCategory.protocol,
          ),
        ),
      );
    });
  }
  test(
    'heartbeat uses Cookie, CSRF, seconds and completion sentinel',
    () async {
      await report();
      expect(
        transport.posts.single.uri.path,
        '/x/click-interface/web/heartbeat',
      );
      expect(transport.posts.single.fields, {
        'bvid': _bvid,
        'cid': _cid,
        'played_time': '42',
        'video_duration': '120',
        'type': '3',
        'csrf': 'fixture-csrf',
      });
      await report(completed: true);
      expect(transport.posts.last.fields['played_time'], '-1');
    },
  );
  test('PGC read and write carry real episode and season identity', () async {
    await client.read(_bvid, _cid, episodeId: '7', seasonId: '8');
    expect(transport.reads.last.queryParameters['ep_id'], '7');
    await client.report(
      _bvid,
      _cid,
      position: Duration.zero,
      duration: const Duration(seconds: 120),
      completed: false,
      episodeId: '7',
      seasonId: '8',
    );
    expect(transport.posts.last.fields['epid'], '7');
    expect(transport.posts.last.fields['sid'], '8');
    expect(transport.posts.last.fields['type'], '4');
  });
  test('guest cannot submit a heartbeat', () async {
    api.cookieJar.clear();
    await expectLater(
      report(),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.authentication,
        ),
      ),
    );
    expect(transport.posts, isEmpty);
  });
  for (final kind in ['http', 'network', 'timeout']) {
    test('$kind write failure is never retried', () async {
      transport.failure = kind;
      await expectLater(report(), throwsA(isA<ApiFailure>()));
      expect(transport.posts, hasLength(1));
    });
  }
  test('cancelled or old-epoch writes never transmit', () async {
    await expectLater(
      client.report(
        _bvid,
        _cid,
        position: Duration.zero,
        duration: const Duration(seconds: 120),
        completed: false,
        context: ApiRequestContext(cancellation: ApiCancellation()..cancel()),
      ),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(
      client.report(
        _bvid,
        _cid,
        position: Duration.zero,
        duration: const Duration(seconds: 120),
        completed: false,
        context: ApiRequestContext(sessionEpoch: 0),
      ),
      throwsA(isA<ApiFailure>()),
    );
    expect(transport.posts, isEmpty);
  });
  test('late response after epoch change is discarded', () async {
    transport.pending = Completer<ApiHttpResponse>();
    final result = report();
    final assertion = expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    await Future<void>.delayed(Duration.zero);
    session.sessionEpoch++;
    transport.pending!.complete(_response(null));
    await assertion;
  });
}

ApiHttpResponse _response(Object? data, {int status = 200}) => ApiHttpResponse(
  status,
  Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
  const {},
);

final class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 1;
}

final class _Transport implements ApiTransport, ApiFormTransport {
  Map<String, Object?> data = {'last_play_time': 42678, 'last_play_cid': _cid};
  final reads = <Uri>[];
  final posts = <({Uri uri, Map<String, String> fields})>[];
  String? failure;
  Completer<ApiHttpResponse>? pending;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    reads.add(uri);
    if (uri.path == '/x/web-interface/nav') {
      return _response({
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
        },
      });
    }
    return _response(data);
  }

  @override
  Future<ApiHttpResponse> postForm(
    Uri uri, {
    required Map<String, String> fields,
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    posts.add((uri: uri, fields: Map.of(fields)));
    if (failure == 'network') {
      throw const ApiFailure(ApiFailureCategory.network, 'fixture');
    }
    if (failure == 'timeout') throw TimeoutException('fixture');
    return pending?.future ??
        _response(null, status: failure == 'http' ? 503 : 200);
  }
}
