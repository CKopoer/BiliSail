import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../core/presentation/page_back_scope.dart';
import '../../../domain/request_cancellation.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/playback_navigation.dart';
import '../../../shared/ui/image_viewer.dart';
import '../../live/domain/live_room.dart';
import '../../dynamic/domain/dynamic_link.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/scroll_collapsing_header.dart';
import '../../../shared/ui/user_follow_button.dart';
import '../../auth/application/auth_controller.dart';
import 'profile_header.dart';
import 'profile_details_dialog.dart';
import 'profile_report_dialog.dart';
import 'profile_section_content.dart';
import 'profile_follow_groups_tabs.dart';
import 'profile_following_tools.dart';
import '../application/profile_controller.dart';
import '../application/profile_actions_controller.dart';
import '../domain/profile_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    required this.id,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenPlaylist,
    this.onOpenLiveRoom,
    this.onOpenSeason,
    this.onMessage,
    this.onLogin,
    this.isSelf = false,
    this.initialSection = ProfileSection.videos,
  });
  final UserId id;
  final void Function(UserId)? onOpenUser;
  final void Function(VideoSummary)? onOpenVideo;
  final void Function(VideoSummary, String queueId)? onOpenPlaylist;
  final void Function(RoomId)? onOpenLiveRoom;
  final ValueChanged<String>? onOpenSeason;
  final ValueChanged<UserProfile>? onMessage;
  final VoidCallback? onLogin;
  final bool isSelf;
  final ProfileSection initialSection;
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  RequestCancellation? _reportCancellation;
  late final _pagingProgress = TabPagingProgress(
    widget.initialSection.index.toDouble(),
  );

  Future<void> _copy(String value, String notice) async {
    try {
      await Clipboard.setData(ClipboardData(text: value));
      if (mounted) showAppNotice(context, notice);
    } catch (_) {
      if (mounted) showAppNotice(context, '复制失败，请重试');
    }
  }

  Future<void> _openWebsite() async {
    try {
      final opened = await ref.read(externalLinkOpenerProvider)(
        Uri.https('space.bilibili.com', '/${widget.id.value}'),
      );
      if (mounted && !opened) showAppNotice(context, '无法打开主页链接');
    } catch (_) {
      if (mounted) showAppNotice(context, '无法打开主页链接');
    }
  }

  Future<void> _report(UserProfile profile) async {
    if (!ref.read(authControllerProvider).isSignedIn) {
      widget.onLogin?.call();
      return;
    }
    final repository = ref.read(profileRepositoryProvider);
    final account = (repository.accountScope, repository.sessionEpoch);
    final cancellation = _reportCancellation = RequestCancellation();
    final bool? submitted;
    try {
      submitted = await showAppDialog<bool>(
        context: context,
        builder: (_) =>
            ProfileReportDialog(profile: profile, cancellation: cancellation),
      );
    } finally {
      _reportCancellation = null;
      cancellation.cancel();
    }
    if (!mounted || submitted != true) return;
    final current = ref.read(profileRepositoryProvider);
    if (account == (current.accountScope, current.sessionEpoch)) {
      showAppNotice(context, '举报已提交');
    }
  }

  Future<void> _block() async {
    if (!ref.read(authControllerProvider).isSignedIn) {
      widget.onLogin?.call();
      return;
    }
    final provider = profileActionsControllerProvider(widget.id);
    final actions = ref.read(provider);
    if (actions.busy) return;
    if (actions.blocked == null) {
      await ref.read(provider.notifier).refresh();
      return;
    }
    final currentBlocked = actions.blocked;
    if (currentBlocked == null) return;
    final blocked = !currentBlocked;
    final id = widget.id;
    final repository = ref.read(profileRepositoryProvider);
    final account = (repository.accountScope, repository.sessionEpoch);
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(blocked ? '加入黑名单' : '移出黑名单'),
        content: Text(blocked ? '确定将该用户加入黑名单？' : '确定将该用户移出黑名单？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    // The confirmation belongs to the account and profile visible when opened.
    final currentRepository = ref.read(profileRepositoryProvider);
    if (widget.id != id ||
        !identical(currentRepository, repository) ||
        (currentRepository.accountScope, currentRepository.sessionEpoch) !=
            account ||
        !identical(ref.read(provider), actions)) {
      return;
    }
    await ref.read(provider.notifier).setBlocked(blocked);
  }

  @override
  void dispose() {
    _reportCancellation?.cancel();
    _pagingProgress.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(() {
      if (mounted) {
        ref
            .read(profileControllerProvider(widget.id).notifier)
            .select(widget.initialSection);
      }
    });
  }

  @override
  void didUpdateWidget(ProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.id != widget.id) {
      Future<void>.microtask(() {
        if (mounted) {
          ref
              .read(profileControllerProvider(widget.id).notifier)
              .select(widget.initialSection);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final navigation = PlaybackNavigation.maybeOf(context);
    final actionsProvider = profileActionsControllerProvider(widget.id);
    final (
      generation,
      p,
      profileMessage,
      details,
      detailsMessage,
      liveRoom,
      liveRoomMessage,
      section,
    ) = ref.watch(
      profileControllerProvider(widget.id).select(
        (state) => (
          state.sessionGeneration,
          state.profile,
          state.profileMessage,
          state.details,
          state.detailsMessage,
          state.liveRoom,
          state.liveRoomMessage,
          state.section,
        ),
      ),
    );
    final controller = ref.read(profileControllerProvider(widget.id).notifier);
    final (accountMid, signedIn) = ref.watch(
      authControllerProvider.select((state) => (state.mid, state.isSignedIn)),
    );
    final isSelf = widget.isSelf || accountMid == widget.id.value;
    final actions = isSelf || !signedIn
        ? const ProfileActionsState()
        : ref.watch(actionsProvider);
    if (!isSelf && signedIn) {
      ref.listen(actionsProvider, (before, next) {
        if (next.message case final message? when message != before?.message) {
          showAppNotice(context, message);
        }
      });
    }
    final session = (widget.id, generation);
    // Wait for the header before laying out tabs and content. Otherwise they
    // briefly appear at the top and jump down when the profile arrives.
    if (p == null && profileMessage == null) {
      return Stack(
        children: [
          _ProfileInitialLoading(key: ValueKey(session)),
          if (navigation != null)
            Positioned(
              top: 24,
              left: 24,
              child: IconButton.filledTonal(
                key: const ValueKey('profile-back'),
                tooltip: '返回',
                onPressed: navigation.onBack,
                icon: const Icon(Icons.arrow_back),
              ),
            ),
        ],
      );
    }
    final (folderOpen, collectionOpen) = ref.watch(
      profileControllerProvider(widget.id).select(
        (state) => (
          state.section == ProfileSection.folders && state.folderId != null,
          state.section == ProfileSection.collections &&
              state.collection != null,
        ),
      ),
    );
    return PageBackHandler(
      enabled: folderOpen || collectionOpen,
      onBack: () {
        if (folderOpen) {
          controller.closeFolder();
        } else {
          controller.closeCollection();
        }
        return true;
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1920),
          child: ScrollHeaderLayout(
            key: ValueKey(session),
            enabled: true,
            header: KeyedSubtree(
              key: const ValueKey('profile-collapsing-header'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p == null && navigation != null)
                      IconButton.filledTonal(
                        key: const ValueKey('profile-back'),
                        tooltip: '返回',
                        onPressed: navigation.onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                    if (p != null)
                      ProfileHeader(
                        profile: p,
                        onBack: navigation?.onBack,
                        blocked: signedIn ? actions.blocked : false,
                        blockBusy: actions.busy,
                        onBlock: _block,
                        onReport: () => _report(p),
                        details: details,
                        onOpenAvatar: switch (p.avatarUrl) {
                          final url? => () => showImageViewer(context, [
                            url,
                          ], 0),
                          _ => null,
                        },
                        onOpenBanner: switch (details?.bannerUrl ??
                            p.bannerUrl) {
                          final url? => () => showImageViewer(context, [
                            url,
                          ], 0),
                          _ => null,
                        },
                        onShowDetails: () => showProfileDetails(
                          context,
                          profile: p,
                          details: details,
                          detailsMessage: detailsMessage,
                        ),
                        onCopyUid: () => _copy(widget.id.value, '已复制 UID'),
                        onCopyLink: () => _copy(
                          Uri.https(
                            'space.bilibili.com',
                            '/${widget.id.value}',
                          ).toString(),
                          '已复制主页链接',
                        ),
                        onOpenWebsite: _openWebsite,
                        onRefresh: controller.refresh,
                        isSelf: isSelf,
                        followAction: isSelf
                            ? null
                            : UserFollowButton(
                                key: const ValueKey('profile-follow'),
                                id: widget.id,
                                onLogin: widget.onLogin,
                              ),
                        messageAction: isSelf
                            ? null
                            : OutlinedButton.icon(
                                key: const ValueKey('profile-message'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(80, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                onPressed: signedIn
                                    ? widget.onMessage == null
                                          ? null
                                          : () => widget.onMessage?.call(p)
                                    : widget.onLogin,
                                icon: const Icon(Icons.mail_outline, size: 18),
                                label: const Text('私信'),
                              ),
                        onSelectSection: controller.select,
                        liveRoom: liveRoom,
                        onOpenLiveRoom: switch ((
                          liveRoom,
                          widget.onOpenLiveRoom,
                        )) {
                          (final room?, final open?) => () => open(room.id),
                          _ => null,
                        },
                      ),
                    if (profileMessage case final message?)
                      StateView.error(
                        message: message,
                        onAction: controller.loadProfile,
                      ),
                    if (liveRoomMessage case final message?)
                      StateView.error(
                        message: '直播间：$message',
                        onAction: controller.loadLiveRoom,
                      ),
                    if (detailsMessage != null)
                      TextButton.icon(
                        key: const ValueKey('profile-details-retry'),
                        onPressed: controller.loadDetails,
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('扩展资料加载失败，点击重试'),
                      ),
                  ],
                ),
              ),
            ),
            pinnedHeader: Material(
              color: Theme.of(context).colorScheme.surface,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ProfileSectionNavigation(
                      section: section,
                      progress: _pagingProgress,
                      onSelected: controller.select,
                    ),
                    ProfileFollowGroupsTabs(
                      id: widget.id,
                      active: section == ProfileSection.following,
                    ),
                  ],
                ),
              ),
            ),
            child: RetainedTabView<ProfileSection>(
              progress: _pagingProgress,
              tabs: ProfileSection.values,
              value: section,
              onChanged: controller.select,
              viewKey: const ValueKey('profile-section-swipe'),
              pageBuilder: (context, section, active) => _ProfileSectionPage(
                id: widget.id,
                section: section,
                active: active,
                onOpenVideo: widget.onOpenVideo,
                onOpenUser: widget.onOpenUser,
                onOpenPlaylist: widget.onOpenPlaylist,
                onOpenLiveRoom: widget.onOpenLiveRoom,
                onOpenSeason: widget.onOpenSeason,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Each retained list observes its own query and paging state. Header reads and
/// updates to another section do not replace this page's scroll/content tree.
class _ProfileSectionPage extends ConsumerStatefulWidget {
  const _ProfileSectionPage({
    required this.id,
    required this.section,
    required this.active,
    this.onOpenVideo,
    this.onOpenUser,
    this.onOpenPlaylist,
    this.onOpenLiveRoom,
    this.onOpenSeason,
  });

  final UserId id;
  final ProfileSection section;
  final bool active;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<UserId>? onOpenUser;
  final void Function(VideoSummary, String queueId)? onOpenPlaylist;
  final ValueChanged<RoomId>? onOpenLiveRoom;
  final ValueChanged<String>? onOpenSeason;

  @override
  ConsumerState<_ProfileSectionPage> createState() =>
      _ProfileSectionPageState();
}

class _ProfileSectionPageState extends ConsumerState<_ProfileSectionPage> {
  final _followingDialogs = FollowingDialogLifetime();

  @override
  void dispose() {
    _followingDialogs.dispose();
    super.dispose();
  }

  void _manageUser(ProfileEntry entry) {
    manageProfileUser(
      context: context,
      ref: ref,
      owner: widget.id,
      entry: entry,
      lifetime: _followingDialogs,
    );
  }

  void _openFavoriteVideo(VideoSummary video) {
    _playFavorites(initial: video.id);
  }

  Future<void> _playFavorites({VideoId? initial}) async {
    if (!widget.active || !WorkspaceActivity.isActive(context)) return;
    final provider = profileControllerProvider(widget.id);
    final before = ref.read(provider);
    final queue = await ref
        .read(provider.notifier)
        .captureFavoriteQueue(initial: initial);
    if (!mounted || !widget.active || !WorkspaceActivity.isActive(context)) {
      return;
    }
    final after = ref.read(provider);
    if (before.sessionGeneration != after.sessionGeneration ||
        before.folderId != after.folderId) {
      return;
    }
    if (queue == null) {
      if (after.queueMessage case final message?) {
        showAppNotice(context, message);
      }
      return;
    }
    final index = initial == null ? 0 : queue.indexOf(initial);
    if (index < 0) {
      showAppNotice(context, '该视频不在当前收藏夹播放列表内，请刷新后重试');
      return;
    }
    widget.onOpenPlaylist?.call(queue.items[index].video, queue.id);
  }

  void _openLink(Uri uri) {
    final room = dynamicLiveRoom(uri);
    if (room != null && widget.onOpenLiveRoom != null) {
      widget.onOpenLiveRoom!(room);
      return;
    }
    ref.read(externalLinkOpenerProvider)(uri);
  }

  Future<void> _playAll() async {
    final queue = await ref
        .read(profileControllerProvider(widget.id).notifier)
        .playAll();
    if (!mounted ||
        !widget.active ||
        !WorkspaceActivity.isActive(context) ||
        queue == null) {
      return;
    }
    final repository = ref.read(profileRepositoryProvider);
    if (repository.accountScope != queue.scope ||
        repository.sessionEpoch != queue.sessionEpoch) {
      return;
    }
    widget.onOpenPlaylist?.call(queue.items.first.video, queue.id);
  }

  @override
  Widget build(BuildContext context) {
    final (
      generation,
      list,
      order,
      keyword,
      folderId,
      folderTitle,
      collection,
      collectionTitle,
      followingGroupId,
      followingQuery,
    ) = ref.watch(
      profileControllerProvider(widget.id).select(
        (state) => (
          state.sessionGeneration,
          state.lists[widget.section] ?? const ProfileListState(),
          widget.section == ProfileSection.videos ? state.order : '',
          widget.section == ProfileSection.videos ? state.keyword : '',
          widget.section == ProfileSection.folders ? state.folderId : null,
          widget.section == ProfileSection.folders ? state.folderTitle : null,
          widget.section == ProfileSection.collections
              ? state.collection
              : null,
          widget.section == ProfileSection.collections
              ? state.collectionTitle
              : null,
          widget.section == ProfileSection.following
              ? state.followingGroupId
              : null,
          widget.section == ProfileSection.following
              ? (
                  state.followingKeyword,
                  state.followingOrder,
                  state.showBlacklist,
                  state.followingManagementAvailable,
                )
              : ('', '', false, false),
        ),
      ),
    );
    final controller = ref.read(profileControllerProvider(widget.id).notifier);
    final session = (widget.id, generation);
    final listKey = (
      session,
      widget.section,
      widget.section == ProfileSection.folders ? folderId : null,
      collection,
      followingGroupId,
      followingQuery,
    );
    return PagedScrollViewport(
      key: ValueKey(listKey),
      active: widget.active,
      canLoadMore:
          list.page > 0 &&
          list.hasMore &&
          !list.loading &&
          !list.isHidden &&
          list.message == null,
      contentVersion: list,
      onLoadMore: () async {
        final current = ref.read(profileControllerProvider(widget.id));
        // A deferred layout check must still target the selected list/query.
        if (current.sessionGeneration == generation &&
            current.section == widget.section &&
            (widget.section != ProfileSection.folders ||
                current.folderId == folderId) &&
            (widget.section != ProfileSection.collections ||
                current.collection == collection) &&
            (widget.section != ProfileSection.following ||
                (current.followingGroupId == followingGroupId &&
                    (
                          current.followingKeyword,
                          current.followingOrder,
                          current.showBlacklist,
                          current.followingManagementAvailable,
                        ) ==
                        followingQuery)) &&
            (widget.section != ProfileSection.videos ||
                (current.order == order && current.keyword == keyword)) &&
            current.current.message == null) {
          await controller.load();
        }
      },
      builder: (scrollController) => CustomScrollView(
        key: PageStorageKey(listKey),
        controller: scrollController,
        primary: false,
        slivers: [
          SliverOverlapInjector(
            handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.section == ProfileSection.following &&
                      followingQuery.$4) ...[
                    ProfileFollowingTools(id: widget.id),
                    const SizedBox(height: 12),
                  ],
                  if (widget.section == ProfileSection.videos) ...[
                    Consumer(
                      builder: (context, ref, _) {
                        final (loading, message) = ref.watch(
                          profileControllerProvider(widget.id)
                              .select((s) => (s.queueLoading, s.queueMessage)),
                        );
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ProfileVideoFilters(
                              order: order,
                              keyword: keyword,
                              onOrderChanged: (value) =>
                                  controller.filter(order: value),
                              onSearch: (value) =>
                                  controller.filter(keyword: value),
                              onPlayAll: widget.onOpenPlaylist == null
                                  ? null
                                  : _playAll,
                              playAllLoading: loading,
                            ),
                            if (message != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  message,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.section == ProfileSection.folders &&
                      folderId != null)
                    Row(
                      children: [
                        IconButton(
                          tooltip: '返回收藏夹',
                          onPressed: controller.closeFolder,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            folderTitle ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final loading = ref.watch(
                              profileControllerProvider(widget.id)
                                  .select((s) => s.queueLoading),
                            );
                            return TextButton.icon(
                              key: const ValueKey('profile-favorite-play-all'),
                              onPressed:
                                  loading ||
                                      widget.onOpenPlaylist == null ||
                                      !list.items.any(
                                        (entry) =>
                                            entry.video?.id.isValid == true,
                                      )
                                  ? null
                                  : () => _playFavorites(),
                              icon: loading
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.playlist_play),
                              label: const Text('播放全部'),
                            );
                          },
                        ),
                      ],
                    ),
                  if (widget.section == ProfileSection.collections &&
                      collection != null)
                    Row(
                      children: [
                        IconButton(
                          tooltip: '返回合集',
                          onPressed: controller.closeCollection,
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            collectionTitle ?? '',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  if (list.items.isEmpty && list.loading)
                    const StateView.loading(),
                  if (list.message case final message?)
                    StateView.error(
                      message: message,
                      onAction: () => controller.load(),
                    ),
                  if (list.isHidden)
                    StateView.empty(
                      message: '该用户未公开${profileSectionLabel(widget.section)}列表',
                      icon: Icons.visibility_off_outlined,
                    ),
                  if (list.items.isEmpty &&
                      !list.loading &&
                      !list.isHidden &&
                      list.message == null)
                    StateView.empty(
                      message: followingQuery.$3
                          ? '黑名单为空'
                          : followingQuery.$1.isNotEmpty
                          ? '没有找到匹配的关注用户'
                          : '${profileSectionLabel(widget.section)}暂无公开内容',
                    ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            sliver: ProfileSectionContent(
              section: widget.section,
              folderOpen: folderId != null,
              entries: list.items,
              onOpenVideo: folderId != null && widget.onOpenPlaylist != null
                  ? _openFavoriteVideo
                  : widget.onOpenVideo,
              onOpenUser: widget.onOpenUser,
              onManageUser: followingQuery.$4 ? _manageUser : null,
              onOpenFolder: controller.openFolder,
              onOpenCollection: controller.openCollection,
              onOpenSeason: widget.onOpenSeason,
              onOpenLink: _openLink,
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (list.items.isNotEmpty &&
                      list.message == null &&
                      (list.loading || !list.hasMore))
                    Center(
                      child: list.loading
                          ? const CircularProgressIndicator()
                          : Text(
                              list.items.length >= 500
                                  ? '已显示 500 条，请通过搜索或排序查找更多'
                                  : '已显示全部可见内容',
                            ),
                    ),
                  Align(
                    alignment: Alignment.center,
                    child: TextButton.icon(
                      onPressed: () {
                        controller.refresh();
                      },
                      icon: const Icon(Icons.refresh),
                      label: const Text('刷新'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileInitialLoading extends StatefulWidget {
  const _ProfileInitialLoading({super.key});

  @override
  State<_ProfileInitialLoading> createState() => _ProfileInitialLoadingState();
}

class _ProfileInitialLoadingState extends State<_ProfileInitialLoading> {
  Timer? _timer;
  bool _showIndicator = false;

  @override
  void initState() {
    super.initState();
    // Fast reads should open the space without flashing a loading screen.
    _timer = Timer(const Duration(milliseconds: 300), () {
      setState(() => _showIndicator = true);
    });
  }

  @override
  Widget build(BuildContext context) =>
      _showIndicator ? const StateView.loading() : const SizedBox.expand();

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The search draft lives with the retained video page, including its session.
class _ProfileVideoFilters extends StatefulWidget {
  const _ProfileVideoFilters({
    required this.order,
    required this.keyword,
    required this.onOrderChanged,
    required this.onSearch,
    this.onPlayAll,
    this.playAllLoading = false,
  });

  final String order, keyword;
  final ValueChanged<String> onOrderChanged, onSearch;
  final VoidCallback? onPlayAll;
  final bool playAllLoading;

  @override
  State<_ProfileVideoFilters> createState() => _ProfileVideoFiltersState();
}

class _ProfileVideoFiltersState extends State<_ProfileVideoFilters> {
  late final _keyword = TextEditingController(text: widget.keyword);

  @override
  Widget build(BuildContext context) => ProfileVideoToolbar(
    order: widget.order,
    keywordController: _keyword,
    onOrderChanged: widget.onOrderChanged,
    onSearch: widget.onSearch,
    onPlayAll: widget.onPlayAll,
    playAllLoading: widget.playAllLoading,
  );

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }
}
