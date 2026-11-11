import 'package:flutter/material.dart';

import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/retained_tab_view.dart';

import '../../../shared/ui/bili_badges.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/video_card.dart';
import '../domain/profile_repository.dart';

class ProfileHeader extends StatefulWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.onSelectSection,
    this.details,
    this.isSelf = false,
    this.liveRoom,
    this.onOpenLiveRoom,
    this.followAction,
    this.messageAction,
    this.onOpenAvatar,
    this.onOpenBanner,
    this.onShowDetails,
    this.onCopyUid,
    this.onCopyLink,
    this.onOpenWebsite,
    this.onRefresh,
    this.onBack,
    this.onBlock,
    this.onReport,
    this.blocked,
    this.blockBusy = false,
  });

  final UserProfile profile;
  final ProfileSpaceDetails? details;
  final ValueChanged<ProfileSection> onSelectSection;
  final bool isSelf;
  final ProfileLiveRoom? liveRoom;
  final VoidCallback? onOpenLiveRoom,
      onOpenAvatar,
      onOpenBanner,
      onShowDetails,
      onCopyUid,
      onCopyLink,
      onOpenWebsite,
      onRefresh,
      onBack,
      onBlock,
      onReport;
  final bool? blocked;
  final bool blockBusy;
  final Widget? followAction, messageAction;

  @override
  State<ProfileHeader> createState() => _ProfileHeaderState();
}

class _ProfileHeaderState extends State<ProfileHeader> {
  bool _signatureExpanded = false;

