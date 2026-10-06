import 'package:bili_api/bili_api.dart';

/// Explicit guest reads; print only track metadata and CDN hosts, never URLs.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final bvid = args.firstOrNull ?? 'BV1HcHn6UEdF';
    final detail = await api.getVideoDetail(bvid);
    final part = detail.pages.first;
    final previewWatch = Stopwatch()..start();
    final preview = await api.getVideoPreviewInfo(bvid, part.cid);
    print(
      'PREVIEW elapsedMs=${previewWatch.elapsedMilliseconds} '
      'video=${preview.dashVideo.length} audio=${preview.dashAudio.length}',
    );
    for (final track in preview.dashVideo.where((t) => t.id == 32)) {
      print(
        'PREVIEW track id=${track.id} codec=${track.codecs} '
        'hosts=${[track.url, ...track.backupUrls].map((u) => u.host).join(",")}',
      );
    }
    for (final qn in [32, 80]) {
      final info = await api.getPlayInfo(bvid, part.cid, qn: qn);
      print(
        '$bvid qn=$qn duration=${info.duration.inSeconds}s '
        'video=${info.dashVideo.length} audio=${info.dashAudio.length}',
      );
      for (final track in [...info.dashVideo, ...info.dashAudio]) {
        print(
          'track id=${track.id} codec=${track.codecs} '
          'bandwidth=${track.bandwidth} '
          'hosts=${[track.url, ...track.backupUrls].map((u) => u.host).join(",")}',
        );
      }
    }
  } on ApiFailure catch (failure) {
    print(
      'FAILED category=${failure.category.name} endpoint=${failure.endpointId} '
      'status=${failure.httpStatus} business=${failure.businessCode}',
    );
    // ApiFailure intentionally contains no response body or credential values.
    rethrow;
  } finally {
    api.close();
  }
}
