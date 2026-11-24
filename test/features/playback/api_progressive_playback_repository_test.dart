import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bili_player/bili_player.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/application/playback_source_selection.dart';
import 'package:bilisail/features/playback/data/api_playback_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'an annual report MP4 opens as a single source with embedded audio',
    () async {
      final transport = _AnnualReportTransport();
      final requests = ApiRequests();
      final api = BiliApiClient(
        transport: transport,
        sessionProvider: requests,
      );
      addTearDown(api.close);
      final repository = ApiPlaybackRepository(
        api,
        requests,
        cdnPreference: () async => MediaCdnPreference.cosov,
      );

      final media = await repository.resolve(
        const VideoId('BV19C4y1T7t3'),
        '1384635946',
        quality: 80,
        preferredCodec: VideoCodecPreference.av1,
        cancellation: RequestCancellation(),
      );
      expect(transport.playRequests, 1);
      expect(media.kind, PlaybackMediaKind.progressive);
      expect(media.duration, const Duration(milliseconds: 50991));
      expect(media.quality, 64);
      expect(media.qualities, [64]);
      expect(media.video.codec, 'avc1');
      expect(media.audio, isNull);
      expect(media.isIntentionallySilent, isFalse);
      expect(media.video.urls.map((url) => url.host), [
        'upos-sz-mirrorcosov.bilivideo.com',
        'upos-hz-mirrorakam.akamaized.net',
      ]);

      final selection = selectPlaybackSource(
        media,
        requestedAudioOnly: false,
        isLive: false,
        requestedLiveLine: 0,
      );
      expect(
        selection.source,
        isA<ProgressiveSource>()
            .having((source) => source.media.uri, 'uri', media.video.urls.first)
            .having((source) => source.isAudioOnly, 'audio only', isFalse)
            .having(
              (source) => source.media.requestPolicy.headers['Referer'],
              'referer',
              'https://www.bilibili.com/',
            ),
      );
    },
  );
}

final class _AnnualReportTransport implements ApiTransport {
  int playRequests = 0;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path == '/x/player/wbi/playurl') playRequests++;
    final data = switch (uri.path) {
      '/x/web-interface/nav' => {
        'wbi_img': {
          'img_url': 'https://i0.hdslb.com/${'a' * 32}.png',
          'sub_url': 'https://i0.hdslb.com/${'b' * 32}.png',
        },
      },
      '/x/player/wbi/playurl' => {
        'quality': 64,
        'accept_quality': [64],
        'accept_description': ['高清 720P'],
        'format': 'mp4720',
        'timelength': 50991,
        'video_codecid': 7,
        'durl': [
          {
            'order': 1,
            'length': 50991,
            'url': 'https://upos-hz-mirrorakam.akamaized.net/annual-report.mp4',
            'backup_url': [
              '//upos-sz-mirrorcosov.bilivideo.com/annual-report.mp4',
              'https://name@invalid.example/annual-report.mp4',
            ],
          },
        ],
      },
      _ => throw StateError('Unexpected endpoint ${uri.path}'),
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
