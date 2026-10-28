import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/platform/external_links.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../live/domain/live_room.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/user_follow_button.dart';
import '../../auth/application/auth_controller.dart';
import 'profile_header.dart';
import 'profile_section_content.dart';
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
    final (
      generation,
      p,
      profileMessage,
      liveRoom,
      liveRoomMessage,
      section,
    ) = ref.watch(
      profileControllerProvider(widget.id).select(
        (state) => (
          state.sessionGeneration,
          state.profile,
          state.profileMessage,
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
    final session = (widget.id, generation);
    // Wait for the header before laying out tabs and content. Otherwise they
    // briefly appear at the top and jump down when the profile arrives.
    if (p == null && profileMessage == null) {
      return _ProfileInitialLoading(key: ValueKey(session));
    }
    final isSelf = widget.isSelf || accountMid == widget.id.value;
    final scrollBehavior = ScrollConfiguration.of(context);
    return LayoutBuilder(
      key: ValueKey(session),
      builder: (context, constraints) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Keep the shared header outside all tab lists. Long introductions
          // can scroll within it, leaving room for navigation and content.
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: constraints.maxHeight * .5),
            child: ScrollConfiguration(
              behavior: scrollBehavior.copyWith(scrollbars: false),
              child: SingleChildScrollView(
                key: const ValueKey('profile-header-scroll'),
                primary: false,
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: ProfileSectionNavigation(
              section: section,
              progress: _pagingProgress,
              onSelected: controller.select,
            ),
          ),
          Expanded(
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
              ),
            ),
          ),
        ],
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
  });

  final UserId id;
  final ProfileSection section;
  final bool active;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<UserId>? onOpenUser;

  @override
  ConsumerState<_ProfileSectionPage> createState() =>
      _ProfileSectionPageState();
}

class _ProfileSectionPageState extends ConsumerState<_ProfileSectionPage> {
  void _openLink(Uri uri) => ref.read(externalLinkOpenerProvider)(uri);

  @override
  Widget build(BuildContext context) {
    final (generation, list, order, keyword, folderId, folderTitle) = ref.watch(
      profileControllerProvider(widget.id).select(
        (state) => (
          state.sessionGeneration,
          state.lists[widget.section] ?? const ProfileListState(),
          widget.section == ProfileSection.videos ? state.order : '',
          widget.section == ProfileSection.videos ? state.keyword : '',
          widget.section == ProfileSection.folders ? state.folderId : null,
          widget.section == ProfileSection.folders ? state.folderTitle : null,
        ),
      ),
    );
    final controller = ref.read(profileControllerProvider(widget.id).notifier);
    final session = (widget.id, generation);
    final listKey = (
      session,
      widget.section,
      widget.section == ProfileSection.folders ? folderId : null,
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
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.section == ProfileSection.videos) ...[
                    _ProfileVideoFilters(
                      order: order,
                      keyword: keyword,
                      onOrderChanged: (value) =>
                          controller.filter(order: value),
                      onSearch: (value) => controller.filter(keyword: value),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (widget.section == ProfileSection.folders &&
                      folderId != null)
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        TextButton.icon(
                          onPressed: controller.closeFolder,
                          icon: const Icon(Icons.arrow_back),
                          label: const Text('返回收藏夹'),
                        ),
                        Text(folderTitle ?? ''),
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
                      message: '${profileSectionLabel(widget.section)}暂无公开内容',
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
              onOpenVideo: widget.onOpenVideo,
              onOpenUser: widget.onOpenUser,
              onOpenFolder: controller.openFolder,
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
