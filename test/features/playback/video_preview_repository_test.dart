import 'dart:convert';
import 'dart:typed_data';

import 'package:bili_api/bili_api.dart';
import 'package:bilisail/core/network/api_requests.dart';
import 'package:bilisail/domain/media_cdn.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/video.dart';
import 'package:bilisail/features/playback/data/api_video_preview_repository.dart';
import 'package:bilisail/features/playback/domain/playback_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final preference in [
    MediaCdnPreference.automatic,
    MediaCdnPreference.tencent,
  ]) {
    test(
      'preview $preference uses a supplied CDN and never needs audio',
      () async {
        final transport = _Transport();
        final requests = ApiRequests();
        final api = BiliApiClient(
          transport: transport,
          sessionProvider: requests,
        );
        addTearDown(api.close);
        final repository = ApiVideoPreviewRepository(
          api,
          requests,
          cdnPreference: () async => preference,
        );
        final media = await repository.resolve(
          const VideoId('BV1234567890'),
          '42',
          cancellation: RequestCancellation(),
        );
        expect(media.kind, PlaybackMediaKind.dash);
        expect(media.audio, isNull);
        expect(media.quality, 32);
        expect(
          media.video.urls.first,
          Uri.parse(
            preference == MediaCdnPreference.tencent
                ? _Transport.tencent
                : _Transport.huawei,
          ),
        );
        expect(
          media.video.urls.indexOf(Uri.parse(_Transport.pcdn)),
          preference == MediaCdnPreference.automatic ? 2 : 1,
        );
        expect(media.video.urls.toSet(), {
          Uri.parse(_Transport.pcdn),
          Uri.parse(_Transport.huawei),
          Uri.parse(_Transport.tencent),
        });
        expect(transport.playRequests, 1);
      },
    );
  }
}

final class _Transport implements ApiTransport {
  static const pcdn =
      'https://xy1x2x3x4xy.mcdn.bilivideo.cn:8082/video.m4s?token=fixture';
  static const huawei =
      'https://upos-sz-mirrorhw.bilivideo.com/video.m4s?token=fixture';
  static const tencent =
      'https://upos-sz-mirrorcos.bilivideo.com/video.m4s?token=fixture';
  int playRequests = 0;

  @override
  Future<ApiHttpResponse> get(
    Uri uri, {
    required Map<String, String> headers,
    required Duration timeout,
    ApiCancellation? cancellation,
  }) async {
    final nav = uri.path.endsWith('/nav');
    if (!nav) playRequests++;
    final data = nav
        ? {
            'wbi_img': {
              'img_url': 'https://i0.hdslb.com/bfs/wbi/${'a' * 32}.png',
              'sub_url': 'https://i0.hdslb.com/bfs/wbi/${'b' * 32}.png',
            },
          }
        : {
            'accept_quality': [32],
            'dash': {
              'duration': 20,
              'video': [
                {
                  'id': 32,
                  'codecs': 'avc1.640028',
                  'base_url': pcdn,
                  'backup_url': [huawei, tencent],
                },
              ],
            },
          };
    return ApiHttpResponse(
      200,
      Uint8List.fromList(utf8.encode(jsonEncode({'code': 0, 'data': data}))),
      const {},
    );
  }
}
