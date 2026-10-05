// Explicit, low-frequency guest-only read smoke. Never prints IDs, URLs,
// QR keys, cookies, response bodies, or query strings.
import 'package:bili_api/bili_api.dart';

Future<void> main() async {
  final client = BiliApiClient();
  try {
    final popular = await _run('popular', () => client.getPopular());
    await _run('nav', () => client.getNav());
    await _run('qr_generate', () => client.generateQr());
    await _run('search', () => client.searchVideos('flutter'));
    if (popular == null || popular.items.isEmpty) return;
    final detail = await _run(
      'detail',
      () => client.getVideoDetail(popular.items.first.bvid),
    );
    if (detail == null) return;
    await _run(
      'playurl',
      () => client.getPlayInfo(detail.bvid, detail.pages.first.cid),
    );
    await _run(
      'subtitle_index',
      () => client.getSubtitleTracks(detail.aid, detail.pages.first.cid),
    );
    await _run(
      'danmaku_segment',
      () => client.getDanmakuSegment(detail.pages.first.cid, 1),
    );
  } finally {
    client.close();
  }
}

Future<T?> _run<T>(String name, Future<T> Function() work) async {
  try {
    final result = await work();
    print('$name: success');
    return result;
  } on ApiFailure catch (failure) {
    print(
      '$name: ${failure.category.name} '
      'http=${failure.httpStatus} code=${failure.businessCode}',
    );
    return null;
  }
}
