import 'package:bili_api/bili_api.dart';

/// Explicit, bounded guest reads. Never prints image URLs or account headers.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final bvid = args.firstOrNull ?? 'BV1VEHn6TEKq';
    final detail = await api.getVideoDetail(bvid);
    final part = detail.pages.first;
    final client = PlaybackMetadataClient(api);
    final metadata = await client.load(detail.aid, part.cid);
    final shot = await client.storyboard(bvid, part.cid);
    print(
      'player metadata: chapters=${metadata.chapters.length}, subtitles=${metadata.subtitles.length}, '
      'chapterFailure=${metadata.chapterFailure?.category.name}, subtitleFailure=${metadata.subtitleFailure?.category.name}',
    );
    print(
      'storyboard: pages=${shot?.images.length ?? 0}, frames=${shot?.times.length ?? 0}, '
      'grid=${shot?.columns}x${shot?.rows}, tile=${shot?.tileWidth}x${shot?.tileHeight}',
    );
    if (metadata.chapters.isNotEmpty) {
      print(
        'chapter boundaries: ${metadata.chapters.map((c) => "${c.start.inSeconds}-${c.end.inSeconds}").join(",")}',
      );
    }
  } on ApiFailure catch (failure) {
    print(
      'FAILED category=${failure.category.name} endpoint=${failure.endpointId} '
      'status=${failure.httpStatus} business=${failure.businessCode}',
    );
    rethrow;
  } finally {
    api.close();
  }
}
