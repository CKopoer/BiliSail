import 'package:flutter/material.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_cover_image.dart';
import '../../../shared/ui/card_menu.dart';
import '../../../shared/ui/highlighted_text.dart';
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
    this.busy = false,
  });

  final WatchHistoryEntry entry;
  final String date, dateTooltip;
  final VoidCallback onOpen;
  final VoidCallback? onDelete, onOpenAuthor;
  final bool busy;

  @override
  State<HistoryContentCard> createState() => _HistoryContentCardState();
}

class _HistoryContentCardState extends State<HistoryContentCard> {
  bool _hovered = false, _focused = false, _authorHovered = false;
  bool _menuFocused = false, _menuOpen = false;
  final _menuAnchor = GlobalKey();

  Future<void> _showMenu() async {
    if (_menuOpen ||
        widget.busy ||
        widget.onDelete == null ||
        !WorkspaceActivity.isActive(context)) {
      return;
    }
    final entry = widget.entry;
    setState(() => _menuOpen = true);
    bool? selected;
    try {
      selected = await showCardMenu<bool>(
        context,
        anchorKey: _menuAnchor,
        actions: const [
          (value: true, icon: Icons.delete_outline, label: '删除记录'),
        ],
      );
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
    if (mounted &&
        selected == true &&
        identical(widget.entry, entry) &&
        !widget.busy &&
        WorkspaceActivity.isActive(context)) {
      widget.onDelete?.call();
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final entry = widget.entry;
      final theme = Theme.of(context);
      final scheme = theme.colorScheme;
      final textScaler = MediaQuery.textScalerOf(context);
      final label = entry.type == HistoryContentType.live
          ? (entry.isLive ? '直播中' : '未开播')
          : entry.type.label;
      final metadataStyle = theme.textTheme.bodySmall?.copyWith(
        fontSize: 13,
        height: 16 / 13,
      );
      final touchPlatform = switch (theme.platform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };
      return ScrollAwareHoverRegion(
        onHover: (hovered) => setState(() => _hovered = hovered),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            clipBehavior: Clip.none,
            child: InkWell(
              onTap: () {
                setState(() => _hovered = false);
                widget.onOpen();
              },
              onLongPress: _showMenu,
              onFocusChange: (focused) => setState(() => _focused = focused),
              hoverColor: Colors.transparent,
              hoverDuration: Duration.zero,
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
                            child: _cover(context, label),
                          )
                        : _cover(context, label),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 9, bottom: 1),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: double.infinity,
                          // Match video cards' two scaled 22px title lines.
                          height: textScaler.scale(15) * (22 / 15) * 2 + 2,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: HighlightedText(
                                  entry.title,
                                  query: '',
                                  maxLines: 2,
                                  showOverflowTooltip: true,
                                  tooltipTriggerMode: TooltipTriggerMode.manual,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500,
                                    height: 22 / 15,
                                    color:
                                        (_hovered || _focused) &&
                                            !_authorHovered
                                        ? scheme.primary
                                        : scheme.onSurface,
                                  ),
                                ),
                              ),
                              CardMenuButton(
                                anchorKey: _menuAnchor,
                                buttonKey: const ValueKey(
                                  'history-content-title-menu',
                                ),
                                cardWidth: constraints.maxWidth,
                                visible:
                                    _hovered ||
                                    _focused ||
                                    _menuFocused ||
                                    _menuOpen ||
                                    touchPlatform,
                                busy: widget.busy,
                                onFocusChange: (focused) =>
                                    setState(() => _menuFocused = focused),
                                onPressed:
                                    widget.busy || widget.onDelete == null
                                    ? null
                                    : _showMenu,
                                tooltip: '历史记录操作',
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        LayoutBuilder(
                          builder: (context, constraints) => Row(
                            children: [
                              Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: ScrollAwareHoverRegion(
                                    onHover: (hovered) => setState(
                                      () => _authorHovered = hovered,
                                    ),
                                    child: InkWell(
                                      onTap: widget.onOpenAuthor,
                                      hoverColor: Colors.transparent,
                                      hoverDuration: Duration.zero,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Flexible(
                                            child: Text(
                                              entry.author,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: metadataStyle?.copyWith(
                                                color: _authorHovered
                                                    ? scheme.primary
                                                    : null,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.date.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxWidth: constraints.maxWidth * .4,
                                  ),
                                  child: Tooltip(
                                    message: widget.dateTooltip,
                                    child: Text(
                                      widget.date,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: metadataStyle,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _cover(BuildContext context, String label) {
    final entry = widget.entry;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
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
