import '../../../domain/request_cancellation.dart';

final class CastMediaRequest {
  const CastMediaRequest({
    required this.cid,
    required this.quality,
    this.aid,
    this.bvid,
    this.episodeId,
    this.seasonId,
    this.position = Duration.zero,
    this.speed = 1,
    this.danmakuEnabled = true,
  }) : roomId = null;

  const CastMediaRequest.live({
    required this.roomId,
    required this.quality,
    this.danmakuEnabled = true,
  }) : aid = null,
       bvid = null,
       cid = null,
       episodeId = null,
       seasonId = null,
       position = Duration.zero,
       speed = 1;

  final String? cid, roomId;
  final int quality;
  final String? aid, bvid, episodeId, seasonId;
  final Duration position;
  final double speed;
  final bool danmakuEnabled;
  bool get isLive => roomId != null;
}

/// Short-lived handoff data. Media URLs and identities remain in memory.
final class CastMedia {
  const CastMedia({required this.request, this.uri, this.aid, this.roomId});
  final CastMediaRequest request;
  final Uri? uri;
  final String? aid, roomId;
}

abstract interface class CastMediaRepository {
  Future<CastMedia> resolve(
    CastMediaRequest request, {
    bool receiverResolves = false,
    required RequestCancellation cancellation,
  });
}

final class CastService {
  const CastService({required this.controlUri, required this.type});
  final Uri controlUri;
  final String type;
}

final class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.controlUri,
    required this.serviceType,
    this.bilibiliService,
  });
  final String id, name, serviceType;
  final Uri controlUri;
  final CastService? bilibiliService;
}

enum CastCommand { play, pause, stop }

abstract interface class CastDeviceRepository {
  Stream<CastDevice> discover({required RequestCancellation cancellation});
  Future<void> setMedia(
    CastDevice device,
    CastMedia media,
    String title, {
    required RequestCancellation cancellation,
  });
  Future<void> command(
    CastDevice device,
    CastCommand command, {
    required RequestCancellation cancellation,
  });
  Future<void> setDanmaku(
    CastDevice device,
    bool enabled, {
    required RequestCancellation cancellation,
  });
  void dispose();
}
