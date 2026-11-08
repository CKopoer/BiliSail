import 'dart:async';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/feed/domain/dynamic_author.dart';
import 'package:bilisail/features/feed/domain/home_channel.dart';
import 'package:bilisail/features/feed/domain/home_repository.dart';

DynamicAuthor author(int id) =>
    DynamicAuthor(id: UserId('$id'), name: 'UP 主 $id', hasUpdate: id.isOdd);

final class DynamicAuthorRepository
    implements HomeRepository, HomeDynamicRepository {
  String scope = 'user:7';
  bool deferAuthors = false;
  bool deferFeeds = false;
  int allReads = 0;
  final authorCalls =
      <
        ({
          String? cursor,
          RequestCancellation cancellation,
          Completer<DynamicAuthorPage> result,
        })
      >[];
  final feedCalls =
      <
        ({
          HomeQuery query,
          UserId authorId,
          int page,
          String? cursor,
          RequestCancellation cancellation,
          Completer<HomePage> result,
        })
      >[];

  @override
  String get accountScope => scope;

  @override
  Future<DynamicAuthorPage> loadDynamicAuthors({
    required String scope,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<DynamicAuthorPage>();
    authorCalls.add((
      cursor: cursor,
      cancellation: cancellation,
      result: result,
    ));
    if (!deferAuthors) {
      result.complete(
        DynamicAuthorPage([
          for (var i = 1; i <= 40; i++) author(i),
        ], hasMore: false),
      );
    }
    return result.future;
  }

  @override
  Future<HomePage> loadAuthorFeed(
    HomeQuery query,
    UserId authorId, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    final result = Completer<HomePage>();
    feedCalls.add((
      query: query,
      authorId: authorId,
      page: page,
      cursor: cursor,
      cancellation: cancellation,
      result: result,
    ));
    if (!deferFeeds) result.complete(content(query, authorId));
    return result.future;
  }

  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) async {
    allReads++;
    return content(query, null);
  }

  HomePage content(HomeQuery query, UserId? authorId) => HomePage([
    for (var i = 1; i <= 30; i++)
      HomeEntry(
        id: '${authorId?.value ?? '0'}$i',
        title: '筛选 ${authorId?.value ?? '全部'} 视频 $i',
        kind: query.channel == HomeChannel.videoDynamic
            ? HomeEntryKind.video
            : HomeEntryKind.dynamic,
        dynamicPost: DynamicPost(
          id: '${authorId?.value ?? '0'}$i',
          authorId: authorId,
          authorName: '测试作者',
          text: '筛选 ${authorId?.value ?? '全部'} 图文 $i',
        ),
        bvid: 'BV1abc${i.toString().padLeft(6, '0')}',
      ),
  ], hasMore: false);
}
