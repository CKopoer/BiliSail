import 'package:flutter/material.dart';

import '../../../domain/dynamic_post.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/dynamic_post_interactions.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/season_card.dart';
import '../../../shared/ui/sliver_dynamic_post_list.dart';
import '../domain/profile_repository.dart';
import 'profile_folder_video_grid.dart';
import 'profile_video_card.dart';
import 'profile_user_card.dart';

/// Retain one lazy delegate for unchanged content, independent of scroll offset
/// and paging/header status. Entry snapshots are immutable in the controller.
class ProfileSectionContent extends StatefulWidget {
  const ProfileSectionContent({
    super.key,
    required this.section,
    required this.entries,
    required this.onOpenFolder,
    required this.onOpenLink,
    this.folderOpen = false,
    this.onOpenVideo,
    this.onOpenUser,
    this.onOpenCollection,
    this.onOpenSeason,
    this.onManageUser,
  });

  final ProfileSection section;
  final List<ProfileEntry> entries;
  final bool folderOpen;
  final ValueChanged<ProfileEntry> onOpenFolder;
  final ValueChanged<Uri> onOpenLink;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<ProfileEntry>? onOpenCollection;
  final ValueChanged<String>? onOpenSeason;
  final ValueChanged<ProfileEntry>? onManageUser;

  @override
  State<ProfileSectionContent> createState() => _ProfileSectionContentState();
}

class _ProfileSectionContentState extends State<ProfileSectionContent> {
  Widget? _content, _videoGrid;
  (double, TextScaler)? _videoLayout;
  _ContentKind? _kind;
  List<DynamicPost>? _posts;

  @override
  void didUpdateWidget(ProfileSectionContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final dataChanged =
        !identical(oldWidget.entries, widget.entries) ||
        oldWidget.section != widget.section ||
        oldWidget.folderOpen != widget.folderOpen;
    if (dataChanged) {
      _kind = null;
      _posts = null;
    }
    if (dataChanged ||
        oldWidget.onOpenFolder != widget.onOpenFolder ||
        oldWidget.onOpenLink != widget.onOpenLink ||
        oldWidget.onOpenVideo != widget.onOpenVideo ||
        oldWidget.onOpenUser != widget.onOpenUser ||
        oldWidget.onManageUser != widget.onManageUser ||
        oldWidget.onOpenCollection != widget.onOpenCollection ||
        oldWidget.onOpenSeason != widget.onOpenSeason) {
      _content = null;
      _videoGrid = null;
    }
  }

  @override
  Widget build(BuildContext context) => _content ??= _buildContent();

  _ContentKind _classify() {
    final entries = widget.entries;
    if (widget.section == ProfileSection.folders && widget.folderOpen) {
      return _ContentKind.folderVideos;
    }
    if (widget.section == ProfileSection.dynamics &&
        entries.every((entry) => entry.dynamicPost != null)) {
      return _ContentKind.dynamics;
    }
    return entries.isNotEmpty &&
            entries.every(
              (entry) =>
                  entry.kind == ProfileEntryKind.video && entry.video != null,
            )
        ? _ContentKind.videos
        : _ContentKind.entries;
  }

