import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/media_cdn.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';
import 'dash_media_selection.dart';
import '../domain/playback_repository.dart';
import '../domain/video_preview_repository.dart';

final class ApiVideoPreviewRepository implements VideoPreviewRepository {
  ApiVideoPreviewRepository(this.api, this.requests, {this.cdnPreference});
  final BiliApiClient api;
  final ApiRequests requests;
  final Future<MediaCdnPreference> Function()? cdnPreference;

  @override
  Future<PlaybackMedia> resolve(
    VideoId video,
    String cid, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final info = await api.getVideoPreviewInfo(
      video.value,
      cid,
      context: context,
    );
    final preference =
        await cdnPreference?.call() ?? MediaCdnPreference.automatic;
    return selectDashMedia(
      info,
      quality: 32,
      preferredCodec: VideoCodecPreference.h264,
      videoOnly: true,
      // A short hover must not wait on a PCDN before trying the supplied CDN.
      // Explicit provider preferences still take priority; no URL is rewritten.
      cdnPreference: preference == MediaCdnPreference.automatic
          ? MediaCdnPreference.regular
          : preference,
      headers: const {
        'Referer': 'https://www.bilibili.com/',
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/132.0.0.0 Safari/537.36',
      },
    );
  }, cancellation: cancellation);
}
