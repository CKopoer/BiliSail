import 'package:flutter/material.dart';

import '../../../domain/video.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/bili_icons.dart';
import '../../../shared/ui/video_card.dart';
import '../domain/watch_later_queue.dart';

/// The expanded queue occupies the sidebar; its heading remains when folded.
final class WatchLaterQueuePanel extends StatefulWidget {
  const WatchLaterQueuePanel({
    super.key,
    required this.queue,
    required this.current,
    required this.expanded,
    required this.onToggle,
    required this.onSelect,
  });

  final WatchLaterQueue queue;
  final VideoId current;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<VideoId> onSelect;

  @override
  State<WatchLaterQueuePanel> createState() => _WatchLaterQueuePanelState();
}

final class _WatchLaterQueuePanelState extends State<WatchLaterQueuePanel> {
  final ScrollController _scroll = ScrollController();
  int? _positionedIndex;

  @override
  void didUpdateWidget(covariant WatchLaterQueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.queue.id != widget.queue.id ||
        oldWidget.expanded != widget.expanded) {
      _positionedIndex = null;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  double _measureLines(
    BuildContext context,
    TextStyle style,
    String text,
    int lines,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: lines,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final index = widget.queue.indexOf(widget.current);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: scheme.surfaceContainerLow,
          child: InkWell(
            onTap: widget.onToggle,
            child: SizedBox(
              height: 48 * textScale.clamp(1, 1.5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Icon(
                      widget.expanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 20,
                    ),
                    const SizedBox(width: 4),
                    Text('稍后再看', style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(width: 8),
                    Icon(Icons.equalizer, size: 15, color: scheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      '${index + 1}/${widget.queue.items.length}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.expanded)
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final coverWidth =
                    (constraints.maxWidth - 50 - 160 * textScale.clamp(1, 1.5))
                        .clamp(96.0, 141.0);
                final typography = Theme.of(context).textTheme;
                final titleHeight = _measureLines(
                  context,
                  (typography.bodyMedium ?? const TextStyle()).copyWith(
                    fontSize: 14,
                    height: 1.3,
                  ),
                  '汉字Ag\n汉字Ag',
                  2,
                );
                final authorHeight = _measureLines(
                  context,
                  typography.bodySmall ?? const TextStyle(),
                  '汉字Ag',
                  1,
                );
                final countHeight = _measureLines(
                  context,
                  (typography.bodySmall ?? const TextStyle()).copyWith(
                    fontSize: 12,
                  ),
                  '9999.9万',
                  1,
                );
                final rowHeight =
                    (coverWidth * 9 / 16).clamp(
                      titleHeight + authorHeight + countHeight + 4 * textScale,
                      double.infinity,
                    ) +
                    20;
                if (index >= 0 && _positionedIndex != index) {
                  _positionedIndex = index;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted || !_scroll.hasClients) return;
                    final start = index * rowHeight;
                    final end = start + rowHeight;
                    final visibleStart = _scroll.offset;
                    final visibleEnd =
                        visibleStart + _scroll.position.viewportDimension;
                    if (start < visibleStart || end > visibleEnd) {
                      _scroll.jumpTo(
                        start.clamp(0.0, _scroll.position.maxScrollExtent),
                      );
                    }
                  });
                }
                return ListView.builder(
                  key: const ValueKey('watch-later-queue-list'),
                  controller: _scroll,
                  itemExtent: rowHeight,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: widget.queue.items.length,
                  itemBuilder: (context, itemIndex) => _QueueRow(
                    item: widget.queue.items[itemIndex],
                    selected: itemIndex == index,
                    coverWidth: coverWidth,
                    onTap: () =>
                        widget.onSelect(widget.queue.items[itemIndex].video.id),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

final class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.item,
    required this.selected,
    required this.coverWidth,
    required this.onTap,
  });

  final WatchLaterQueueItem item;
  final bool selected;
  final double coverWidth;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final viewText = item.playCountText.isEmpty ? '—' : item.playCountText;
    final danmakuText = item.danmakuCountText.isEmpty
        ? '—'
        : item.danmakuCountText;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: .10)
          : Colors.transparent,
      child: InkWell(
        key: ValueKey('watch-later-queue-${item.video.id.value}'),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: coverWidth,
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (item.video.coverUrl.isEmpty)
                          _coverFallback(context)
                        else
                          AppCoverImage(
                            url: item.video.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _coverFallback(context),
                          ),
                        Positioned(
                          right: 3,
                          bottom: 3,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: const Color(0xB9000000),
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 3,
                                vertical: 1,
                              ),
                              child: Text(
                                durationLabel(item.video.duration),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.video.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: selected ? scheme.primary : scheme.onSurface,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                    SizedBox(height: 2 * textScale),
                    Text(
                      item.video.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    SizedBox(height: 2 * textScale),
                    Row(
                      children: [
                        Icon(
                          BiliIcons.playCount,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            viewText,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          BiliIcons.comment,
                          size: 12,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            danmakuText,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 12,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _coverFallback(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.surfaceContainerHighest, scheme.surfaceContainerHigh],
        ),
      ),
      child: Center(
        child: Icon(
          Icons.play_circle_outline,
          size: 30,
          color: scheme.onSurfaceVariant.withValues(alpha: .55),
        ),
      ),
    );
  }
}
