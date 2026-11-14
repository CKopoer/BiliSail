import 'package:flutter/material.dart';

import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/live_card_cover.dart';
import '../../../shared/ui/scroll_aware_hover_region.dart';
import '../../live/domain/live_room.dart';
import '../domain/library_repository.dart';

/// Non-video histories share the grid, cover ratio and typography of video cards.
final class HistoryContentCard extends StatefulWidget {
  const HistoryContentCard({
    super.key,
    required this.entry,
    required this.date,
    required this.dateTooltip,
    required this.onOpen,
    required this.onDelete,
    this.onOpenAuthor,
  });

  final WatchHistoryEntry entry;
  final String date, dateTooltip;
  final VoidCallback onOpen;
  final VoidCallback? onDelete, onOpenAuthor;

  @override
  State<HistoryContentCard> createState() => _HistoryContentCardState();
}

class _HistoryContentCardState extends State<HistoryContentCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final date = widget.date, dateTooltip = widget.dateTooltip;
    final onDelete = widget.onDelete, onOpenAuthor = widget.onOpenAuthor;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = entry.type == HistoryContentType.live
        ? (entry.isLive ? '直播中' : '未开播')
        : entry.type.label;
    final card = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          setState(() => _hovered = false);
          widget.onOpen();
        },
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: entry.type == HistoryContentType.live
                  ? LiveCardCover(
                      roomId: RoomId(entry.contentId ?? ''),
                      hovered: _hovered,
                      previewEnabled: entry.isLive,
                      borderRadius: 12,
                      child: _cover(context, label),
                    )
                  : _cover(context, label),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entry.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 15),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '历史记录操作',
                  iconSize: 20,
                  onSelected: (_) => onDelete?.call(),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'delete',
                      enabled: onDelete != null,
                      child: const Text('删除记录'),
                    ),
                  ],
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: onOpenAuthor,
                    child: Text(
                      entry.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Tooltip(
                  message: dateTooltip,
                  child: Text(
                    date,
                    maxLines: 1,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    return entry.type == HistoryContentType.live
        ? ScrollAwareHoverRegion(
            onHover: (hovered) => setState(() => _hovered = hovered),
            child: card,
          )
        : card;
  }

  Widget _cover(BuildContext context, String label) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: scheme.surfaceContainerHighest,
            child: entry.coverUrl.isEmpty
                ? Icon(
                    entry.type == HistoryContentType.live
                        ? Icons.live_tv_outlined
                        : Icons.article_outlined,
                    color: scheme.onSurfaceVariant,
                  )
                : AppCoverImage(url: entry.coverUrl),
          ),
          Positioned(
            top: 8,
            left: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: entry.isLive
                    ? scheme.primaryContainer
                    : scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                child: Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: entry.isLive
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
