import 'package:material_ui/material_ui.dart';

import '../../features/live/domain/live_room.dart';
import 'catalog_card_cover.dart';
import 'highlighted_text.dart';
import 'live_card_cover.dart';
import 'scroll_aware_hover_region.dart';
import 'video_card.dart' show compactCountLabel;
import 'workspace_link.dart';

/// The room card used by the live channel and search results.
final class LiveRoomTile extends StatefulWidget {
  const LiveRoomTile({
    super.key,
    required this.roomId,
    required this.title,
    required this.author,
    required this.onOpen,
    this.coverUrl,
    this.popularity = '',
    this.area = '',
    this.isLive,
    this.highlightQuery = '',
    this.onOpenAuthor,
  });

  final RoomId roomId;
  final Uri? coverUrl;
  final String title, author, popularity, area, highlightQuery;
  final bool? isLive;
  final VoidCallback onOpen;
  final VoidCallback? onOpenAuthor;

  @override
  State<LiveRoomTile> createState() => _LiveRoomTileState();
}

final class _LiveRoomTileState extends State<LiveRoomTile> {
  bool _hovered = false;

  void _open(VoidCallback open) {
    if (_hovered) setState(() => _hovered = false);
    open();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final openAuthor = widget.onOpenAuthor;
    final author = Text(
      widget.author,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    void openRoom() => _open(widget.onOpen);
    return ScrollAwareHoverRegion(
      onHover: (hovered) => setState(() => _hovered = hovered),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: openRoom,
          onTertiaryTapUp: WorkspaceLinkScope.middleClick(context, openRoom),
          borderRadius: BorderRadius.circular(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: LiveCardCover(
                  roomId: widget.roomId,
                  hovered: _hovered,
                  previewEnabled: widget.isLive != false,
                  child: CatalogCardCover(
                    url: widget.coverUrl,
                    left: widget.popularity.trim().isEmpty
                        ? ''
                        : '♨ ${compactCountLabel(null, widget.popularity)}',
                    right: widget.area,
                    badge: switch (widget.isLive) {
                      true => '直播中',
                      false => '未开播',
                      null => '直播',
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              HighlightedText(
                widget.title,
                query: widget.highlightQuery,
                maxLines: 2,
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              if (openAuthor == null)
                author
              else
                InkWell(
                  onTap: () => _open(openAuthor),
                  onTertiaryTapUp: WorkspaceLinkScope.middleClick(
                    context,
                    () => _open(openAuthor),
                  ),
                  child: author,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
