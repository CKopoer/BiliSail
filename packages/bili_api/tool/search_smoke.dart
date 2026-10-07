import 'package:bili_api/bili_api.dart';

/// Explicit guest-only reads. Never loads or prints account credentials.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final client = SearchClient(api);
    final keyword = args.isEmpty ? '哔哩哔哩' : args.first;
    final types = args.length < 2
        ? ApiSearchType.values
        : ApiSearchType.values.where((type) => type.name == args[1]);
    for (final type in types) {
      try {
        final page = await client.search(
          keyword,
          type: type,
          order: args.length < 3 ? 'totalrank' : args[2],
          page: args.length < 4 ? 1 : int.parse(args[3]),
        );
        print(
          '${type.name}: items=${page.items.length}, more=${page.hasMore}, '
          'counts=${page.counts.map((k, v) => MapEntry(k.name, v))}',
        );
        print(
          'kinds=${page.items.map((item) => item.runtimeType).toSet()}, '
          'previews=${page.items.whereType<ApiSearchUser>().fold<int>(0, (n, user) => n + user.videos.length)}',
        );
        final firstUser = page.items.whereType<ApiSearchUser>().firstOrNull;
        if (firstUser != null) {
          print('first user=${firstUser.name}, mid=${firstUser.mid}');
          print(
            'preview stats=${firstUser.videos.map((video) => (video.playCount, video.danmakuCount)).toList()}',
          );
        }
        print(
          'video stats=${page.items.whereType<ApiSearchVideo>().take(3).map((item) => (item.video.playCount, item.video.publishedAt)).toList()}',
        );
      } on ApiFailure catch (e) {
        print(
          '${type.name}: ${e.category.name}, HTTP ${e.httpStatus}, business ${e.businessCode}',
        );
      }
    }
  } finally {
    api.close();
  }
}
