import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../live/domain/live_room.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/dynamic_post_interactions.dart';
import '../../../shared/ui/sliver_dynamic_post_list.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/user_follow_button.dart';
import '../../auth/application/auth_controller.dart';
import 'profile_header.dart';
import 'profile_video_card.dart';
import '../application/profile_controller.dart';
import '../domain/profile_repository.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({
    super.key,
    required this.id,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLiveRoom,
    this.onMessage,
    this.onLogin,
    this.isSelf = false,
    this.initialSection = ProfileSection.videos,
  });
  final UserId id;
  final void Function(UserId)? onOpenUser;
  final void Function(VideoSummary)? onOpenVideo;
  final void Function(RoomId)? onOpenLiveRoom;
  final ValueChanged<UserProfile>? onMessage;
  final VoidCallback? onLogin;
  final bool isSelf;
  final ProfileSection initialSection;
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  late final _pagingProgress = TabPagingProgress(
    widget.initialSection.index.toDouble(),
  );

  @override
  void dispose() {
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
    final state = ref.watch(profileControllerProvider(widget.id));
    final controller = ref.read(profileControllerProvider(widget.id).notifier);
    final account = ref.watch(authControllerProvider);
    final session = (widget.id, state.sessionGeneration);
    final p = state.profile;
    final isSelf = widget.isSelf || account.mid == widget.id.value;
    final signedIn = account.isSignedIn;
    // Native pointer scrolling coordinates the header and content together.
    // The application's wheel activity moves only an individual position.
    final scrollBehavior = ScrollConfiguration.of(context)
        .copyWith(overscroll: false);
    return ScrollConfiguration(
      // Only inner lists own desktop scrollbars, with one position per tab.
      behavior: scrollBehavior.copyWith(scrollbars: false),
      child: NestedScrollView(
        key: ValueKey(session),
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (p != null)
                    ProfileHeader(
                      profile: p,
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
                      liveRoom: state.liveRoom,
                      onOpenLiveRoom: switch ((
                        state.liveRoom,
                        widget.onOpenLiveRoom,
                      )) {
                        (final room?, final open?) => () => open(room.id),
                        _ => null,
                      },
                    )
                  else if (state.profileLoading)
                    const LinearProgressIndicator(),
                  if (state.profileMessage case final message?)
                    StateView.error(
                      message: message,
                      onAction: controller.loadProfile,
                    ),
                  if (state.liveRoomMessage case final message?)
                    StateView.error(
                      message: '直播间：$message',
                      onAction: controller.loadLiveRoom,
                    ),
                  const SizedBox(height: 4),
                  ProfileSectionNavigation(
                    section: state.section,
                    progress: _pagingProgress,
                    onSelected: controller.select,
                  ),
                ],
              ),
            ),
          ),
        ],
        body: RetainedTabView<ProfileSection>(
          progress: _pagingProgress,
          tabs: ProfileSection.values,
          value: state.section,
          onChanged: controller.select,
          viewKey: const ValueKey('profile-section-swipe'),
          pageBuilder: (context, section, active) => _sectionPage(
            context,
            state.copy(section: section),
            controller,
            session: session,
            active: active,
            scrollBehavior: scrollBehavior,
          ),
        ),
      ),
    );
  }

  Widget _sectionPage(
    BuildContext context,
    ProfileState state,
    ProfileController controller, {
    required (UserId, int) session,
    required bool active,
    required ScrollBehavior scrollBehavior,
  }) {
    final entries = state.current.items;
    return Column(
      children: [
        Expanded(
          child: _ProfileSectionScrollView(
            active: active,
            scrollBehavior: scrollBehavior,
            key: PageStorageKey((
              session,
              state.section,
              state.section == ProfileSection.folders ? state.folderId : null,
            )),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(16),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (state.section == ProfileSection.videos) ...[
                        _ProfileVideoFilters(
                          order: state.order,
                          keyword: state.keyword,
                          onOrderChanged: (value) =>
                              controller.filter(order: value),
                          onSearch: (value) =>
                              controller.filter(keyword: value),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (state.section == ProfileSection.folders &&
                          state.folderId != null)
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            TextButton.icon(
                              onPressed: controller.closeFolder,
                              icon: const Icon(Icons.arrow_back),
                              label: const Text('返回收藏夹'),
                            ),
                            Text(state.folderTitle ?? ''),
                          ],
                        ),
                      if (state.current.items.isEmpty && state.current.loading)
                        const StateView.loading(),
                      if (state.current.message case final message?)
                        StateView.error(
                          message: message,
                          onAction: () => controller.load(),
                        ),
                      if (state.current.isHidden)
                        StateView.empty(
                          message:
                              '该用户未公开${profileSectionLabel(state.section)}列表',
                          icon: Icons.visibility_off_outlined,
                        ),
                      if (state.current.items.isEmpty &&
                          !state.current.loading &&
                          !state.current.isHidden &&
                          state.current.message == null)
                        StateView.empty(
                          message:
                              '${profileSectionLabel(state.section)}暂无公开内容',
                        ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver:
                    state.section == ProfileSection.dynamics &&
                        entries.every((entry) => entry.dynamicPost != null)
                    ? SliverDynamicPostList(
                        posts: [
                          for (final entry in entries) ?entry.dynamicPost,
                        ],
                        spacing: 12,
                        onOpenUser: widget.onOpenUser,
                        onOpenVideo: widget.onOpenVideo,
                        onOpenLink: (uri) =>
                            ref.read(externalLinkOpenerProvider)(uri),
                      )
                    : SliverLayoutBuilder(
                        builder: (context, constraints) {
                          if (state.section == ProfileSection.folders &&
                              state.folderId != null) {
                            return SliverResponsiveCardGrid(
                              itemCount: entries.length,
                              itemBuilder: (context, index) => _entry(
                                entries[index],
                                controller,
                                sharedVideoCard: true,
                              ),
                            );
                          }
                          final isVideoList =
                              entries.isNotEmpty &&
                              entries.every(
                                (e) =>
                                    e.kind == ProfileEntryKind.video &&
                                    e.video != null,
                              );
                          if (!isVideoList) {
                            return SliverList.builder(
                              itemCount: entries.length,
                              itemBuilder: (context, index) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Align(
                                  alignment: Alignment.topCenter,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth:
                                          state.section ==
                                              ProfileSection.dynamics
                                          ? 780
                                          : double.infinity,
                                    ),
                                    child: _entry(entries[index], controller),
                                  ),
                                ),
                              ),
                            );
                          }
                          final columns = (constraints.crossAxisExtent / 560)
                              .floor()
                              .clamp(1, 3);
                          final cardWidth =
                              (constraints.crossAxisExtent -
                                  (columns - 1) * 24) /
                              columns;
                          return SliverGrid.builder(
                            itemCount: entries.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: ProfileVideoCard.heightFor(
                                    cardWidth,
                                    MediaQuery.textScalerOf(context),
                                  ),
                                  crossAxisSpacing: 24,
                                  mainAxisSpacing: 24,
                                ),
                            itemBuilder: (context, index) =>
                                _video(entries[index].video!),
                          );
                        },
                      ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      if (state.current.items.isNotEmpty &&
                          state.current.message == null)
                        Center(
                          child: state.current.loading
                              ? const CircularProgressIndicator()
                              : state.current.hasMore
                              ? OutlinedButton(
                                  onPressed: () => controller.load(),
                                  child: const Text('加载更多'),
                                )
                              : Text(
                                  state.current.items.length >= 500
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
        ),
      ],
    );
  }

  Widget _entry(
    ProfileEntry entry,
    ProfileController controller, {
    bool sharedVideoCard = false,
  }) {
    final post = entry.dynamicPost;
    if (post != null && entry.kind == ProfileEntryKind.dynamic) {
      return InteractiveDynamicPostCard(
        post: post,
        onOpenUser: widget.onOpenUser,
        onOpenVideo: widget.onOpenVideo,
        onOpenLink: (uri) => ref.read(externalLinkOpenerProvider)(uri),
      );
    }
    final video = entry.video;
    if (video != null && entry.kind == ProfileEntryKind.video) {
      if (sharedVideoCard) {
        return VideoCard(
          video: video,
          onTap: () => widget.onOpenVideo?.call(video),
          onOpenUser: widget.onOpenUser,
        );
      }
      return _video(video);
    }
    if (entry.kind == ProfileEntryKind.video) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.play_disabled),
          title: Text(entry.title),
          subtitle: Text(entry.subtitle.isEmpty ? '该收藏内容不可播放' : entry.subtitle),
        ),
      );
    }
    if (entry.kind == ProfileEntryKind.user) {
      return ListTile(
        leading: NetworkAvatar(url: entry.coverUrl, name: entry.title),
        title: Text(entry.title),
        subtitle: entry.subtitle.isEmpty ? null : Text(entry.subtitle),
        onTap: entry.userId?.isValid == true
            ? () => widget.onOpenUser?.call(entry.userId!)
            : null,
      );
    }
    if (entry.kind == ProfileEntryKind.folder) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.folder_outlined),
          title: Text(entry.title),
          subtitle: Text(entry.count == null ? '视频数量未知' : '${entry.count} 个视频'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => controller.openFolder(entry),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (entry.title.isNotEmpty && entry.title != entry.subtitle)
              Text(entry.title, style: Theme.of(context).textTheme.titleMedium),
            if (entry.publishedAt case final date?)
              Text('${date.year}-${date.month}-${date.day}'),
            if (entry.subtitle.isNotEmpty) Text(entry.subtitle),
            if (entry.imageUrls.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final url in entry.imageUrls.take(9))
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Image.network(
                        url.toString(),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.broken_image_outlined),
                      ),
                    ),
                ],
              ),
            if (video != null)
              TextButton(
                onPressed: () => widget.onOpenVideo?.call(video),
                child: Text('播放 ${video.title}'),
              ),
            TextButton(
              onPressed: () => ref.read(externalLinkOpenerProvider)(
                Uri.https('t.bilibili.com', '/${entry.id}'),
              ),
              child: const Text('查看原动态'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _video(VideoSummary video) => ProfileVideoCard(
    video: video,
    onTap: () => widget.onOpenVideo?.call(video),
  );
}

/// The search draft lives with the retained video page, including its session.
class _ProfileVideoFilters extends StatefulWidget {
  const _ProfileVideoFilters({
    required this.order,
    required this.keyword,
    required this.onOrderChanged,
    required this.onSearch,
  });

  final String order, keyword;
  final ValueChanged<String> onOrderChanged, onSearch;

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
  );

  @override
  void dispose() {
    _keyword.dispose();
    super.dispose();
  }
}

