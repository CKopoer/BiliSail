import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/media_cdn.dart';
import '../domain/content_playback.dart';
import '../domain/playback_repository.dart';
import 'dash_media_selection.dart';

final class ApiContentPlaybackRepository implements ContentPlaybackRepository {
  ApiContentPlaybackRepository(
    this.pgc,
    this.live,
    this.requests, {
    this.cdnPreference,
  });
  final PgcClient pgc;
  final LiveClient live;
  final ApiRequests requests;
  final Future<MediaCdnPreference> Function()? cdnPreference;

  static const _headers = {
    'Referer': 'https://www.bilibili.com/',
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36',
  };

  @override
  Future<PlaybackMedia> resolve(
    ContentPlaybackTarget target, {
    required int quality,
    VideoCodecPreference preferredCodec = VideoCodecPreference.h264,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    switch (target) {
      case PgcPlaybackTarget(:final episodeId):
        final info = await pgc.getPlayInfo(
          episodeId,
          qn: quality,
          context: context,
        );
        return selectDashMedia(
          info,
          quality: quality,
          preferredCodec: preferredCodec,
          cdnPreference:
              await cdnPreference?.call() ?? MediaCdnPreference.automatic,
          headers: _headers,
        );
      case LivePlaybackTarget(:final roomId):
        final info = await live.getPlayInfo(
          roomId,
          qn: quality,
          context: context,
        );
        if (info.liveStatus != 1) {
          throw const AppFailure(AppFailureKind.playback, '主播当前未开播');
        }
        final streams =
            info.streams
                .where(
                  (stream) =>
                      stream.urls.isNotEmpty &&
                      (stream.codec == 'avc' ||
                          stream.codec == 'avc1' ||
                          stream.codec == 'h264') &&
                      const ['ts', 'fmp4', 'flv'].contains(stream.format),
                )
                .toList()
              ..sort(
                (a, b) => (a.format == 'flv' ? 1 : 0).compareTo(
                  b.format == 'flv' ? 1 : 0,
                ),
              );
        if (streams.isEmpty) {
          throw const AppFailure(AppFailureKind.playback, '未取得可用的 H.264 直播线路');
        }
        final stream = streams.first;
        return PlaybackMedia(
          video: PlaybackTrack(
            urls: stream.urls,
            codec: stream.codec,
            bandwidth: 0,
          ),
          audio: null,
          quality: stream.quality,
          qualities: info.qualities,
          qualityLabels: info.qualityLabels,
          duration: Duration.zero,
          headers: {..._headers, 'Referer': 'https://live.bilibili.com/'},
          kind: stream.format == 'flv'
              ? PlaybackMediaKind.liveFlv
              : PlaybackMediaKind.liveHls,
        );
    }
  }, cancellation: cancellation);
}