  Widget _buildContent() {
    if (widget.section == ProfileSection.following ||
        widget.section == ProfileSection.followers) {
      return ProfileUserGrid(
        entries: widget.entries,
        onOpen: widget.onOpenUser,
        onManage: widget.onManageUser,
      );
    }
    final kind = _kind ??= _classify();
    if (kind == _ContentKind.folderVideos) {
      return ProfileFolderVideoGrid(
        entries: widget.entries,
        onOpenVideo: widget.onOpenVideo,
        onOpenUser: widget.onOpenUser,
      );
    }
    if (kind == _ContentKind.dynamics) {
      return SliverDynamicPostList(
        pinnedFirst: true,
        posts: _posts ??= [
          for (final entry in widget.entries) ?entry.dynamicPost,
        ],
        spacing: 12,
        onOpenUser: widget.onOpenUser,
        onOpenVideo: widget.onOpenVideo,
        onOpenLink: widget.onOpenLink,
      );
    }
    if (kind == _ContentKind.entries) {
      if (widget.entries.isNotEmpty &&
          widget.entries.every(
            (entry) => const {
              ProfileEntryKind.folder,
              ProfileEntryKind.collection,
              ProfileEntryKind.season,
            }.contains(entry.kind),
          )) {
        return SliverResponsiveCardGrid(
          itemCount: widget.entries.length,
          itemBuilder: (context, index) =>
              _libraryCard(context, widget.entries[index]),
        );
      }
      return SliverList.builder(
        itemCount: widget.entries.length,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: widget.section == ProfileSection.dynamics
                    ? 780
                    : double.infinity,
              ),
              child: _entry(context, widget.entries[index]),
            ),
          ),
        ),
      );
    }
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final layout = (
          constraints.crossAxisExtent,
          MediaQuery.textScalerOf(context),
        );
        if (_videoLayout == layout && _videoGrid != null) return _videoGrid!;
        _videoLayout = layout;
        final columns = (layout.$1 / 560).floor().clamp(1, 3);
        final cardWidth = (layout.$1 - (columns - 1) * 24) / columns;
        return _videoGrid = SliverGrid.builder(
          itemCount: widget.entries.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: ProfileVideoCard.heightFor(cardWidth, layout.$2),
            crossAxisSpacing: 24,
            mainAxisSpacing: 24,
          ),
          itemBuilder: (context, index) => _video(widget.entries[index].video!),
        );
      },
    );
  }

  Widget _video(VideoSummary video) => ProfileVideoCard(
    video: video,
    onTap: () => widget.onOpenVideo?.call(video),
  );

  Widget _libraryCard(BuildContext context, ProfileEntry entry) {
    if (entry.kind == ProfileEntryKind.season) {
      final seasonId = entry.seasonId;
      return SeasonCard(
        key: ValueKey('profile-library-${entry.kind.name}-${entry.id}'),
        title: entry.title,
        subtitle: entry.subtitle,
        coverUrl: entry.coverUrl,
        label: widget.section == ProfileSection.bangumi ? '追番' : '追剧',
        onTap: seasonId != null && widget.onOpenSeason != null
            ? () => widget.onOpenSeason?.call(seasonId)
            : null,
      );
    }
    final scheme = Theme.of(context).colorScheme;
    final label = switch (entry.kind) {
      ProfileEntryKind.folder => '收藏夹',
      _ => entry.collection?.isSeries == true ? '系列' : '合集',
    };
    final VoidCallback? open = switch (entry.kind) {
      ProfileEntryKind.folder => () => widget.onOpenFolder(entry),
      ProfileEntryKind.collection when widget.onOpenCollection != null =>
        () => widget.onOpenCollection?.call(entry),
      _ => null,
    };
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: ValueKey('profile-library-${entry.kind.name}-${entry.id}'),
        onTap: open,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ColoredBox(
                    color: scheme.surfaceContainerHighest,
                    child: entry.coverUrl == null
                        ? const Icon(Icons.video_library_outlined, size: 36)
                        : AppCoverImage(
                            url: entry.coverUrl.toString(),
                            excludeFromSemantics: true,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                  ),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xB3000000),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        child: Text(
                          label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.count == null ? '视频数量未知' : '${entry.count} 个视频',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _entry(BuildContext context, ProfileEntry entry) {
    final post = entry.dynamicPost;
    if (post != null && entry.kind == ProfileEntryKind.dynamic) {
      return InteractiveDynamicPostCard(
        post: post,
        onOpenUser: widget.onOpenUser,
        onOpenVideo: widget.onOpenVideo,
        onOpenLink: widget.onOpenLink,
      );
    }
    final video = entry.video;
    if (video != null && entry.kind == ProfileEntryKind.video) {
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
          onTap: () => widget.onOpenFolder(entry),
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
              onPressed: () => widget.onOpenLink(
                Uri.https('t.bilibili.com', '/${entry.id}'),
              ),
              child: const Text('查看原动态'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _ContentKind { folderVideos, dynamics, videos, entries }