/// Only the selected list participates in shared vertical header scrolling.
class _ProfileSectionScrollView extends StatefulWidget {
  const _ProfileSectionScrollView({
    super.key,
    required this.active,
    required this.scrollBehavior,
    required this.slivers,
  });

  final bool active;
  final ScrollBehavior scrollBehavior;
  final List<Widget> slivers;

  @override
  State<_ProfileSectionScrollView> createState() =>
      _ProfileSectionScrollViewState();
}

class _ProfileSectionScrollViewState extends State<_ProfileSectionScrollView> {
  _ProfileSectionScrollController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller ??= _ProfileSectionScrollController(
      PrimaryScrollController.of(context),
      widget.active,
    );
  }

  @override
  void didUpdateWidget(_ProfileSectionScrollView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller?.setActive(widget.active);
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
    behavior: widget.scrollBehavior,
    child: CustomScrollView(
      controller: _controller,
      primary: false,
      slivers: widget.slivers,
    ),
  );

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }
}

/// Create coordinated positions through Flutter's public controller API while
/// keeping each retained tab's position and scrollbar separate. Hidden tabs
/// detach from the coordinator so vertical drags cannot change their offsets.
class _ProfileSectionScrollController extends ScrollController {
  _ProfileSectionScrollController(this.parent, this._active);

  final ScrollController parent;
  bool _active;

  void setActive(bool active) {
    if (_active == active) return;
    _active = active;
    for (final position in positions) {
      if (active) {
        parent.attach(position);
      } else {
        parent.detach(position);
      }
    }
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) => parent.createScrollPosition(physics, context, oldPosition);

  @override
  void attach(ScrollPosition position) {
    super.attach(position);
    if (_active) parent.attach(position);
  }

  @override
  void detach(ScrollPosition position) {
    if (_active) parent.detach(position);
    super.detach(position);
  }
}
