import 'package:flutter/material.dart';

import '../../../shared/ui/paging_tab_strip.dart';
import '../../../shared/ui/retained_tab_view.dart';

import '../../../shared/ui/bili_badges.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/video_card.dart';
import '../domain/profile_repository.dart';

class ProfileHeader extends StatelessWidget {
  const ProfileHeader({
    super.key,
    required this.profile,
    required this.onSelectSection,
    this.isSelf = false,
    this.liveRoom,
    this.onOpenLiveRoom,
    this.followAction,
    this.messageAction,
  });

  final UserProfile profile;
  final ValueChanged<ProfileSection> onSelectSection;
  final bool isSelf;
  final ProfileLiveRoom? liveRoom;
  final VoidCallback? onOpenLiveRoom;
  final Widget? followAction;
  final Widget? messageAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final actions = <Widget>[
      ?followAction,
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
      ?messageAction,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NetworkAvatar(
              url: profile.avatarUrl,
              name: profile.name,
              radius: 32,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
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
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (profile.level case final level?)
                        BiliLevelBadge(level: level),
                      if (profile.verifyType case final type?)
                        BiliVerifyBadge(type: type),
                      if (profile.vipLabel case final label?
                          when label.isNotEmpty)
                        Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SelectionArea(
                        child: Text(
                          'UID ${profile.id.value}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                      if (isSelf)
                        Text(
                          '我的主页',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  if (profile.verifyDescription case final description?
                      when description.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectionArea(
                        child: Text(
                          description,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                  if (profile.signature.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: SelectionArea(
                        child: Text(
                          profile.signature,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: muted,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (actions.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
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
              ),
          ],
        ),
      ],
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
    final foreground = onTap == null
        ? theme.colorScheme.onSurface
        : theme.colorScheme.primary;
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: compactCount(count),
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              TextSpan(text: ' $label'),
            ],
          ),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: foreground,
            height: 1.35,
          ),
        ),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: onTap,
        child: content,
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
