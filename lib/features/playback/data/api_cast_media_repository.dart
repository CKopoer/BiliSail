import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../auth/domain/app_session_credentials.dart';
import '../domain/casting.dart';

final class ApiCastMediaRepository implements CastMediaRepository {
  const ApiCastMediaRepository(
    this.api,
    this.requests, {
    required this.credentials,
  });
  final BiliApiClient api;
  final ApiRequests requests;
  final AppSessionCredentials? Function() credentials;

  @override
  Future<CastMedia> resolve(
    CastMediaRequest request, {
    bool receiverResolves = false,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    if (request.roomId case final roomId?) {
      final info = await LiveClient(api)
          .getPlayInfo(roomId, qn: request.quality, context: context);
      if (info.liveStatus != 1) {
        throw const AppFailure(AppFailureKind.playback, '主播当前未开播');
      }
      if (receiverResolves) {
        return CastMedia(request: request, roomId: info.roomId);
      }
      // A renderer cannot inherit the native player's HTTP headers or decode
      // preferences. Prefer an AVC MPEG-TS HLS stream for ordinary televisions.
      final streams =
          info.streams
              .where(
                (stream) => stream.codec == 'avc' && stream.urls.isNotEmpty,
              )
              .where((stream) => _livePriority(stream) < 3)
              .toList()
            ..sort((a, b) => _livePriority(a).compareTo(_livePriority(b)));
      if (streams.isEmpty) {
        throw const AppFailure(AppFailureKind.playback, '未取得可投屏的 H.264 直播流');
      }
      return CastMedia(
        request: request,
        roomId: info.roomId,
        uri: streams.first.urls.first,
      );
    }
    var objectId = request.episodeId ?? request.aid;
    if (objectId == null && request.bvid != null) {
      objectId = (await api.getVideoDetail(
        request.bvid!,
        context: context,
      )).aid;
    }
    if (objectId == null) {
      throw const AppFailure(AppFailureKind.playback, '当前内容暂不支持投屏');
    }
    final aid = request.episodeId == null ? objectId : request.aid;
    if (receiverResolves) return CastMedia(request: request, aid: aid);
    final cid = request.cid;
    if (cid == null) {
      throw const AppFailure(AppFailureKind.playback, '当前内容缺少投屏所需的视频标识');
    }
    final credential = credentials();
    final token =
        credential != null &&
            !credential.invalid &&
            credential.expiresAt.isAfter(DateTime.now())
        ? credential.accessToken
        : null;
    try {
      final uri = await CastClient(api).playUrl(
        objectId: objectId,
        cid: cid,
        episode: request.episodeId != null,
        quality: request.quality,
        accessToken: token,
        context: context,
      );
      return CastMedia(request: request, aid: aid, uri: uri);
    } on ApiFailure catch (error) {
      if (error.category == ApiFailureCategory.unavailable) {
        throw const AppFailure(
          AppFailureKind.playback,
          '当前内容没有可投屏的完整音视频地址，请尝试其他视频',
        );
      }
      rethrow;
    }
  }, cancellation: cancellation);

  static int _livePriority(ApiLiveStream stream) =>
      switch ((stream.protocol, stream.format)) {
        ('http_hls', 'ts') => 0,
        ('http_hls', 'fmp4') => 1,
        ('http_stream', 'flv') => 2,
        _ => 3,
      };
}
