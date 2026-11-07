import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final supplement in [false, true]) {
    test(
      'silent UGC retains its marker through quality supplement=$supplement',
      () async {
        final transport = _Transport(silent: true, missingLower: supplement);
        final media = await _repository(transport).resolve(
          const VideoId('BV1fTnZ6LEvr'),
          '43074848375',
          quality: 80,
          cancellation: RequestCancellation(),
        );
        expect(media.isIntentionallySilent, isTrue);
        expect(media.audio, isNull);
        expect(media.quality, 80);
        expect(transport.qualities, supplement ? [129, 80] : [129]);
      },
    );
  }
  for (final codec in VideoCodecPreference.values.take(3)) {
    test('1080P60 discovers the ladder before selecting $codec', () async {
      final transport = _Transport();
      final repository = _repository(transport);
      final media = await repository.resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 116,
        preferredCodec: codec,
        cancellation: RequestCancellation(),
      );
      expect(transport.qualities, [129]);
      expect(media.quality, 116);
      expect(media.qualities, [80, 116]);
      expect(VideoCodecPreference.fromCodec(media.video.codec), codec);
      expect(media.audio?.codec, 'mp4a.40.2');
    });
  }

  test(
    'supplements a missing lower quality without losing the upper ladder',
    () async {
      final transport = _Transport(missingLower: true);
      final media = await _repository(transport).resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 80,
        cancellation: RequestCancellation(),
      );
      expect(transport.qualities, [129, 80]);
      expect(media.quality, 80);
      expect(media.qualities, [80, 116]);
      expect(media.audio, isNotNull);
    },
  );

  test('advertised VIP quality alone never becomes playable', () async {
    final transport = _Transport(entitled: false);
    final media = await _repository(transport).resolve(
      const VideoId('BV1VNxr63EZp'),
      '43202641987',
      quality: 116,
      cancellation: RequestCancellation(),
    );
    expect(transport.qualities, [129]);
    expect(media.quality, 80);
    expect(media.qualities, [80]);
  });

  test(
    'optional supplement failure retains complete discovery media',
    () async {
      final transport = _Transport(missingLower: true, supplementFailure: -352);
      final media = await _repository(transport).resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 80,
        cancellation: RequestCancellation(),
      );
      expect(transport.qualities, [129, 80]);
      expect(media.quality, 116);
      expect(media.audio, isNotNull);
    },
  );

  for (final code in [-101, null]) {
    test(
      'supplement propagates ${code == null ? 'cancellation' : 'expired session'}',
      () async {
        final transport = _Transport(
          missingLower: true,
          supplementFailure: code,
          cancelSupplement: code == null,
        );
        await expectLater(
          _repository(transport).resolve(
            const VideoId('BV1VNxr63EZp'),
            '43202641987',
            quality: 80,
            cancellation: RequestCancellation(),
          ),
          throwsA(
            isA<AppFailure>().having(
              (failure) => failure.kind,
              'kind',
              code == null
                  ? AppFailureKind.cancelled
                  : AppFailureKind.authentication,
            ),
          ),
        );
        expect(transport.qualities, [129, 80]);
      },
    );
  }

  test(
    'a supplement in another voice cannot mix with original audio',
    () async {
      final transport = _Transport(missingLower: true, wrongVoice: true);
      final media = await _repository(transport).resolve(
        const VideoId('BV1VNxr63EZp'),
        '43202641987',
        quality: 80,
        cancellation: RequestCancellation(),
      );
      expect(media.quality, 116);
      expect(media.qualities, [116]);
      expect(media.voice.isOriginal, isTrue);
    },
  );
}

ApiPlaybackRepository _repository(_Transport transport) {
  final requests = ApiRequests();
  final api = BiliApiClient(transport: transport, sessionProvider: requests);
  addTearDown(api.close);
  return ApiPlaybackRepository(api, requests);
}

final class _Transport implements ApiTransport {
  _Transport({
    this.missingLower = false,
    this.entitled = true,
    this.supplementFailure,
    this.cancelSupplement = false,
    this.wrongVoice = false,
    this.silent = false,
  });
  final bool missingLower;
  final bool entitled;
  final int? supplementFailure;
  final bool cancelSupplement;
  final bool wrongVoice;
  final bool silent;
  final qualities = <int>[];

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final Map<String, Object?> data;
    switch (uri.path) {
      case '/x/web-interface/view':
        data = {
          'aid': '117258244656600',
          'bvid': 'BV1fTnZ6LEvr',
          'title': 'Silent fixture',
          'pages': [
            {'cid': '43074848375', 'page': 1, 'part': 'P1'},
          ],
        };
      case '/x/web-interface/nav':
        data = {
          'wbi_img': {
            'img_url': 'https://i0.hdslb.com/${'a' * 32}.png',
            'sub_url': 'https://i0.hdslb.com/${'b' * 32}.png',
          },
        };
      case '/x/player/wbi/playurl':
        final qn = int.parse(uri.queryParameters['qn']!);
        qualities.add(qn);
        if (qn != 129 && cancelSupplement) cancellation?.cancel();
        if (qn != 129 && supplementFailure != null) {
          return ApiHttpResponse(
            200,
            Uint8List.fromList(
              utf8.encode(jsonEncode({'code': supplementFailure})),
            ),
            const {},
          );
        }
        data = {
          if (qn != 129 && wrongVoice) ...{
            'cur_language': 'en',
            'cur_production_type': 2,
          },
          'accept_quality': [116, 80],
          'dash': {
            'duration': 309,
            'video': [
              for (final quality in [
                if (entitled && qn == 129) 116,
                if (!missingLower || qn != 129) 80,
              ])
                for (final codec in [
                  'avc1.640032',
                  'hvc1.1.6.L150.90',
                  'av01.0.08M.08',
                ])
                  {
                    'id': quality,
                    'base_url': 'https://cdn.example/$quality/$codec',
                    'codecs': codec,
                    'frame_rate': quality == 116 ? '60.000' : '30.000',
                  },
            ],
            if (silent) ...{
              'audio': null,
              'dolby': {'type': 0, 'audio': null},
              'flac': null,
            } else
              'audio': [
                {
                  'id': 30280,
                  'baseUrl': 'https://cdn.example/audio',
                  'codecs': 'mp4a.40.2',
                },
              ],
          },
        };
      default:
        throw StateError('Unexpected request path ${uri.path}');
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
