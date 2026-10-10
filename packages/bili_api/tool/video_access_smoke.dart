import 'package:bili_api/bili_api.dart';

/// Explicit guest reads. Never prints credentials, media URLs or response text.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final bvid = args.firstOrNull ?? 'BV1q6ad6NEVK';
    final detail = await api.getVideoDetail(bvid);
    print(
      '$bvid access=${detail.access.kind.name} '
      'canWatch=${detail.access.canWatch} '
      'canPreview=${detail.access.canPreview}',
    );
    for (final preview in [false, true]) {
      try {
        final info = preview
            ? await api.getVideoPreviewInfo(bvid, detail.pages.first.cid)
            : await api.getPlayInfo(bvid, detail.pages.first.cid, qn: 32);
        print(
          'preview=$preview video=${info.dashVideo.length} '
          'audio=${info.dashAudio.length} isTrial=${info.isPreview}',
        );
      } on ApiFailure catch (failure) {
        print(
          'preview=$preview category=${failure.category.name} '
          'access=${failure.videoAccessKind?.name} '
          'endpoint=${failure.endpointId} business=${failure.businessCode}',
        );
      }
    }
    if (args.contains('--lists')) {
      for (final path in [
        '/x/web-interface/wbi/search/type',
        '/x/space/wbi/arc/search',
      ]) {
        try {
          final data = await api.requestWbiJson(
            path,
            path.contains('/space/')
                ? {
                    'mid': detail.ownerMid ?? '0',
                    'pn': '1',
                    'ps': '30',
                    'tid': '0',
                    'order': 'pubdate',
                  }
                : {
                    'keyword': bvid,
                    'search_type': 'video',
                    'page': '1',
                    'page_size': '20',
                  },
            'video_access_list_smoke',
          );
          final group = data['list'];
          final list = path.contains('/space/') && group is Map<String, Object?>
              ? group['vlist']
              : data['result'];
          for (final raw
              in (list is List<Object?> ? list : const <Object?>[])) {
            if (raw is! Map<String, Object?> || raw['bvid'] != bvid) continue;
            print(
              'list=$path accessFields=${raw.keys.where((key) => RegExp(r'pay|charg|upower|badge|exclusive').hasMatch(key)).join(",")}',
            );
            for (final key in raw.keys.where(
              (key) => RegExp(r'pay|charg|upower|exclusive').hasMatch(key),
            )) {
              final value = raw[key];
              if (value is bool || value is int) print('$key=$value');
            }
          }
        } on ApiFailure catch (failure) {
          print(
            'list=$path category=${failure.category.name} business=${failure.businessCode}',
          );
        }
      }
    }
  } finally {
    api.close();
  }
}
