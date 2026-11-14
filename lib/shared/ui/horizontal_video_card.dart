import 'package:flutter/material.dart';

import '../../domain/user.dart';
import '../../domain/video.dart';
import 'app_cover_image.dart';
import 'bili_icons.dart';
import 'highlighted_text.dart';
import 'scroll_aware_hover_region.dart';
import 'video_card.dart';
import 'video_card_cover.dart';
import 'video_card_menu_sheet.dart';

final class HorizontalVideoCard extends StatefulWidget {
  const HorizontalVideoCard({
    super.key,
    required this.video,
    this.onTap,
    this.onOpenUser,
    this.selected = false,
    this.playCountText = '',
    this.danmakuCountText = '',
    this.trailing,
    this.showWatchLaterActions = true,
  });

  static const coverSize = Size(140, 79);
  static const coverSpacing = 10.0;

  static TextStyle? titleStyleOf(BuildContext context) =>
      Theme.of(context).textTheme.titleSmall?.copyWith(height: 19 / 14);

  final VideoSummary video;
  final VoidCallback? onTap;
  final ValueChanged<UserId>? onOpenUser;
  final bool selected;
  final String playCountText, danmakuCountText;
  final Widget? trailing;
  final bool showWatchLaterActions;

  @override
  State<HorizontalVideoCard> createState() => _HorizontalVideoCardState();
}

final class _HorizontalVideoCardState extends State<HorizontalVideoCard> {
  bool _hovered = false;
  bool _focused = false;
  bool _authorHovered = false;
  bool _authorFocused = false;

  @override
  Widget build(BuildContext context) {
    final video = widget.video;
    final theme = Theme.of(context);
    final authorId = video.authorId;
    final onOpenUser = widget.onOpenUser;
    final canOpenAuthor =
        authorId != null && authorId.isValid && onOpenUser != null;
    return ScrollAwareHoverRegion(
      onHover: (hovered) => setState(() => _hovered = hovered),
      child: InkWell(
        onTap: widget.onTap,
        onLongPress: widget.showWatchLaterActions
            ? () => showVideoCardWatchLaterMenu(
                context,
                video.id,
                isCurrent: () => widget.video.id == video.id,
              )
            : null,
        onFocusChange: (focused) => setState(() => _focused = focused),
        hoverColor: Colors.transparent,
        hoverDuration: Duration.zero,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: HorizontalVideoCard.coverSize.width,
              height: HorizontalVideoCard.coverSize.height,
              child: VideoCardCover(
                video: video,
                hovered: _hovered,
                focused: _focused,
                borderRadius: 5,
                showWatchLaterButton: widget.showWatchLaterActions,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (video.coverUrl.isEmpty)
                      const ColoredBox(
                        color: Colors.black12,
                        child: Icon(Icons.video_library_outlined),
                      )
                    else
                      AppCoverImage(
                        url: video.coverUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) =>
                            const Icon(Icons.video_library_outlined),
                      ),
                    Positioned(
                      right: 4,
                      bottom: 3,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: Text(
                            durationLabel(video.duration),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: HorizontalVideoCard.coverSpacing),
            Expanded(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: HorizontalVideoCard.coverSize.height,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HighlightedText(
                      video.title,
                      query: '',
                      maxLines: 2,
                      showOverflowTooltip: true,
                      tooltipTriggerMode: MediaQuery.sizeOf(context).width < 600
                          ? TooltipTriggerMode.manual
                          : TooltipTriggerMode.longPress,
                      style: HorizontalVideoCard.titleStyleOf(context)
                          ?.copyWith(
                            color: widget.selected
                                ? theme.colorScheme.primary
                                : null,
                          ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                BiliIcons.up,
                                size: 13,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                              const SizedBox(width: 3),
                              Flexible(
                                child: ScrollAwareHoverRegion(
                                  onHover: (hovered) =>
                                      setState(() => _authorHovered = hovered),
                                  child: InkWell(
                                    onTap: canOpenAuthor
                                        ? () => onOpenUser(authorId)
                                        : null,
                                    onFocusChange: (focused) => setState(
                                      () => _authorFocused = focused,
                                    ),
                                    hoverColor: Colors.transparent,
                                    hoverDuration: Duration.zero,
                                    child: Text(
                                      video.author,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                            color:
                                                canOpenAuthor &&
                                                    (_authorHovered ||
                                                        _authorFocused)
                                                ? theme.colorScheme.primary
                                                : null,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (widget.trailing case final trailing?)
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Expanded(child: _statistics(video)),
                                const SizedBox(width: 4),
                                trailing,
                              ],
                            )
                          else
                            _statistics(video),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statistics(VideoSummary video) => Wrap(
    spacing: 8,
    runSpacing: 3,
    children: [
      _VideoMeta(
        icon: BiliIcons.playCount,
        label: compactCountLabel(video.playCount, widget.playCountText),
      ),
      _VideoMeta(
        icon: BiliIcons.danmaku,
        label: compactCountLabel(video.danmakuCount, widget.danmakuCountText),
      ),
    ],
  );
}

final class _VideoMeta extends StatelessWidget {
  const _VideoMeta({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        icon,
        size: 16,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 5),
      Flexible(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ],
  );
}
