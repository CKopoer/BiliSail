import '../../../domain/request_cancellation.dart';
import '../../../domain/video.dart';

typedef PgcDanmakuTarget = ({String episodeId, VideoId video, String cid});

/// An interrupted write may already have reached the server. The caller must
/// retain the draft and never replay it automatically.
final class PgcDanmakuWriteUncertain implements Exception {
  const PgcDanmakuWriteUncertain();
}

abstract interface class PgcDanmakuRepository {
  String get accountScope;
  int get sessionEpoch;

  Future<void> send(
    PgcDanmakuTarget target,
    String text,
    Duration position, {
    required int mode,
    required int color,
    required RequestCancellation cancellation,
  });
}
