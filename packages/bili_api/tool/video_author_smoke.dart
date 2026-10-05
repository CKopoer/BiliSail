import 'dart:io';

import 'package:bili_api/bili_api.dart';

/// Explicit, guest-only read probe. Does not print IDs, credentials or URLs.
Future<void> main(List<String> args) async {
  final api = BiliApiClient();
  try {
    final detail = await api.getVideoDetail(args.firstOrNull ?? 'BV1GLHE6hEFg');
    final mid = detail.ownerMid;
    if (mid == null) throw StateError('No author ID');
    final author = await VideoAuthorClient(api).load(mid);
    print(
      'author: followers=${author.followerCount}, likes=${author.likeCount}, '
      'following=${author.following}',
    );
    print(
      'collection: entries=${detail.collection?.entries.length}, '
      'plays=${detail.collection?.playCount}, '
      'durations=${detail.collection?.entries.where((e) => e.duration != null).length}',
    );
  } on ApiFailure catch (error) {
    print(
      'failure: ${error.category.name}, http=${error.httpStatus}, code=${error.businessCode}',
    );
    exitCode = 1;
  } finally {
    api.close();
  }
}
