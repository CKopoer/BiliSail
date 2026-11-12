import '../../../shared/data/dynamic_post_mapper.dart';
import '../../../shared/data/video_access_mapper.dart';

import 'dart:math';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../domain/dynamic_author.dart';
import '../domain/home_repository.dart';
import '../domain/home_channel.dart';
import '../../video/domain/video_actions_repository.dart';

final class ApiHomeRepository
    implements
        HomeRepository,
        HomeDynamicRepository,
        HomeSubscriptionRepository,
        HomeFavoriteRepository,
        HomeWatchLaterRepository {
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
  static const _snapshotPrefix = 'local-favorite-';
  static const _snapshotPageSize = 99;
  static const _maximumSnapshotItems = 5000;
  final _snapshotNonce = Random.secure().nextInt(1 << 32).toRadixString(16);
  final Map<
    String,
    ({
      HomeQuery query,
      int epoch,
      List<HomeEntry> items,
      String? favoriteFolderId,
    })
  >
  _snapshots = {};
  RequestCancellation? _snapshotLifetime;
  int _nextSnapshot = 0;

  HomePage _snapshotPage(String key, HomeQuery query, int page) {
    final snapshot = _snapshots[key];
    if (snapshot == null ||
        snapshot.query != query ||
        snapshot.epoch != requests.sessionEpoch) {
      throw const AppFailure(AppFailureKind.notFound, '收藏列表快照已失效，请刷新后重试');
    }
    _snapshots.remove(key);
    _snapshots[key] = snapshot;
    final start = (page - 1) * _snapshotPageSize;
    return HomePage(
      List.unmodifiable(snapshot.items.skip(start).take(_snapshotPageSize)),
      hasMore: start + _snapshotPageSize < snapshot.items.length,
      nextCursor: key,
      favoriteFolderId: snapshot.favoriteFolderId,
    );
  }

  HomePage _publishSnapshot(
    HomeQuery query,
    List<HomeEntry> items,
    int page,
    String? favoriteFolderId,
  ) {
    if (_snapshotLifetime == null || _snapshotLifetime!.isCancelled) {
      final lifetime = _snapshotLifetime = RequestCancellation();
      lifetime.onCancel(_snapshots.clear);
      requests.trackLifetime(lifetime);
    }
    final key = '$_snapshotPrefix$_snapshotNonce-${++_nextSnapshot}';
    _snapshots[key] = (
      query: query,
      epoch: requests.sessionEpoch,
      items: List.unmodifiable(items.take(_maximumSnapshotItems)),
      favoriteFolderId: favoriteFolderId,
    );
    while (_snapshots.length > 16) {
      _snapshots.remove(_snapshots.keys.first);
    }
    return _snapshotPage(key, query, page);
  }

  @override
  String get accountScope => _accountScope();

  @override
  Future<DynamicAuthorPage> loadDynamicAuthors({
    required String scope,
    String? cursor,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    final result = await client.dynamicAuthors(
      cursor: cursor,
      context: context,
    );
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    return DynamicAuthorPage(
      List.unmodifiable(
        result.items.map(
          (item) => DynamicAuthor(
            id: UserId(item.mid),
            name: item.name,
            avatarUrl: item.avatarUrl,
            hasUpdate: item.hasUpdate,
          ),
        ),
      ),
      hasMore: result.hasMore,
      nextCursor: result.nextCursor,
    );
  }, cancellation: cancellation);

  @override
  Future<HomePage> loadAuthorFeed(
    HomeQuery query,
    UserId authorId, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) {
    if (!authorId.isValid ||
        query.channel != HomeChannel.dynamic &&
            query.channel != HomeChannel.videoDynamic) {
      throw ArgumentError('Invalid dynamic author query');
    }
    return _load(
      query,
      page: page,
      cursor: cursor,
      authorId: authorId,
      cancellation: cancellation,
    );
  }

  Future<void> _writeFavorite(
    String folderId,
    String scope,
    RequestCancellation cancellation,
    Future<void> Function(ApiRequestContext) write,
  ) => requests.run((context) async {
    void checkScope() {
      if (scope != accountScope) {
        throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
      }
      if (!scope.startsWith('user:')) {
        throw const AppFailure(AppFailureKind.authentication, '请先登录');
      }
    }

    checkScope();
    final info = await FavoriteFolderClient(client.api)
        .load(folderId, context: context);
    checkScope();
    if (scope != 'user:${info.ownerMid}') {
      throw const AppFailure(AppFailureKind.permission, '只能操作自己创建的收藏夹');
    }
    try {
      await write(context);
    } on ApiFailure catch (failure) {
      if (context.cancellation?.isCancelled != true &&
          {
            ApiFailureCategory.network,
            ApiFailureCategory.timeout,
            ApiFailureCategory.http,
            ApiFailureCategory.protocol,
          }.contains(failure.category)) {
        throw const UnknownWriteOutcome();
      }
      rethrow;
    }
    checkScope();
    _snapshots.removeWhere(
      (_, snapshot) =>
          snapshot.query.scope == scope &&
          snapshot.favoriteFolderId == folderId,
    );
  }, cancellation: cancellation);

  @override
  Future<void> removeFavorite(
    HomeEntry entry, {
    required String folderId,
    required String scope,
    required RequestCancellation cancellation,
  }) {
    final aid = entry.aid;
    if (entry.kind != HomeEntryKind.video || aid == null) {
      throw const AppFailure(AppFailureKind.protocol, '收藏内容缺少视频标识，请刷新');
    }
    return _writeFavorite(
      folderId,
      scope,
      cancellation,
      (context) => client.removeFavorite(folderId, aid, context: context),
    );
  }

  @override
  Future<void> deleteFavoriteFolder(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) {
    if (entry.kind != HomeEntryKind.folder) {
      throw const AppFailure(AppFailureKind.permission, '只能删除自己创建的收藏夹');
    }
    return _writeFavorite(
      entry.id,
      scope,
      cancellation,
      (context) => client.deleteFavoriteFolder(entry.id, context: context),
    );
  }

  @override
  Future<void> removeWatchLater(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    if (entry.kind != HomeEntryKind.video) {
      throw const AppFailure(AppFailureKind.protocol, '无法识别稍后再看视频');
    }
    try {
      final aid = entry.aid;
      if (aid == null) {
        throw const AppFailure(AppFailureKind.protocol, '稍后再看条目缺少视频标识，请刷新');
      }
      await FeedCardActionsClient(client.api)
          .removeWatchLater(aid, context: context);
    } on ApiFailure catch (failure) {
      if (context.cancellation?.isCancelled != true &&
          {
            ApiFailureCategory.network,
            ApiFailureCategory.timeout,
            ApiFailureCategory.http,
            ApiFailureCategory.protocol,
          }.contains(failure.category)) {
        throw const UnknownWriteOutcome();
      }
      rethrow;
    }
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
  }, cancellation: cancellation);
  @override
  Future<void> unsubscribeFavorite(
    HomeEntry entry, {
    required String scope,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    if (!scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    if (entry.kind != HomeEntryKind.folder &&
        entry.kind != HomeEntryKind.collection) {
      throw ArgumentError('Only subscribed folders/collections can be removed');
    }
    await client.unsubscribeFavorite(
      entry.id,
      collection: entry.kind == HomeEntryKind.collection,
      context: context,
    );
    if (scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
  }, cancellation: cancellation);
  @override
  Future<HomePage> load(
    HomeQuery query, {
    required int page,
    String? cursor,
    required RequestCancellation cancellation,
  }) => _load(query, page: page, cursor: cursor, cancellation: cancellation);

  Future<HomePage> _load(
    HomeQuery query, {
    required int page,
    String? cursor,
    UserId? authorId,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    if (query.scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    if (authorId != null && !query.scope.startsWith('user:')) {
      throw const AppFailure(AppFailureKind.authentication, '请先登录');
    }
    if (page < 1) throw ArgumentError.value(page, 'page');
    if (cursor != null && cursor.startsWith(_snapshotPrefix)) {
      return _snapshotPage(cursor, query, page);
    }
    final result = await client.load(
      channel: query.channel.name,
      section: query.section,
      page: page,
      cursor: cursor,
      mid: query.scope.startsWith('user:') ? query.scope.substring(5) : null,
      folderId: query.folderId,
      authorId: authorId?.value,
      context: context,
    );
    if (query.scope != accountScope) {
      throw const AppFailure(AppFailureKind.cancelled, '请求已取消');
    }
    final items = List<HomeEntry>.unmodifiable(result.items.map(_entry));
    final favoriteFolderId =
        query.channel == HomeChannel.favorites &&
            query.folderId?.startsWith('ugc:') != true
        ? query.folderId ??
              (query.section == '默认收藏夹' ? result.nextCursor : null)
        : null;
    // Some collected UGC endpoints ignore ps and return the complete collection.
    // Expose bounded local pages without changing watch-later's full-list flow.
    if (query.channel == HomeChannel.favorites &&
        (query.folderId != null || query.section == '默认收藏夹') &&
        !result.hasMore &&
        items.length > _snapshotPageSize) {
      return _publishSnapshot(query, items, page, favoriteFolderId);
    }
    return HomePage(
      items,
      hasMore: result.hasMore,
      nextCursor: result.nextCursor,
      favoriteFolderId: favoriteFolderId,
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
    aid: item.aid,
    previewCid: item.previewCid,
    access: mapVideoAccess(item.access),
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
    contentCount: item.contentCount,
    viewCount: item.viewCount,
    isPrivate: item.isPrivate,
    createdAt: item.createdAt,
    children: List.unmodifiable(item.children.map(_entry)),
  );
}
