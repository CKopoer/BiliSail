import '../../../domain/user.dart';

import 'package:flutter/material.dart';

import '../../../shared/ui/video_card.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_network_image.dart';
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
  });
  final HomeEntry entry;
  final VoidCallback onTap;
  final ValueChanged<UserId>? onOpenUser;

  @override
  Widget build(BuildContext context) => VideoCard(
    video:
        entry.dynamicPost?.video ??
        VideoSummary(
          id: VideoId(entry.bvid ?? entry.id),
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
  );
}

final class FavoriteFolderCard extends StatelessWidget {
  const FavoriteFolderCard({
    super.key,
    required this.entry,
    required this.onTap,
  });
  final HomeEntry entry;
  final VoidCallback onTap;

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
                        left: entry.contentCount == null
                            ? ''
                            : '${entry.contentCount}个内容',
                        right: entry.kind == HomeEntryKind.collection
                            ? '合集'
                            : '收藏夹',
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Text(
              entry.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (entry.viewCount != null) ...[
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
                left: entry.popularityText.isEmpty
                    ? ''
                    : '♨ ${entry.popularityText}',
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
            : AppNetworkImage(
                url: url.toString(),
                cacheWidth: 640,
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