  @override
  void didUpdateWidget(ProfileHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.id != widget.profile.id) _signatureExpanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile,
        details = widget.details,
        isSelf = widget.isSelf,
        liveRoom = widget.liveRoom,
        followAction = widget.followAction,
        messageAction = widget.messageAction;
    final onSelectSection = widget.onSelectSection,
        onOpenLiveRoom = widget.onOpenLiveRoom,
        onOpenAvatar = widget.onOpenAvatar,
        onOpenBanner = widget.onOpenBanner,
        onShowDetails = widget.onShowDetails,
        onCopyUid = widget.onCopyUid,
        onCopyLink = widget.onCopyLink,
        onOpenWebsite = widget.onOpenWebsite,
        onRefresh = widget.onRefresh;
    final theme = Theme.of(context), scheme = theme.colorScheme;
    final bannerUrl = details?.bannerUrl ?? profile.bannerUrl;
    final actions = Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ?followAction,
        ?messageAction,
        if (liveRoom case final room? when room.id.isValid)
          Tooltip(
            message: room.isLive ? '进入正在直播的直播间' : '进入直播间，当前未开播',
            child: OutlinedButton.icon(
              key: const ValueKey('profile-live-room'),
              onPressed: onOpenLiveRoom,
              icon: Icon(
                room.isLive ? Icons.live_tv : Icons.live_tv_outlined,
                size: 18,
              ),
              label: Text(room.isLive ? '正在直播' : '直播间'),
            ),
          ),
      ],
    );
    final identity = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SelectionArea(
              child: Text(
                profile.name,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (profile.level case final level?) BiliLevelBadge(level: level),
            if (profile.vipLabel case final label?
                when profile.vipStatus == 1 && label.isNotEmpty)
              if (profile.vipLabelImageUrl case final image?)
                Semantics(
                  label: label,
                  child: AppCoverImage(
                    key: const ValueKey('profile-vip-image'),
                    url: image.toString(),
                    width: 88,
                    height: 24,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => Text(label),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    child: Text(
                      label,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            SelectionArea(
              child: Text(
                'UID ${profile.id.value}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            if (isSelf)
              Text(
                '我的主页',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.primary,
                ),
              ),
          ],
        ),
        if (profile.verifyDescription case final description?
            when description.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SelectionArea(
              child: Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        if (profile.signature.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _ProfileBiography(
              text: profile.signature,
              expanded: _signatureExpanded,
              onToggle: () =>
                  setState(() => _signatureExpanded = !_signatureExpanded),
            ),
          ),
      ],
    );
    final statistics = Wrap(
      spacing: 8,
      runSpacing: 4,
      children: [
        _ProfileStatistic(
          key: const ValueKey('profile-following-stat'),
          count: profile.followingCount,
          label: '关注',
          onTap: () => onSelectSection(ProfileSection.following),
        ),
        _ProfileStatistic(
          key: const ValueKey('profile-followers-stat'),
          count: profile.followerCount,
          label: '粉丝',
          onTap: () => onSelectSection(ProfileSection.followers),
        ),
        _ProfileStatistic(
          key: const ValueKey('profile-likes-stat'),
          count: profile.likeCount,
          label: '获赞',
        ),
        if (profile.videoCount case final count?)
          _ProfileStatistic(
            key: const ValueKey('profile-videos-stat'),
            count: count,
            label: '投稿',
            onTap: () => onSelectSection(ProfileSection.videos),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 840 &&
            MediaQuery.textScalerOf(context).scale(14) < 21;
        return Material(
          key: ValueKey(wide ? 'profile-header-wide' : 'profile-header-narrow'),
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: wide ? 138 : 142,
                child: Stack(
                  children: [
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      height: 108,
                      child: Material(
                        color: scheme.secondaryContainer,
                        child: InkWell(
                          key: const ValueKey('profile-banner'),
                          onTap: bannerUrl == null ? null : onOpenBanner,
                          child: Ink(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  scheme.primaryContainer,
                                  scheme.secondaryContainer,
                                  scheme.tertiaryContainer,
                                ],
                              ),
                            ),
                            child: switch (bannerUrl) {
                              final url? => AppCoverImage(
                                url: url.toString(),
                                excludeFromSemantics: true,
                                errorBuilder: (_, _, _) =>
                                    const SizedBox.expand(),
                              ),
                              _ => const SizedBox.expand(),
                            },
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 20,
                      bottom: 0,
                      child: Tooltip(
                        message: '查看头像',
                        child: Material(
                          type: MaterialType.transparency,
                          shape: const CircleBorder(),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: InkWell(
                              key: const ValueKey('profile-avatar'),
                              customBorder: const CircleBorder(),
                              onTap: onOpenAvatar,
                              child: SizedBox.square(
                                dimension: 88,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    NetworkAvatar(
                                      url: profile.avatarUrl,
                                      pendantUrl: profile.pendantUrl,
                                      name: profile.name,
                                      radius: profile.pendantUrl == null
                                          ? 32
                                          : 35,
                                    ),
                                    if (profile.verifyType case final type?
                                        when type == 0 || type == 1)
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: BiliVerifyBadge(
                                          type: type,
                                          size: 20,
                                        ),
                                      )
                                    else if (profile.vipStatus == 1)
                                      Positioned(
                                        right: 4,
                                        bottom: 4,
                                        child: Semantics(
                                          label: '大会员',
                                          child: Icon(
                                            Icons.workspace_premium,
                                            size: 22,
                                            color: scheme.primary,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (widget.onBack != null)
                      Positioned(
                        left: 8,
                        top: 8,
                        child: IconButton(
                          key: const ValueKey('profile-back'),
                          tooltip: '返回',
                          onPressed: widget.onBack,
                          icon: const Icon(Icons.arrow_back),
                        ),
                      ),
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            key: const ValueKey('profile-details'),
                            tooltip: '用户资料',
                            onPressed: onShowDetails,
                            icon: const Icon(Icons.info_outline, size: 20),
                          ),
                          PopupMenuButton<String>(
                            key: const ValueKey('profile-more'),
                            tooltip: '主页更多操作',
                            onSelected: (value) => switch (value) {
                              'uid' => onCopyUid?.call(),
                              'link' => onCopyLink?.call(),
                              'web' => onOpenWebsite?.call(),
                              'refresh' => onRefresh?.call(),
                              'block' => widget.onBlock?.call(),
                              'report' => widget.onReport?.call(),
                              _ => null,
                            },
                            itemBuilder: (_) => [
                              if (!isSelf) ...[
                                PopupMenuItem(
                                  value: 'block',
                                  enabled:
                                      widget.onBlock != null &&
                                      !widget.blockBusy,
                                  child: Text(
                                    widget.blockBusy
                                        ? '正在读取黑名单状态…'
                                        : widget.blocked == true
                                        ? '移出黑名单'
                                        : widget.blocked == false
                                        ? '加入黑名单'
                                        : '刷新黑名单状态',
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'report',
                                  enabled: widget.onReport != null,
                                  child: const Text('举报'),
                                ),
                                const PopupMenuDivider(),
                              ],
                              PopupMenuItem(
                                value: 'uid',
                                enabled: onCopyUid != null,
                                child: const Text('复制 UID'),
                              ),
                              PopupMenuItem(
                                value: 'link',
                                enabled: onCopyLink != null,
                                child: const Text('复制主页链接'),
                              ),
                              PopupMenuItem(
                                value: 'web',
                                enabled: onOpenWebsite != null,
                                child: const Text('在浏览器打开'),
                              ),
                              PopupMenuItem(
                                value: 'refresh',
                                enabled: onRefresh != null,
                                child: const Text('刷新主页'),
                              ),
                            ],
                            icon: const Icon(Icons.more_horiz),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: identity),
                          const SizedBox(width: 24),
                          SizedBox(
                            width: 360,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                statistics,
                                const SizedBox(height: 8),
                                actions,
                              ],
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (followAction != null ||
                              messageAction != null ||
                              liveRoom?.id.isValid == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: actions,
                            ),
                          identity,
                          const SizedBox(height: 8),
                          statistics,
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProfileBiography extends StatelessWidget {
  const _ProfileBiography({
    required this.text,
    required this.expanded,
    required this.onToggle,
  });
  final String text;
  final bool expanded;
  final VoidCallback onToggle;
  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
      height: 1.4,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 2,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = painter.didExceedMaxLines;
        painter.dispose();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionArea(
              child: Text(
                text,
                style: style,
                maxLines: expanded ? null : 2,
                overflow: expanded ? null : TextOverflow.ellipsis,
              ),
            ),
            if (overflow)
              TextButton(
                key: const ValueKey('profile-signature-toggle'),
                onPressed: onToggle,
                child: Text(expanded ? '收起简介' : '展开简介'),
              ),
          ],
        );
      },
    );
  }
}

class _ProfileStatistic extends StatelessWidget {
  const _ProfileStatistic({
    super.key,
    required this.count,
    required this.label,
    this.onTap,
  });
  final int? count;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '$label：${count ?? '未知'}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 60, minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    compactCount(count),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    label,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ProfileSectionNavigation extends StatelessWidget {
  const ProfileSectionNavigation({
    super.key,
    required this.section,
    required this.onSelected,
    this.progress,
  });

  final ProfileSection section;
  final ValueChanged<ProfileSection> onSelected;
  final TabPagingProgress? progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: PagingTabStrip<ProfileSection>(
          tabs: ProfileSection.values,
          value: section,
          progress: progress,
          onSelected: onSelected,
          spacing: 0,
          fullWidthIndicator: true,
          indicatorHeight: 3,
          unselectedColor: theme.colorScheme.onSurfaceVariant,
          itemKey: (entry) => ValueKey('profile-tab-${entry.name}'),
          labelBuilder: (context, entry) => Text(profileSectionLabel(entry)),
          buttonStyle: TextButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            textStyle: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

String profileSectionLabel(ProfileSection section) => switch (section) {
  ProfileSection.videos => '投稿',
  ProfileSection.dynamics => '动态',
  ProfileSection.folders => '收藏夹',
  ProfileSection.collections => '合集',
  ProfileSection.bangumi => '追番',
  ProfileSection.cinema => '追剧',
  ProfileSection.following => '关注',
  ProfileSection.followers => '粉丝',
};

class ProfileVideoToolbar extends StatefulWidget {
  const ProfileVideoToolbar({
    super.key,
    required this.order,
    required this.keywordController,
    required this.onOrderChanged,
    required this.onSearch,
    this.onPlayAll,
    this.playAllLoading = false,
  });

  final String order;
  final TextEditingController keywordController;
  final ValueChanged<String> onOrderChanged, onSearch;
  final VoidCallback? onPlayAll;
  final bool playAllLoading;

  @override
  State<ProfileVideoToolbar> createState() => _ProfileVideoToolbarState();
}

class _ProfileVideoToolbarState extends State<ProfileVideoToolbar> {
  late bool _searchExpanded = widget.keywordController.text.isNotEmpty;
  final _searchFocus = FocusNode();

  @override
  void dispose() {
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final order = widget.order;
    final keywordController = widget.keywordController;
    final onOrderChanged = widget.onOrderChanged;
    final onSearch = widget.onSearch;
    final playAllLoading = widget.playAllLoading;
    final onPlayAll = widget.onPlayAll;
    final playAll = Semantics(
      liveRegion: playAllLoading,
      value: playAllLoading ? '正在加载播放列表' : null,
      child: TextButton.icon(
        key: const ValueKey('profile-play-all'),
        onPressed: playAllLoading ? null : onPlayAll,
        icon: playAllLoading
            ? const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.playlist_play, size: 18),
        label: const Text('播放全部'),
      ),
    );
    final sort = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          key: const ValueKey('profile-video-sort'),
          value: order,
          isDense: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          borderRadius: BorderRadius.circular(8),
          style: theme.textTheme.bodyMedium,
          icon: const Icon(Icons.expand_more, size: 18),
          items: const [
            DropdownMenuItem(value: 'pubdate', child: Text('最新发布')),
            DropdownMenuItem(value: 'click', child: Text('最多播放')),
            DropdownMenuItem(value: 'stow', child: Text('最多收藏')),
          ],
          onChanged: (value) {
            if (value != null) onOrderChanged(value);
          },
        ),
      ),
    );
    final search = TextField(
      key: const ValueKey('profile-video-search'),
      controller: keywordController,
      focusNode: _searchFocus,
      textInputAction: TextInputAction.search,
      style: theme.textTheme.bodyMedium,
      decoration: InputDecoration(
        hintText: '搜索投稿',
        filled: true,
        fillColor: theme.colorScheme.surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        prefixIcon: const Icon(Icons.search, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        suffixIcon: IconButton(
          tooltip: '搜索投稿',
          onPressed: () => onSearch(keywordController.text),
          icon: const Icon(Icons.search, size: 20),
        ),
      ),
      onSubmitted: onSearch,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 600) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OverflowBar(
                alignment: MainAxisAlignment.spaceBetween,
                overflowAlignment: OverflowBarAlignment.end,
                spacing: 12,
                overflowSpacing: 8,
                children: [
                  sort,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        key: const ValueKey('profile-search-toggle'),
                        tooltip: _searchExpanded ? '收起搜索' : '展开搜索',
                        isSelected: _searchExpanded,
                        onPressed: () {
                          setState(() => _searchExpanded = !_searchExpanded);
                          if (_searchExpanded) {
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && _searchExpanded) {
                                _searchFocus.requestFocus();
                              }
                            });
                          } else {
                            _searchFocus.unfocus();
                          }
                        },
                        icon: Icon(
                          _searchExpanded ? Icons.close : Icons.search,
                        ),
                      ),
                      playAll,
                    ],
                  ),
                ],
              ),
              if (_searchExpanded) ...[const SizedBox(height: 8), search],
            ],
          );
        }
        return Row(
          children: [
            sort,
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 260),
                  child: search,
                ),
              ),
            ),
            const SizedBox(width: 12),
            playAll,
          ],
        );
      },
    );
  }
}
