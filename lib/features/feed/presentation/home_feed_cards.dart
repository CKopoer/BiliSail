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
