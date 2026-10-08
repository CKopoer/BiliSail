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
  for (final response in ['selected', 'original', 'missing-capability']) {
    test(
      'voice repository verifies the returned media language: $response',
      () async {
        final transport = _Transport(response);
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
        );
        addTearDown(api.close);
        final repository = ApiPlaybackRepository(api, requests);
        final resolve = repository.resolveVoice(
          const VideoId('BV1xx411c7mD'),
          '2',
          voice: const PlaybackVoice(
            languageCode: 'en',
            label: 'English',
            productionType: 2,
          ),
          quality: 80,
          preferredCodec: VideoCodecPreference.h264,
          cancellation: RequestCancellation(),
        );
        if (response == 'selected') {
          final media = await resolve;
          expect(media.voice.key, '2:en');
          expect(media.video.urls.single.path, '/video/en');
          expect(media.audio?.urls.single.path, '/audio/en');
          expect(media.voices.single.subtitleLanguage, 'ai-en');
        } else {
          await expectLater(
            resolve,
            throwsA(
              isA<AppFailure>().having(
                (failure) => failure.kind,
                'kind',
                AppFailureKind.playback,
              ),
            ),
          );
        }
        expect(transport.playRequest?.queryParameters['cur_language'], 'en');
        expect(
          transport.playRequest?.queryParameters['cur_production_type'],
          '2',
        );
        expect(transport.playRequest?.queryParameters['w_rid'], isNotEmpty);
      },
    );
  }
}

final class _Transport implements ApiTransport {
  _Transport(this.response);
  final String response;
  Uri? playRequest;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final Map<String, Object?> data;
    if (uri.path == '/x/web-interface/nav') {
      data = {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/${'b' * 32}.png',
        },
      };
    } else {
      playRequest = uri;
      data = {
        'cur_language': response == 'original' ? '' : 'en',
        'cur_production_type': response == 'original' ? 0 : 2,
        if (response != 'missing-capability')
          'language': {
            'support': true,
            'items': [
              {
                'lang': 'en',
                'title': 'English',
                'production_type': 2,
                'subtitle_lang': 'ai-en',
              },
            ],
          },
        'accept_quality': [80],
        'dash': {
          'duration': 180,
          'video': [
            {
              'id': 80,
              'codecs': 'avc1',
              'base_url': 'https://cdn.example/video/en',
            },
          ],
          'audio': [
            {
              'id': 30280,
              'codecs': 'mp4a.40.2',
              'base_url': 'https://cdn.example/audio/en',
            },
          ],
        },
      };
    }
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
