import '../../../shared/data/dynamic_post_mapper.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../domain/home_repository.dart';

final class ApiHomeRepository implements HomeRepository {
  ApiHomeRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
    // Retain the meaningful public named argument without exposing the callback.
    // ignore: prefer_initializing_formals
  }) : _accountScope = accountScope;
  final HomeClient client;
  final ApiRequests requests;
  final String Function() _accountScope;
  @override
  String get accountScope => _accountScope();
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    if (query.scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    final result = await client.load(
      channel: query.channel.name,
      section: query.section,
      page: page,
      cursor: cursor,
      mid: query.scope.startsWith('user:') ? query.scope.substring(5) : null,
      folderId: query.folderId,
      context: context,
    );
    if (query.scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    return HomePage(
      List.unmodifiable(result.items.map(_entry)),
      hasMore: result.hasMore,
      nextCursor: result.nextCursor,
    );
  }, cancellation: cancellation);
  static HomeEntry _entry(ApiHomeEntry item) => HomeEntry(
    id: item.id,
    dynamicPost: item.dynamicPost == null
        ? null
        : mapDynamicPost(item.dynamicPost!),
    title: item.title,
    kind: HomeEntryKind.values.byName(item.kind.name),
    coverUrl: item.coverUrl,
    subtitle: item.subtitle,
    description: item.description,
    bvid: item.bvid,
    url: item.url,
    authorName: item.authorName,
    authorAvatarUrl: item.authorAvatarUrl,
    authorMid: item.authorMid,
    duration: item.duration,
    publishedAt: item.publishedAt,
    publishText: item.publishText,
    playCountText: item.playCountText,
    danmakuCountText: item.danmakuCountText,
    popularityText: item.popularityText,
    areaName: item.areaName,
    children: List.unmodifiable(item.children.map(_entry)),
  );
}
