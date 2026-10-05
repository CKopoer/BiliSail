import 'package:bili_api/bili_api.dart';

/// Manual guest-only protocol smoke. Never logs content, cookies, or URLs.
Future<void> main() async {
  final api = BiliApiClient();
  final home = HomeClient(api);
  try {
    for (final target in const [
      (channel: 'bangumi', section: '推荐'),
      (channel: 'bangumi', section: '时间表'),
      (channel: 'live', section: '全部分区'),
      (channel: 'live', section: '推荐直播'),
    ]) {
      try {
        final page = await home.load(
          channel: target.channel,
          section: target.section,
          page: 1,
          context: ApiRequestContext(
            deadline: DateTime.now().add(const Duration(seconds: 20)),
          ),
        );
        final kinds = page.items.map((entry) => entry.kind.name).toSet();
        print(
          '${target.channel}/${target.section}: code=0 '
          'count=${page.items.length} kinds=${kinds.join(',')} '
          'hasMore=${page.hasMore}',
        );
      } on ApiFailure catch (failure) {
        print(
          '${target.channel}/${target.section}: '
          'category=${failure.category.name} '
          'businessCode=${failure.businessCode} '
          'httpStatus=${failure.httpStatus}',
        );
      }
    }
  } finally {
    api.close();
  }
}
