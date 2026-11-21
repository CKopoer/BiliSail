import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/audio_quality.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/media_cdn.dart';
import '../domain/content_playback.dart';
import '../domain/playback_repository.dart';
import 'dash_media_selection.dart';

final class ApiContentPlaybackRepository
    implements ContentPlaybackRepository, LiveStreamPlaybackRepository {
  ApiContentPlaybackRepository(
    this.pgc,
    this.live,
    this.requests, {
    this.cdnPreference,
    this.audioQualityPreference,
  });
  final PgcClient pgc;
  final LiveClient live;
  final ApiRequests requests;
  final Future<MediaCdnPreference> Function()? cdnPreference;
  final Future<AudioQualityPreference> Function()? audioQualityPreference;

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
      case OfflinePlaybackTarget():
        throw const AppFailure(AppFailureKind.playback, '离线播放服务未配置');
      case PgcPlaybackTarget(:final episodeId):
        final info = await pgc.getPlayInfo(
          episodeId,
          qn: quality,
          context: context,
        );
        return selectDashMedia(
          info,
          audioQuality:
              await audioQualityPreference?.call() ??
              AudioQualityPreference.aac192,
          quality: quality,
          preferredCodec: preferredCodec,
          cdnPreference:
              await cdnPreference?.call() ?? MediaCdnPreference.automatic,
          headers: _headers,
        );
      case LivePlaybackTarget():
        return resolveLive(
          target,
          quality: quality,
          preference: LiveStreamPreference.automatic,
          cancellation: cancellation,
        );
    }
  }, cancellation: cancellation);

  @override
  Future<PlaybackMedia> resolveLive(
    LivePlaybackTarget target, {
    required int quality,
    required LiveStreamPreference preference,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final info = await live.getPlayInfo(
      target.roomId,
      qn: quality,
      context: context,
    );
    if (info.liveStatus != 1) {
      throw const AppFailure(AppFailureKind.playback, '主播当前未开播');
    }
    final streams = List<LivePlaybackStream>.unmodifiable([
      for (final stream in info.streams)
        if (stream.urls.isNotEmpty &&
            VideoCodecPreference.fromCodec(stream.codec) != null &&
            const ['http_hls', 'http_stream'].contains(stream.protocol) &&
            const ['ts', 'fmp4', 'flv'].contains(stream.format))
          LivePlaybackStream(
            preference: LiveStreamPreference(
              protocol: stream.protocol,
              format: stream.format,
              codec: stream.codec,
            ),
            urls: stream.urls,
            quality: stream.quality,
            qualities: stream.qualities,
          ),
    ]);
    final stream = LivePlaybackStream.select(streams, preference);
    if (stream == null) {
      throw const AppFailure(AppFailureKind.playback, '未取得可用的直播流');
    }
    return PlaybackMedia(
      liveStream: stream.preference,
      liveStreams: streams,
      video: PlaybackTrack(
        urls: stream.urls,
        codec: stream.preference.codec,
        bandwidth: 0,
      ),
      audio: null,
      quality: stream.quality,
      qualities: stream.qualities,
      qualityLabels: info.qualityLabels,
      duration: Duration.zero,
      headers: {..._headers, 'Referer': 'https://live.bilibili.com/'},
      kind: stream.preference.format == 'flv'
          ? PlaybackMediaKind.liveFlv
          : PlaybackMediaKind.liveHls,
    );
  }, cancellation: cancellation);
}
