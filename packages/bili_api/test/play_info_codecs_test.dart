import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    'preview signs the browser profile and ignores missing companion audio',
    () async {
      final transport = _Transport(['avc1.640028'], includeAudio: false);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final info = await api.getVideoPreviewInfo('BV1xx411c7mD', '123');
      expect(info.dashVideo.single.codecs, 'avc1.640028');
      expect(info.dashAudio, isEmpty);
      final query = transport.playRequest?.queryParameters;
      expect(query?['qn'], '32');
      expect(query?['fnval'], '2000');
      expect(query?['fnver'], '0');
      expect(query?['from_client'], 'BROWSER');
      expect(query?['need_fragment'], 'false');
      expect(query?['w_rid'], isNotEmpty);
      await expectLater(
        api.getPlayInfo('BV1xx411c7mD', '123'),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
  for (final pgc in [false, true]) {
    for (final codecs in [
      ['avc1.640028', 'hev1.1.6.L120', 'av01.0.08M.08'],
      ['hvc1.1.6.L120'],
      ['av01.0.08M.08'],
    ]) {
      test('${pgc ? 'PGC' : 'UGC'} retains video codecs $codecs', () async {
        final transport = _Transport(codecs);
        final api = BiliApiClient(transport: transport);
        addTearDown(api.close);
        final info =
            pgc
                ? await PgcClient(api).getPlayInfo('123')
                : await api.getPlayInfo('BV1xx411c7mD', '123');
        expect(info.dashVideo.map((track) => track.codecs), codecs);
        expect(info.dashAudio.single.codecs, 'mp4a.40.2');
        expect(transport.playRequest?.queryParameters['fnval'], '4048');
      });
    }
  }
}

final class _Transport implements ApiTransport {
  _Transport(this.codecs, {this.includeAudio = true});
  final List<String> codecs;
  final bool includeAudio;
  Uri? playRequest;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final Map<String, Object?> response;
    if (uri.path == '/x/web-interface/nav') {
      response = {
        'code': -101,
        'data': {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
            'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
          },
        },
      };
    } else {
      playRequest = uri;
      response = {
        'code': 0,
        uri.path.startsWith('/pgc/') ? 'result' : 'data': {
          'code': 0,
          'accept_quality': [80],
          'dash': {
            'duration': 3,
            'video': [
              for (final codec in codecs)
                {
                  'id': 80,
                  'base_url': 'https://cdn.example/video.m4s',
                  'codecs': codec,
                },
            ],
            if (includeAudio)
              'audio': [
                {
                  'id': 30280,
                  'base_url': 'https://cdn.example/audio.m4s',
                  'codecs': 'mp4a.40.2',
                },
              ],
          },
        },
      };
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode(response))),
      const {},
    );
  }
}
