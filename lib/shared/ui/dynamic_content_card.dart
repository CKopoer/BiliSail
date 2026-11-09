import 'package:flutter/material.dart';

import '../../core/presentation/public_image_variant.dart';
import '../../domain/dynamic_post.dart';
import 'app_network_image.dart';

/// One renderer for major and additional cards, including forwarded content.
class DynamicContentCardView extends StatelessWidget {
  const DynamicContentCardView({
    super.key,
    required this.card,
    this.onOpenLink,
    this.layoutOnly = false,
  });
  final DynamicContentCard card;
  final ValueChanged<Uri>? onOpenLink;
  final bool layoutOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (icon, label) = switch (card.kind) {
      DynamicCardKind.article => (Icons.article_outlined, '专栏'),
      DynamicCardKind.pgc => (Icons.movie_outlined, '影视'),
      DynamicCardKind.course => (Icons.school_outlined, '课程'),
      DynamicCardKind.season => (Icons.video_library_outlined, '合集'),
      DynamicCardKind.music => (Icons.music_note_outlined, '音乐'),
      DynamicCardKind.medialist => (Icons.playlist_play, '收藏列表'),
      DynamicCardKind.live => (Icons.live_tv, '直播'),
      DynamicCardKind.ugc => (Icons.play_circle_outline, '相关视频'),
      DynamicCardKind.goods => (Icons.shopping_bag_outlined, '商品'),
      DynamicCardKind.reservation => (Icons.event_outlined, '预约'),
      DynamicCardKind.vote => (Icons.poll_outlined, '投票'),
      DynamicCardKind.lottery => (Icons.redeem_outlined, '抽奖'),
      DynamicCardKind.match => (Icons.sports_esports_outlined, '赛事'),
      DynamicCardKind.common => (Icons.link, '相关内容'),
      DynamicCardKind.unknown => (Icons.open_in_new, '更多内容'),
    };
    final panoramic = {
      DynamicCardKind.pgc,
      DynamicCardKind.course,
      DynamicCardKind.season,
      DynamicCardKind.live,
      DynamicCardKind.ugc,
    }.contains(card.kind);
    Widget image({double? size}) => SizedBox(
      width: size,
      height: size,
      child: layoutOnly
          ? const SizedBox.expand()
          : AppNetworkImage(
              url: publicImageThumbnail(
                card.coverUrl!,
                width: panoramic ? 960 : 256,
              ).toString(),
              cacheWidth: panoramic ? 960 : 256,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) =>
                  Center(child: Icon(icon, color: scheme.outline)),
            ),
    );
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: card.url == null || onOpenLink == null
            ? null
            : () => onOpenLink!(card.url!),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (panoramic && card.coverUrl != null)
              AspectRatio(aspectRatio: 16 / 9, child: image()),
            Padding(
              padding: const EdgeInsets.all(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final stacked =
                      constraints.maxWidth < 280 ||
                      MediaQuery.textScalerOf(context).scale(14) > 22;
                  final text = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(icon, size: 16, color: scheme.primary),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              card.badge.isEmpty ? label : card.badge,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        card.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (card.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          card.description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: card.kind == DynamicCardKind.goods
                              ? theme.textTheme.titleSmall?.copyWith(
                                  color: scheme.primary,
                                )
                              : theme.textTheme.bodySmall,
                        ),
                      ],
                      if (card.detail.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          card.detail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ],
                  );
                  final content = Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!panoramic && card.coverUrl != null) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: image(size: stacked ? 48 : 64),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(child: text),
                    ],
                  );
                  final action = card.actionLabel.isEmpty
                      ? null
                      : OutlinedButton(
                          onPressed:
                              card.actionUrl == null || onOpenLink == null
                              ? null
                              : () => onOpenLink!(card.actionUrl!),
                          child: Text(
                            card.actionLabel,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                  if (action == null) return content;
                  if (stacked) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        content,
                        const SizedBox(height: 8),
                        Align(alignment: Alignment.centerRight, child: action),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: content),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 120),
                        child: action,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
