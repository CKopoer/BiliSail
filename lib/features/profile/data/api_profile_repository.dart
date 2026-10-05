import '../../../shared/data/dynamic_post_mapper.dart';

import 'package:bili_api/bili_api.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../domain/profile_repository.dart';

class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository(
    this.client,
    this.requests, {
    required String Function() accountScope,
  }) : _scope = accountScope;
  final ProfileClient client;
  final ApiRequests requests;
  final String Function() _scope;
  @override
  String get accountScope => _scope();
  @override
  int get sessionEpoch => requests.sessionEpoch;
  @override
  Future<UserProfile> loadProfile(
    UserId id, {
    required RequestCancellation cancellation,
  }) => _read(
    requests.run((context) async {
      final p = await client.loadProfile(id.value, context: context);
      return UserProfile(
        id: UserId(p.mid),
        name: p.name,
        avatarUrl: p.avatarUrl,
        signature: p.signature,
        level: p.level,
        verifyType: p.verifyType,
        verifyDescription: p.verifyDescription,
        vipLabel: p.vipLabel,
        followerCount: p.followerCount,
        followingCount: p.followingCount,
        likeCount: p.likeCount,
        videoCount: p.videoCount,
      );
    }, cancellation: cancellation),
  );
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    required RequestCancellation cancellation,
  }) => _read(
    requests.run((context) async {
      final result = await switch (section) {
        ProfileSection.videos => client.loadVideos(
          id.value,
          page: page,
          order: order,
          keyword: keyword,
          context: context,
        ),
        ProfileSection.dynamics => client.loadDynamics(
          id.value,
          cursor: cursor,
          context: context,
        ),
        ProfileSection.folders =>
          folderId == null
              ? client.loadFolders(id.value, page: page, context: context)
              : client.loadFolderVideos(folderId, page: page, context: context),
        ProfileSection.following => client.loadRelations(
          id.value,
          followers: false,
          page: page,
          context: context,
        ),
        ProfileSection.followers => client.loadRelations(
          id.value,
          followers: true,
          page: page,
          context: context,
        ),
      };
      return ProfilePage(
        items: List.unmodifiable(result.items.map(_entry)),
        hasMore: result.hasMore,
        cursor: result.nextCursor,
      );
    }, cancellation: cancellation),
  );
  Future<T> _read<T>(Future<T> request) async {
    try {
      return await request;
    } on AppFailure catch (error) {
      if (error.kind == AppFailureKind.notFound) {
        throw const AppFailure(AppFailureKind.notFound, '用户或主页内容不存在，可能已被删除');
      }
      if (error.kind == AppFailureKind.permission) {
        throw const AppFailure(
          AppFailureKind.permission,
          '该主页内容暂不可见，可能为私密或受限内容',
        );
      }
      rethrow;
    }
  }

  ProfileEntry _entry(ApiProfileEntry e) {
    final v = e.video;
    return ProfileEntry(
      id: e.id,
      dynamicPost: e.dynamicPost == null
          ? null
          : mapDynamicPost(e.dynamicPost!),
      kind: ProfileEntryKind.values.byName(e.kind.name),
      title: e.title,
      subtitle: e.subtitle,
      coverUrl: e.coverUrl,
      userId: e.userMid == null ? null : UserId(e.userMid!),
      publishedAt: e.publishedAt,
      count: e.count,
      imageUrls: List.unmodifiable(e.imageUrls),
      video: v == null
          ? null
          : VideoSummary(
              id: VideoId(v.bvid),
              title: v.title,
              coverUrl: v.coverUrl?.toString() ?? '',
              author: v.ownerName,
              authorAvatarUrl: v.ownerAvatarUrl,
              authorId: v.ownerMid == null ? null : UserId(v.ownerMid!),
              duration: v.duration,
              playCount: v.playCount,
              danmakuCount: v.danmakuCount,
              publishedAt: v.publishedAt,
            ),
    );
  }
}
