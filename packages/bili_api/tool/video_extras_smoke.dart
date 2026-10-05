import 'package:bili_api/bili_api.dart';

/// Developer-invoked, bounded public reads only; never prints content or URLs.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final bvid = args.isEmpty ? 'BV1cGbK6hEQK' : args.first;
    final detail = await api.getVideoDetail(bvid);
    print(
      'detail: collection=${detail.collection != null}, parts=${detail.pages.length}',
    );
    print('related: count=${(await api.getRelatedVideos(bvid)).length}');
    for (final sort in ApiCommentSort.values) {
      try {
        final page = await api.getVideoComments(detail.aid, sort: sort);
        final times =
            page.items.map((e) => e.publishedAt).whereType<DateTime>().toList();
        final descending = List.generate(
          times.isNotEmpty ? times.length - 1 : 0,
          (i) => !times[i].isBefore(times[i + 1]),
        ).every((e) => e);
        print(
          'comments ${sort.name}: count=${page.items.length}, total=${page.totalCount}, '
          'hasMore=${page.hasMore}, avatars=${page.items.where((e) => e.avatarUrl != null).length}, '
          'timestampsDescending=$descending',
        );
        if (sort == ApiCommentSort.hot) {
          final roots = page.items.where((e) => e.replyCount > 0);
          if (roots.isNotEmpty) {
            final replies = await api.getVideoReplies(
              detail.aid,
              roots.first.id,
            );
            print(
              'replies: count=${replies.items.length}, total=${replies.totalCount}, hasMore=${replies.hasMore}',
            );
          }
        }
      } on ApiFailure catch (error) {
        print(
          'comments ${sort.name}: ${error.category.name}, http=${error.httpStatus}, code=${error.businessCode}',
        );
      }
    }
    if (detail.collection == null && !args.contains('--sort-only')) {
      final popular = await api.getPopular();
      for (final video in popular.items.take(3)) {
        final candidate = await api.getVideoDetail(video.bvid);
        print(
          'collection candidate: collection=${candidate.collection != null}, parts=${candidate.pages.length}',
        );
        if (candidate.collection case final collection?) {
          print(
            'collection: entries=${collection.entries.length}, '
            'knownParts=${collection.entries.fold<int>(0, (n, e) => n + e.pages.length)}, '
            'lazyEntries=${collection.entries.where((e) => e.pages.isEmpty).length}',
          );
          break;
        }
      }
    }
  } on ApiFailure catch (error) {
    print(
      'smoke: ${error.category.name}, http=${error.httpStatus}, code=${error.businessCode}',
    );
  } finally {
    api.close();
  }
}
