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
    this.onRemove,
    this.pendingRemovals = const {},
    this.collapsedChild,
    this.onLoadMore,
    this.loadingMore = false,
    this.loadMoreMessage,
  });

  final WatchLaterQueue queue;
  final VideoId current;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<VideoId> onSelect;
  final ValueChanged<WatchLaterQueueItem>? onRemove;
  final Set<String> pendingRemovals;
  final VoidCallback? onLoadMore;
  final bool loadingMore;
  final String? loadMoreMessage;

  /// Lazily mount the details on first collapse, then retain their state.
  final Widget? collapsedChild;

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
                    AnimatedRotation(
                      turns: widget.expanded ? .5 : 0,
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.keyboard_arrow_down, size: 20),
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        widget.queue.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(Icons.equalizer, size: 15, color: scheme.primary),
                    const SizedBox(width: 5),
                    Text(
                      '${widget.queue.offset + index + 1}/${widget.queue.offset + widget.queue.items.length}${widget.queue.hasMore ? '+' : ''}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.collapsedChild case final Widget details)
          Expanded(
            child: _QueueBodyTransition(
              expanded: widget.expanded,
              queue: _buildList(context, index, textScale),
              details: details,
            ),
          )
        else if (widget.expanded)
          Expanded(child: _buildList(context, index, textScale)),
      ],
    );
  }

  Widget _buildList(
    BuildContext context,
    int index,
    double textScale,
  ) => LayoutBuilder(
    builder: (context, constraints) {
      final coverWidth =
          (constraints.maxWidth - 50 - 160 * textScale.clamp(1, 1.5)).clamp(
            96.0,
            141.0,
          );
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
        (typography.bodySmall ?? const TextStyle()).copyWith(fontSize: 12),
        '9999.9万',
        1,
      );
      final rowHeight =
          (coverWidth * 9 / 16).clamp(
            titleHeight +
                authorHeight +
                countHeight.clamp(28.0, double.infinity) +
                4 * textScale,
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
          final visibleEnd = visibleStart + _scroll.position.viewportDimension;
          if (start < visibleStart || end > visibleEnd) {
            _scroll.jumpTo(start.clamp(0.0, _scroll.position.maxScrollExtent));
          }
        });
      }
      return NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth == 0 &&
              notification is ScrollUpdateNotification &&
              notification.metrics.extentAfter < 300 &&
              !widget.loadingMore &&
              widget.loadMoreMessage == null) {
            widget.onLoadMore?.call();
          }
          return false;
        },
        child: ListView.builder(
          key: const ValueKey('watch-later-queue-list'),
          controller: _scroll,
          itemExtent: rowHeight,
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount:
              widget.queue.items.length +
              (widget.onLoadMore == null && widget.loadMoreMessage == null
                  ? 0
                  : 1),
          itemBuilder: (context, itemIndex) =>
              itemIndex == widget.queue.items.length
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: widget.loadingMore
                        ? const CircularProgressIndicator()
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (widget.loadMoreMessage case final message?)
                                Text(
                                  message,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              TextButton(
                                onPressed: widget.onLoadMore,
                                child: Text(
                                  widget.loadMoreMessage == null
                                      ? '加载更多投稿'
                                      : '重试',
                                ),
                              ),
                            ],
                          ),
                  ),
                )
              : _QueueRow(
                  key: ValueKey(widget.queue.items[itemIndex].removalId),
                  item: widget.queue.items[itemIndex],
                  selected: itemIndex == index,
                  coverWidth: coverWidth,
                  onTap: () =>
                      widget.onSelect(widget.queue.items[itemIndex].video.id),
                  onRemove: itemIndex == index || widget.onRemove == null
                      ? null
                      : () => widget.onRemove?.call(
                          widget.queue.items[itemIndex],
                        ),
                  removing: widget.pendingRemovals.contains(
                    widget.queue.items[itemIndex].removalId,
                  ),
                ),
        ),
      );
    },
  );
}

final class _QueueBodyTransition extends StatefulWidget {
  const _QueueBodyTransition({
    required this.expanded,
    required this.queue,
    required this.details,
  });

  final bool expanded;
  final Widget queue, details;

  @override
  State<_QueueBodyTransition> createState() => _QueueBodyTransitionState();
}

final class _QueueBodyTransitionState extends State<_QueueBodyTransition>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    value: widget.expanded ? 1 : 0,
  )..addStatusListener(_settled);
  late final _opacity = _controller.drive(
    CurveTween(curve: Curves.easeOutCubic),
  );
  late final _offset = _opacity.drive(
    Tween(begin: const Offset(0, -.04), end: Offset.zero),
  );
  late bool _detailsVisited = !widget.expanded;

  void _settled(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
  }

  @override
  void didUpdateWidget(covariant _QueueBodyTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.expanded) _detailsVisited = true;
    if (oldWidget.expanded != widget.expanded) {
      widget.expanded ? _controller.forward() : _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ClipRect(
    child: Stack(
      fit: StackFit.expand,
      children: [
        // Offstage retains the providers and scroll state after first viewing.
        // Fade/slide only update painting; the fixed viewport never resizes.
        Offstage(
          offstage: widget.expanded && !_controller.isAnimating,
          child: IgnorePointer(
            ignoring: widget.expanded,
            child: ExcludeFocus(
              excluding: widget.expanded,
              child: ExcludeSemantics(
                excluding: widget.expanded,
                child: TickerMode(
                  enabled: !widget.expanded,
                  child: FadeTransition(
                    opacity: ReverseAnimation(_opacity),
                    child: RepaintBoundary(
                      child: _detailsVisited
                          ? widget.details
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Release list rows and image leases once the exit animation completes.
        if (widget.expanded || _controller.isAnimating)
          IgnorePointer(
            ignoring: !widget.expanded,
            child: ExcludeFocus(
              excluding: !widget.expanded,
              child: ExcludeSemantics(
                excluding: !widget.expanded,
                child: FadeTransition(
                  opacity: _opacity,
                  child: SlideTransition(
                    position: _offset,
                    child: RepaintBoundary(child: widget.queue),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

final class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.item,
    required this.selected,
    required this.coverWidth,
    required this.onTap,
    required this.onRemove,
    required this.removing,
  });

  final WatchLaterQueueItem item;
  final bool selected;
  final double coverWidth;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  final bool removing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final viewText = compactCountLabel(
      item.video.playCount,
      item.playCountText,
    );
    final danmakuText = compactCountLabel(
      item.video.danmakuCount,
      item.danmakuCountText,
    );
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
                        Expanded(
                          child: Row(
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
                        ),
                        if (onRemove != null)
                          TextButton.icon(
                            key: ValueKey(
                              'watch-later-queue-remove-${item.video.id.value}',
                            ),
                            onPressed: removing ? null : onRemove,
                            style: TextButton.styleFrom(
                              foregroundColor: scheme.onSurfaceVariant,
                              minimumSize: const Size(0, 28),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              textStyle: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(fontSize: 12),
                            ),
                            icon: removing
                                ? const SizedBox.square(
                                    dimension: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline, size: 14),
                            label: const Text('删除'),
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
