import '../../../domain/request_cancellation.dart';

final class CastMediaRequest {
  const CastMediaRequest({
    required this.cid,
    required this.quality,
    this.aid,
    this.bvid,
    this.episodeId,
  });
  final String cid;
  final int quality;
  final String? aid, bvid, episodeId;
}

abstract interface class CastMediaRepository {
  Future<Uri> resolve(
    CastMediaRequest request, {
    required RequestCancellation cancellation,
  });
}

final class CastDevice {
  const CastDevice({
    required this.id,
    required this.name,
    required this.controlUri,
    required this.serviceType,
  });
  final String id, name, serviceType;
  final Uri controlUri;
}

enum CastCommand { play, pause, stop }

abstract interface class CastDeviceRepository {
  Stream<CastDevice> discover({required RequestCancellation cancellation});
  Future<void> setMedia(
    CastDevice device,
    Uri uri,
    String title, {
    required RequestCancellation cancellation,
  });
  Future<void> command(
    CastDevice device,
    CastCommand command, {
    required RequestCancellation cancellation,
  });
  void dispose();
}
