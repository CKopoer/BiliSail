import 'dart:async';

import 'package:bilisail/domain/app_failure.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/features/live/domain/live_preview_repository.dart';
import 'package:bilisail/features/live/domain/live_room.dart';

LiveStream livePreviewStream({
  String format = 'fmp4',
  String codec = 'avc',
  int urls = 2,
}) => LiveStream(
  urls: List.generate(
    urls,
    (i) => Uri.parse(
      'https://cdn$i.bilivideo.com/live/$codec.$format?token=a%2Fb&v=1',
    ),
  ),
  quality: 80,
  qualityLabel: '流畅',
  format: format,
  codec: codec,
);

class LivePreviewFakeRepository implements LivePreviewRepository {
  @override
  String accountScope = 'guest';
  @override
  int sessionEpoch = 0;
  final rooms = <RoomId>[];
  final tokens = <RequestCancellation>[];
  Completer<LivePlayInfo>? pending;
  AppFailure? failure;
  late LivePlayInfo info = LivePlayInfo(
    roomId: const RoomId('12'),
    isLive: true,
    streams: [livePreviewStream()],
  );

  @override
  Future<LivePlayInfo> loadPreview(
    RoomId id, {
    required RequestCancellation cancellation,
  }) async {
    rooms.add(id);
    tokens.add(cancellation);
    if (failure case final error?) throw error;
    return pending == null ? info : await pending!.future;
  }
}
