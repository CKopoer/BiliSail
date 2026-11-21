import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/features/playback/data/api_content_playback_repository.dart';
import 'package:bilisail/features/playback/domain/content_playback.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final (protocol, format, codec) in [
    ('http_stream', 'flv', 'avc'),
    ('http_hls', 'fmp4', 'hevc'),
    ('http_hls', 'ts', 'av1'),
  ]) {
    test(
      'selects and retains live combination $protocol/$format/$codec',
      () async {
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: _Transport(),
          sessionProvider: requests,
        );
        addTearDown(api.close);
        final repository = ApiContentPlaybackRepository(
          PgcClient(api),
          LiveClient(api),
          requests,
        );
        final preference = LiveStreamPreference(
          protocol: protocol,
          format: format,
          codec: codec,
        );
        final media = await repository.resolveLive(
          const LivePlaybackTarget('8'),
          quality: 400,
          preference: preference,
          cancellation: RequestCancellation(),
        );
        expect(media.liveStream, preference);
        expect(media.video.codec, codec);
        expect(media.liveStreams.length, 5);
        expect(
          media.kind,
          format == 'flv'
              ? PlaybackMediaKind.liveFlv
              : PlaybackMediaKind.liveHls,
        );
        final fallback = await repository.resolveLive(
          const LivePlaybackTarget('8'),
          quality: 400,
          preference: const LiveStreamPreference(
            protocol: 'http_stream',
            format: 'flv',
            codec: 'av1',
          ),
          cancellation: RequestCancellation(),
        );
        expect(fallback.liveStream?.format, 'flv');
        expect(fallback.liveStream?.codec, 'hevc');
      },
    );
  }
  for (final (quality, hlsFirst) in [(0, false), (400, true), (10000, false)]) {
    test(
      'automatic live playback follows server stream and line order: qn=$quality hlsFirst=$hlsFirst',
      () async {
        final transport = _Transport(hlsFirst: hlsFirst);
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
        );
        addTearDown(api.close);
        final repository = ApiContentPlaybackRepository(
          PgcClient(api),
          LiveClient(api),
          requests,
          cdnPreference: () async => MediaCdnPreference.tencent,
        );
        final media = await repository.resolve(
          const LivePlaybackTarget('8'),
          quality: quality,
          cancellation: RequestCancellation(),
        );
        expect(transport.request?.queryParameters['qn'], '$quality');
        expect(media.liveStreams.first.preference, media.liveStream);
        expect(media.liveStream?.format, hlsFirst ? 'ts' : 'flv');
        expect(
          media.kind,
          hlsFirst ? PlaybackMediaKind.liveHls : PlaybackMediaKind.liveFlv,
        );
        expect(media.video.codec, hlsFirst ? 'av1' : 'hevc');
        expect(media.quality, quality == 0 ? 250 : quality);
        expect(media.qualities, [if (!hlsFirst) 20000, 10000, 400, 250]);
        expect(media.qualityLabels[400], '1080P 蓝光');
        expect(media.video.urls.map((uri) => uri.host), [
          'primary.example',
          'backup.example',
        ]);
        expect(media.video.urls.last.queryParameters['sign'], 'backup');
        expect(media.headers['Referer'], 'https://www.bilibili.com');
        expect(media.headers['User-Agent'], contains('Version/15.2 Safari/'));
        expect(media.audio, isNull);
        expect(media.duration, Duration.zero);
      },
    );
  }
}

final class _Transport implements ApiTransport {
  _Transport({this.hlsFirst = false});

  final bool hlsFirst;
  Uri? request;
  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    if (uri.path == '/x/web-interface/nav') {
      return ApiHttpResponse(
        200,
        Uint8List.fromList(
          utf8.encode(
            jsonEncode({
              'code': 0,
              'data': {
                'wbi_img': {
                  'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
                  'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
                },
              },
            }),
          ),
        ),
        const {},
      );
    }
    request = uri;
    final requested = int.parse(uri.queryParameters['qn'] ?? '0');
    Map<String, Object?> codec(String name, List<int> qualities) => {
      'codec_name': name,
      'current_qn': requested == 0 ? 250 : requested,
      'accept_qn': qualities,
      'base_url': '/live.m3u8?',
      'url_info': [
        {'host': 'https://primary.example', 'extra': 'sign=primary'},
        {'host': 'https://backup.example', 'extra': 'sign=backup'},
      ],
    };
    final flv = {
      'protocol_name': 'http_stream',
      'format': [
        {
          'format_name': 'flv',
          'codec': [
            codec('unknown', [400]),
            codec('hevc', [20000, 10000, 400, 250]),
            codec('avc', [10000, 400, 250]),
          ],
        },
      ],
    };
    final data = {
      'room_id': 8,
      'live_status': 1,
      'playurl_info': {
        'playurl': {
          'g_qn_desc': [
            {'qn': 250, 'desc': '超清'},
            {
              'qn': 400,
              'desc': '蓝光',
              'media_base_desc': {
                'detail_desc': {'desc': '1080P 蓝光'},
              },
            },
            {'qn': 10000, 'desc': '原画'},
            {'qn': 20000, 'desc': '4K'},
          ],
          'stream': [
            if (!hlsFirst) flv,
            {
              'protocol_name': 'http_hls',
              'format': [
                {
                  'format_name': 'ts',
                  'codec': [
                    codec('av1', [10000, 400, 250]),
                  ],
                },
                {
                  'format_name': 'fmp4',
                  'codec': [
                    codec('avc', [10000, 400, 250]),
                    codec('hevc', [20000, 10000, 400, 250]),
                  ],
                },
              ],
            },
            if (hlsFirst) flv,
          ],
        },
      },
    };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
