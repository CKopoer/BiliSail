import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:test/test.dart';

void main() {
  test(
    '1080P60 uses signed Web player context and retains every codec',
    () async {
      final transport = _Transport([
        'avc1.640032',
        'hvc1.1.6.L150.90',
        'av01.0.08M.08',
      ], quality: 116);
      final api = BiliApiClient(transport: transport);
      addTearDown(api.close);
      final info = await api.getPlayInfo(
        'BV1VNxr63EZp',
        '43202641987',
        qn: 116,
      );
      expect(info.dashVideo.map((track) => track.id), everyElement(116));
      expect(info.dashAudio.single.codecs, 'mp4a.40.2');
      final query = transport.playRequest!.queryParameters;
      expect(query, containsPair('qn', '116'));
      expect(query, containsPair('fnver', '0'));
      expect(query, containsPair('fnval', '4048'));
      expect(query, containsPair('fourk', '1'));
      expect(query, containsPair('gaia_source', 'pre-load'));
      expect(query, containsPair('isGaiaAvoided', 'true'));
      expect(query, containsPair('web_location', '1315873'));
      expect(query, containsPair('dm_img_list', '[]'));
      expect(jsonDecode(query['dm_img_inter']!), {
        'ds': [],
        'wh': [0, 0, 0],
        'of': [0, 0, 0],
      });
      expect(
        base64Decode(base64.normalize(query['dm_img_str']!)),
        hasLength(24),
      );
      expect(
        base64Decode(base64.normalize(query['dm_cover_img_str']!)),
        hasLength(48),
      );
      final unsigned = Map<String, String>.of(query)..remove('w_rid');
      final signer = WbiSigner.fromUrls(
        'https://i0.hdslb.com/${'a' * 32}.png',
        'https://i0.hdslb.com/${'b' * 32}.png',
      );
      expect(
        signer.sign(
          unsigned,
          DateTime.fromMillisecondsSinceEpoch(int.parse(query['wts']!) * 1000),
        )['w_rid'],
        query['w_rid'],
      );
      await api.getPlayInfo('BV1VNxr63EZp', '43202641987', qn: 116);
      expect(
        transport.playRequest!.queryParameters['dm_img_str'],
        isNot(query['dm_img_str']),
      );
    },
  );

  for (final pgc in [false, true]) {
    for (final ordinary in [false, true]) {
      test(
        '${pgc ? 'PGC' : 'UGC'} combines FLAC, Dolby and nullable ordinary audio=$ordinary',
        () async {
          final transport = _Transport(
            ['dvh1.05.06'],
            includeAudio: ordinary,
            specialAudio: true,
          );
          final api = BiliApiClient(transport: transport);
          addTearDown(api.close);
          final info = pgc
              ? await PgcClient(api).getPlayInfo('123')
              : await api.getPlayInfo('BV1xx411c7mD', '123');
          expect(info.dashVideo.single.codecs, 'dvh1.05.06');
          expect(info.dashAudio.map((track) => track.id), [
            if (ordinary) 30280,
            30251,
            30250,
            30255,
          ]);
          expect(info.dashAudio.map((track) => track.codecs), [
            if (ordinary) 'mp4a.40.2',
            'fLaC',
            'ec-3',
            'ec-3',
          ]);
        },
      );
    }
  }
  test('PGC play info preserves preview entitlement marker', () async {
    final transport = _Transport(['avc1.640028'], isPreview: true);
    final api = BiliApiClient(transport: transport);
    addTearDown(api.close);
    final info = await PgcClient(api).getPlayInfo('123');
    expect(info.isPreview, isTrue);
  });

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
      expect(query, isNot(contains('gaia_source')));
      expect(query, isNot(contains('dm_img_str')));
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
        final info = pgc
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
  _Transport(
    this.codecs, {
    this.includeAudio = true,
    this.isPreview = false,
    this.specialAudio = false,
    this.quality = 80,
  });
  final bool specialAudio;
  final List<String> codecs;
  final bool includeAudio;
  final bool isPreview;
  final int quality;
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
          'is_preview': isPreview ? 1 : 0,
          'accept_quality': [quality],
          'dash': {
            if (specialAudio) ...{
              'flac': {
                'audio': {
                  'id': 30251,
                  'base_url': 'https://cdn.example/flac.m4s',
                  'codecs': 'fLaC',
                },
              },
              'dolby': {
                'audio': [
                  for (final id in [30250, 30255])
                    {
                      'id': id,
                      'baseUrl': 'https://cdn.example/dolby-$id.m4s',
                      'codecs': 'ec-3',
                    },
                ],
              },
            },
            'duration': 3,
            'video': [
              for (final codec in codecs)
                {
                  'id': quality,
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
