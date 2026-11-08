import '../../../shared/data/dynamic_post_mapper.dart';

import 'package:bili_api/bili_api.dart';

import '../../../shared/data/video_access_mapper.dart';

import '../../../core/network/api_requests.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../live/domain/live_room.dart';
import '../domain/profile_repository.dart';
import '../domain/profile_report.dart';

class ApiProfileRepository
    implements
        ProfileRepository,
        ProfileFollowGroupsRepository,
        ProfileFollowingManagementRepository,
        ProfileDetailsRepository,
        ProfileReportRepository,
        ProfileActionsRepository {
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
  Future<ProfilePage> loadManagedFollowing(
    UserId owner, {
    required int page,
    String keyword = '',
    String order = '',
    bool blacklist = false,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _requireFollowGroupOwner(owner);
    final result = blacklist
        ? await client.loadBlacklist(page: page, context: context)
        : keyword.isNotEmpty
        ? await client.searchFollowing(
            owner.value,
            keyword,
            page: page,
            context: context,
          )
        : await client.loadRelations(
            owner.value,
            followers: false,
            page: page,
            orderType: order,
            context: context,
          );
    return ProfilePage(
      items: List.unmodifiable(result.items.map(_entry)),
      hasMore: result.hasMore,
    );
  }, cancellation: cancellation);

  @override
  Future<ProfileFollowGroup?> editFollowGroup(
    UserId owner,
    FollowGroupEdit edit, {
    String? groupId,
    String name = '',
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _requireFollowGroupOwner(owner);
    final groups = FollowGroupClient(client.api);
    switch (edit) {
      case FollowGroupEdit.create:
        final created = await groups.create(name, context: context);
        return ProfileFollowGroup(id: created.id, name: created.name);
      case FollowGroupEdit.rename:
        if (groupId == null) throw ArgumentError('Missing group');
        await groups.rename(groupId, name, context: context);
      case FollowGroupEdit.delete:
        if (groupId == null) throw ArgumentError('Missing group');
        await groups.delete(groupId, context: context);
    }
    return null;
  }, cancellation: cancellation);

  @override
  Future<void> sortFollowGroups(
    UserId owner,
    List<String> ids, {
    required RequestCancellation cancellation,
  }) => requests.run((context) {
    _requireFollowGroupOwner(owner);
    return FollowGroupClient(client.api).sort(ids, context: context);
  }, cancellation: cancellation);

  @override
  Future<void> setFollowingBlocked(
    UserId owner,
    UserId target,
    bool blocked, {
    required RequestCancellation cancellation,
  }) => requests.run((context) {
    _requireFollowGroupOwner(owner);
    if (target == owner) throw ArgumentError('Cannot block self');
    return client.setBlocked(target.value, blocked, context: context);
  }, cancellation: cancellation);

  void _requireFollowGroupOwner(UserId id) {
    if (accountScope != 'user:${id.value}') {
      throw const AppFailure(AppFailureKind.permission, '只能查看自己的关注分组');
    }
  }

  @override
  Future<List<ProfileFollowGroup>> loadFollowGroups(
    UserId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _requireFollowGroupOwner(id);
    final groups = await FollowGroupClient(client.api)
        .groups(includeReserved: true, context: context);
    return List.unmodifiable([
      if (!groups.any((group) => group.id == '0'))
        const ProfileFollowGroup(id: '0', name: '默认分组'),
      for (final group in groups)
        ProfileFollowGroup(id: group.id, name: group.name),
    ]);
  }, cancellation: cancellation);

  @override
  Future<ProfilePage> loadFollowingGroup(
    UserId id,
    String groupId, {
    required int page,
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    _requireFollowGroupOwner(id);
    final result = await client.loadFollowingGroup(
      id.value,
      groupId,
      page: page,
      context: context,
    );
    return ProfilePage(
      items: List.unmodifiable(result.items.map(_entry)),
      hasMore: result.hasMore,
      cursor: result.nextCursor,
    );
  }, cancellation: cancellation);

  @override
  Future<void> report(
    UserId id,
    ProfileReport report, {
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) => client.report(
      id.value,
      contents: report.contents
          .map(
            (content) => switch (content) {
              ProfileReportContent.avatar => 1,
              ProfileReportContent.nickname => 2,
              ProfileReportContent.signature => 3,
            },
          )
          .toSet(),
      reason: switch (report.reason) {
        null => null,
        ProfileReportReason.sexualContent => 1,
        ProfileReportReason.misinformation => 2,
        ProfileReportReason.prohibitedContent => 3,
        ProfileReportReason.personalAttack => 4,
        ProfileReportReason.gamblingFraud => 5,
        ProfileReportReason.illegalPromotion => 6,
      },
      context: context,
    ),
    cancellation: cancellation,
  );
  @override
  Future<bool> loadBlocked(
    UserId id, {
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) => client.loadBlocked(id.value, context: context),
    cancellation: cancellation,
  );
  @override
  Future<void> setBlocked(
    UserId id,
    bool blocked, {
    required RequestCancellation cancellation,
  }) => requests.run(
    (context) => client.setBlocked(id.value, blocked, context: context),
    cancellation: cancellation,
  );
  @override
  Future<ProfileSpaceDetails> loadDetails(
    UserId id, {
    required RequestCancellation cancellation,
  }) => _read(
    requests.run((context) async {
      final details = await client.loadDetails(id.value, context: context);
      return ProfileSpaceDetails(
        bannerUrl: details.bannerUrl,
        gender: details.gender,
        birthday: details.birthday,
      );
    }, cancellation: cancellation),
  );
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
        pendantUrl: p.pendantUrl,
        bannerUrl: p.bannerUrl,
        vipLabelImageUrl: p.vipLabelImageUrl,
        vipStatus: p.vipStatus,
        vipType: p.vipType,
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
  Future<ProfileLiveRoom?> loadLiveRoom(
    UserId id, {
    required RequestCancellation cancellation,
  }) => requests.run((context) async {
    final room = await client.loadLiveRoom(id.value, context: context);
    return room == null
        ? null
        : ProfileLiveRoom(id: RoomId(room.roomId), isLive: room.isLive);
  }, cancellation: cancellation);
  @override
  Future<ProfilePage> loadEntries(
    UserId id,
    ProfileSection section, {
    required int page,
    String? cursor,
    String order = 'pubdate',
    String keyword = '',
    String? folderId,
    ProfileCollectionId? collection,
    required RequestCancellation cancellation,
  }) => _read(
    requests.run((context) async {
      final isRelation =
          section == ProfileSection.following ||
          section == ProfileSection.followers;
      final isPrivateContent =
          section == ProfileSection.folders ||
          section == ProfileSection.bangumi ||
          section == ProfileSection.cinema;
      if (isPrivateContent && accountScope != 'user:${id.value}') {
        final privacy = await client.loadContentPrivacy(
          id.value,
          context: context,
        );
        if (section == ProfileSection.folders
            ? privacy.foldersHidden
            : privacy.seasonsHidden) {
          return const ProfilePage.hidden();
        }
      }
      // The owner can view their own lists even when hidden from visitors.
      if (isRelation && accountScope != 'user:${id.value}') {
        final privacy = await client.loadRelationPrivacy(
          id.value,
          context: context,
        );
        final hidden = section == ProfileSection.following
            ? privacy.followingHidden
            : privacy.followersHidden;
        if (hidden) return const ProfilePage.hidden();
      }
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
        ProfileSection.collections =>
          collection == null
              ? client.loadCollections(id.value, page: page, context: context)
              : client.loadCollectionVideos(
                  id.value,
                  collection.value,
                  isSeries: collection.isSeries,
                  page: page,
                  context: context,
                ),
        ProfileSection.bangumi ||
        ProfileSection.cinema => client.loadFollowedSeasons(
          id.value,
          cinema: section == ProfileSection.cinema,
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
      collection: switch (e.collectionId) {
        final id? => ProfileCollectionId(id, isSeries: e.isSeries),
        _ => null,
      },
      seasonId: e.seasonId,
      imageUrls: List.unmodifiable(e.imageUrls),
      video: v == null
          ? null
          : VideoSummary(
              id: VideoId(v.bvid),
              access: mapVideoAccess(v.access),
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
