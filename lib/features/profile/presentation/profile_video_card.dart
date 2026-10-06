import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/bili_icons.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/video_card_cover.dart';

/// Space submissions keep their cover and metadata side by side.
class ProfileVideoCard extends StatefulWidget {
  const ProfileVideoCard({super.key, required this.video, required this.onTap});

  final VideoSummary video;
  final VoidCallback onTap;

  static double heightFor(double width, TextScaler scaler) {
    final coverHeight = math.min(200.0, width * .4) * .6;
    return math.max(
      coverHeight,
      scaler.scale(14) * 2.7 + scaler.scale(12) * 3.6 + 20,
    );
  }

  @override
  State<ProfileVideoCard> createState() => _ProfileVideoCardState();
}

class _ProfileVideoCardState extends State<ProfileVideoCard> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final theme = Theme.of(context);
      final video = widget.video;
      final coverWidth = math.min(200.0, constraints.maxWidth * .4);
      final date = video.publishedAt;
      return Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onTap,
          onHover: (hovered) => setState(() => _hovered = hovered),
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: ProfileVideoCard.heightFor(
              constraints.maxWidth,
              MediaQuery.textScalerOf(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: coverWidth,
                  height: coverWidth * .6,
                  child: VideoCardCover(
                    video: video,
                    hovered: _hovered,
                    borderRadius: 8,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: theme.colorScheme.surfaceContainerHighest,
                          child: video.coverUrl.isEmpty
                              ? const Icon(Icons.play_circle_outline)
                              : AppCoverImage(
                                  url: video.coverUrl,
                                  fit: BoxFit.cover,
                                  excludeFromSemantics: true,
                                  errorBuilder: (_, _, _) =>
                                      const Icon(Icons.broken_image_outlined),
                                ),
                        ),
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.center,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, Color(0x99000000)],
                            ),
                          ),
                        ),
                        Positioned(
                          right: 7,
                          bottom: 5,
                          left: 7,
                          child: Text(
                            durationLabel(video.duration),
                            textAlign: TextAlign.right,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        video.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          height: 1.35,
                        ),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 12,
                        runSpacing: 2,
                        children: [
                          _count(
                            context,
                            BiliIcons.playCount,
                            video.playCount,
                            '观看',
                          ),
                          _count(
                            context,
                            BiliIcons.danmaku,
                            video.danmakuCount,
                            '弹幕',
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        date == null
                            ? '发布时间未知'
                            : '发表于 ${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _count(
    BuildContext context,
    IconData icon,
    int? count,
    String label,
  ) => Semantics(
    label: '$label ${compactCount(count)}',
    excludeSemantics: true,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Text(compactCount(count), style: Theme.of(context).textTheme.bodySmall),
      ],
    ),
  );
}
