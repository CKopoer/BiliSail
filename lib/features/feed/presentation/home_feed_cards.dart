import '../../../domain/user.dart';

import 'package:flutter/material.dart';

import '../../../shared/ui/video_card.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../domain/home_repository.dart';

final class VideoDynamicCard extends StatelessWidget {
  const VideoDynamicCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onOpenUser,
  });
  final ValueChanged<UserId>? onOpenUser;
  final HomeEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) =>
      HomeVideoCard(entry: entry, onTap: onTap, onOpenUser: onOpenUser);
}

/// Home videos share the same visual contract as feed/search/history videos.
final class HomeVideoCard extends StatelessWidget {
  const HomeVideoCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onOpenUser,
    this.menu,
    this.showWatchLaterButton = true,
  });
  final HomeEntry entry;
  final VoidCallback onTap;
  final ValueChanged<UserId>? onOpenUser;
  final VideoCardMenu? menu;
  final bool showWatchLaterButton;

  @override
  Widget build(BuildContext context) => VideoCard(
    video:
        entry.dynamicPost?.video ??
        VideoSummary(
          id: VideoId(entry.bvid ?? entry.id),
          previewCid: entry.previewCid,
          title: entry.title,
          coverUrl: entry.coverUrl?.toString() ?? '',
          author: entry.authorName,
          authorId: UserId.tryParse(entry.authorMid),
          duration: entry.duration ?? Duration.zero,
          publishedAt: entry.publishedAt,
        ),
    playCountText: entry.playCountText,
    danmakuCountText: entry.danmakuCountText,
    publishText: entry.publishText,
    onOpenUser: onOpenUser,
    onTap: onTap,
    menu: menu,
    showWatchLaterButton: showWatchLaterButton,
  );
}

final class FavoriteFolderCard extends StatelessWidget {
  const FavoriteFolderCard({
    super.key,
    required this.entry,
    required this.onTap,
    this.onUnsubscribe,
    this.unsubscribing = false,
    this.showCreatedMetadata = false,
    this.onEdit,
  });
  final HomeEntry entry;
  final VoidCallback onTap;
  final VoidCallback? onUnsubscribe;
  final bool unsubscribing;
  final bool showCreatedMetadata;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 28,
                  right: 28,
                  height: 22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .10),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 16,
                  right: 16,
                  height: 22,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: .18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: _Cover(
                        url: entry.coverUrl,
                        left: [
                          if (entry.contentCount != null)
                            '${entry.contentCount}个内容',
                          if (showCreatedMetadata)
                            if (entry.isPrivate == true)
                              '私密'
                            else if (entry.isPrivate == false)
                              '公开',
                        ].join(' '),
                        right: showCreatedMetadata
                            ? ''
                            : entry.kind == HomeEntryKind.collection
                            ? '合集'
                            : '收藏夹',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showCreatedMetadata && entry.isPrivate == true) ...[
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: Tooltip(
                      message: '私密收藏夹',
                      child: Icon(Icons.lock, size: 16),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
                Expanded(
                  child: Text(
                    entry.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                if (onUnsubscribe != null || onEdit != null)
                  PopupMenuButton<String>(
                    tooltip: unsubscribing ? '取消订阅中' : '更多操作',
                    enabled: !unsubscribing,
                    padding: EdgeInsets.zero,
                    iconSize: 20,
                    iconColor: scheme.onSurfaceVariant,
                    style: IconButton.styleFrom(
                      fixedSize: const Size(32, 28),
                      minimumSize: const Size(32, 28),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 140,
                      maxWidth: 240,
                    ),
                    position: PopupMenuPosition.under,
                    color: scheme.surface,
                    surfaceTintColor: Colors.transparent,
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: .6),
                      ),
                    ),
                    icon: unsubscribing
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.more_vert),
                    onSelected: (action) {
                      if (action == 'edit') onEdit?.call();
                      if (action == 'unsubscribe') onUnsubscribe?.call();
                    },
                    itemBuilder: (_) => [
                      if (onEdit != null)
                        PopupMenuItem(
                          value: 'edit',
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '编辑信息',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      if (onUnsubscribe != null)
                        PopupMenuItem(
                          value: 'unsubscribe',
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Text(
                            '取消订阅',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            if (showCreatedMetadata) ...[
              const SizedBox(height: 12),
              Text(
                switch (entry.createdAt) {
                  final date? => '创建于${_date(date.toLocal())}',
                  null => '创建时间未知',
                },
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ] else if (entry.viewCount != null) ...[
              const SizedBox(height: 12),
              Text(
                '${compactCount(entry.viewCount)}播放',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _date(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

final class LiveRoomCard extends StatelessWidget {
  const LiveRoomCard({super.key, required this.entry, required this.onTap});
  final HomeEntry entry;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: _Cover(
                url: entry.coverUrl,
                left: entry.popularityText.trim().isEmpty
                    ? ''
                    : '♨ ${compactCountLabel(null, entry.popularityText, abbreviateThousands: true)}',
                right: entry.areaName,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            entry.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            entry.authorName.isEmpty ? entry.subtitle : entry.authorName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    ),
  );
}

final class _Cover extends StatelessWidget {
  const _Cover({this.url, this.left = '', this.right = ''});
  final Uri? url;
  final String left;
  final String right;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: url == null
            ? const Center(child: Icon(Icons.image_outlined))
            : AppCoverImage(
                url: url.toString(),
                frameBuilder: (_, child, frame, _) => frame != null
                    ? child
                    : const Center(child: Icon(Icons.image_outlined)),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Center(child: Icon(Icons.image_outlined)),
              ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black54],
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
              if (right.isNotEmpty)
                Expanded(
                  child: Text(
                    right,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
      ),
    ],
  );
}
