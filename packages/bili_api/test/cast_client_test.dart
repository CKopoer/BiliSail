import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

void main() {
  for (final episode in [false, true]) {
    test(
      'TV ${episode ? 'PGC' : 'UGC'} signs once without Web cookies',
      () async {
        final transport = _Transport();
        final api = BiliApiClient(
          transport: transport,
          clock: () => DateTime.fromMillisecondsSinceEpoch(1234567890000),
        );
        api.cookieJar.receive(Uri.https('api.bilibili.com', '/'), [
          'SESSDATA=fixture-cookie; Path=/; Secure',
        ]);
        final result = await CastClient(api).playUrl(
          objectId: '170001',
          cid: '99',
          episode: episode,
          quality: 80,
          accessToken: 'fixture token%',
        );
        expect(result.toString(), 'https://cdn.example/video.mp4?sign=a%2Bb');
        final uri = transport.uris.single;
        expect(uri.host, 'api.bilibili.com');
        expect(uri.path, '/x/tv/playurl');
        final params = uri.queryParameters;
        expect(params['playurl_type'], episode ? '2' : '1');
        expect(params['object_id'], '170001');
        expect(params['cid'], '99');
        expect(params['access_key'], 'fixture token%');
        expect(params['mobile_access_key'], 'fixture token%');
        expect(params['is_proj'], '1');
        final keys = params.keys.where((key) => key != 'sign').toList()..sort();
        final query = keys
            .map(
              (key) =>
                  '${Uri.encodeComponent(key)}=${Uri.encodeComponent(params[key]!)}',
            )
            .join('&');
        expect(
          params['sign'],
          md5
              .convert(utf8.encode('${query}b5475a8825547a4fc26c7d518eaaa02e'))
              .toString(),
        );
        expect(
          transport.headers.single.keys.map((key) => key.toLowerCase()),
          isNot(contains('cookie')),
        );
      },
    );
  }
  test(
    'guest omits credentials and rejects DASH-only or segmented media',
    () async {
      final transport = _Transport();
      final client = CastClient(BiliApiClient(transport: transport));
      Future<Uri> load() =>
          client.playUrl(objectId: '1', cid: '2', episode: false, quality: 80);
      await load();
      expect(
        transport.uris.single.queryParameters,
        isNot(contains('access_key')),
      );
      for (final data in [
        <String, Object?>{
          'dash': {'video': []},
        },
        {'durl': []},
        {
          'durl': [
            {'url': 'https://cdn.example/a.mp4'},
            {'url': 'https://cdn.example/b.mp4'},
          ],
        },
        {
          'durl': [
            {'url': 'file:///private/file.mp4'},
          ],
        },
      ]) {
        transport.data = data;
        await expectLater(load(), throwsA(isA<ApiFailure>()));
      }
    },
  );
  test('cancellation and changed account discard a late signed URL', () async {
    final transport = _Transport()..pending = Completer<ApiHttpResponse>();
    final session = _Session();
    final api = BiliApiClient(transport: transport, sessionProvider: session);
    final token = ApiCancellation();
    final result = CastClient(api).playUrl(
      objectId: '1',
      cid: '2',
      episode: false,
      quality: 80,
      context: ApiRequestContext(cancellation: token, sessionEpoch: 0),
    );
    final check = expectLater(
      result,
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.cancelled,
        ),
      ),
    );
    session.sessionEpoch++;
    token.cancel();
    transport.pending!.complete(transport.response);
    await check;
  });
  test('HTTP failure is not accepted as a playable response', () async {
    final transport = _Transport()..status = 403;
    await expectLater(
      CastClient(
        BiliApiClient(transport: transport),
      ).playUrl(objectId: '1', cid: '2', episode: false, quality: 80),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.authentication,
        ),
      ),
    );
  });
  test('explicit preview cannot be handed off as a full video', () async {
    final transport = _Transport();
    transport.data['is_preview'] = 1;
    await expectLater(
      CastClient(
        BiliApiClient(transport: transport),
      ).playUrl(objectId: '1', cid: '2', episode: true, quality: 80),
      throwsA(
        isA<ApiFailure>().having(
          (e) => e.category,
          'category',
          ApiFailureCategory.permission,
        ),
      ),
    );
  });
}

class _Session implements ApiSessionProvider {
  @override
  int sessionEpoch = 0;
}

class _Transport implements ApiTransport {
  final uris = <Uri>[];
  final headers = <Map<String, String>>[];
  int status = 200;
  Map<String, Object?> data = {
    'durl': [
      {'url': 'https://cdn.example/video.mp4?sign=a%2Bb'},
    ],
  };
  Completer<ApiHttpResponse>? pending;
  ApiHttpResponse get response => ApiHttpResponse(
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
    uris.add(uri);
    this.headers.add(headers);
    return pending?.future ?? response;
  }
}
