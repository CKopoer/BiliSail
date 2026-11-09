import 'dart:async';

import 'package:bilisail/domain/dynamic_post.dart';
import 'package:bilisail/domain/request_cancellation.dart';
import 'package:bilisail/domain/user.dart';
import 'package:bilisail/features/dynamic/domain/dynamic_topic_repository.dart';

typedef TopicQuery = ({
  String id,
  int sort,
  String? cursor,
  bool folded,
  RequestCancellation cancellation,
});

class DynamicTopicRepositoryFake implements DynamicTopicRepository {
  final favorites = <(String, bool)>[];
  final reports = <(String, String)>[];
  Future<void> Function(RequestCancellation)? onWrite;
  @override
  Future<void> favorite(
    String id,
    bool value,
    RequestCancellation cancellation,
  ) async {
    favorites.add((id, value));
    await onWrite?.call(cancellation);
    header = header.withFavorite(value);
  }

  @override
  Future<void> report(
    String id,
    String reason,
    RequestCancellation cancellation,
  ) async {
    reports.add((id, reason));
    await onWrite?.call(cancellation);
  }

  @override
  String accountScope = 'user:7';
  @override
  int sessionEpoch = 1;
  final queries = <TopicQuery>[];
  final details = <RequestCancellation>[];
  Future<DynamicTopicPage> Function(TopicQuery)? onFeed;
  Completer<DynamicTopicDetail>? pendingDetail;
  DynamicTopicDetail header = const DynamicTopicDetail(
    id: '12',
    name: '应用内话题',
    description: '话题简介',
    viewCount: 123,
    discussCount: 45,
    creatorId: UserId('7'),
    creatorName: '发起人',
  );
  DynamicTopicPage page = DynamicTopicPage(
    posts: [DynamicPost(id: '1', text: '话题动态')],
    hasMore: false,
    sorts: const [DynamicTopicSort(0, '综合'), DynamicTopicSort(2, '最新')],
  );

  @override
  Future<DynamicTopicDetail> detail(
    String id,
    RequestCancellation cancellation,
  ) async {
    details.add(cancellation);
    return pendingDetail?.future ?? header;
  }

  @override
  Future<DynamicTopicPage> feed(
    String id, {
    required int sort,
    String? cursor,
    bool folded = false,
    required RequestCancellation cancellation,
  }) async {
    final query = (
      id: id,
      sort: sort,
      cursor: cursor,
      folded: folded,
      cancellation: cancellation,
    );
    queries.add(query);
    return onFeed?.call(query) ?? page;
  }
}
