import '../../domain/user.dart';
import 'bili_icons.dart';
import 'app_cover_image.dart';
import 'bili_badges.dart';
import 'highlighted_text.dart';
import 'video_card_cover.dart';
import 'video_card_interaction_scope.dart';
import 'video_card_feedback.dart';
export 'video_card_feedback.dart' show VideoCardFeedback;
import '../../features/video/domain/video_card_interactions.dart';
import '../../core/presentation/workspace_activity.dart';

import 'package:flutter/material.dart';

import '../../domain/video.dart';

String compactCount(int? count) {
  if (count == null) return '—';
  if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
  return '$count';
}

String _videoCountLabel(int? count, String text) {
  final value = text.trim();
  if (value.isEmpty) return compactCount(count);
  // Keep server-provided abbreviations; format decimal count text locally.
  final numericCount = int.tryParse(value, radix: 10);
  return numericCount == null ? text : compactCount(numericCount);
}

String durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

enum VideoCardMenuAction { notInterested, watchLater, removeWatchLater }

final class VideoCardMenu {
  const VideoCardMenu({
    required this.actions,
    this.onSelected,
    this.busy = false,
  });
  final List<VideoCardMenuAction> actions;
  final ValueChanged<VideoCardMenuAction>? onSelected;
  final bool busy;
}

final class VideoCard extends StatefulWidget {
  const VideoCard({
    super.key,
    required this.video,
    required this.onTap,
    this.progress,
    this.onOpenUser,
    this.showUpBadge = false,
    this.showRecommendationReason = false,
    this.highlightQuery = '',
    this.playCountText = '',
    this.danmakuCountText = '',
    this.publishText = '',
    this.publishTooltip,
    this.menu,
    this.feedback,
    this.showWatchLaterButton = true,
  });

  final ValueChanged<UserId>? onOpenUser;
  final VideoSummary video;
  final VoidCallback onTap;
  final double? progress;
  final bool showUpBadge;
  final bool showRecommendationReason;
  final String highlightQuery;
  // Counts may arrive as decimal text or server-provided abbreviations.
  final String playCountText;
  final String danmakuCountText;
  final String publishText;
  final String? publishTooltip;
  final VideoCardMenu? menu;
  final VideoCardFeedback? feedback;
  final bool showWatchLaterButton;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

final class _VideoCardState extends State<VideoCard> {
  static const _titleFontSize = 15.0;

  bool _hovered = false;
  bool _focused = false;
  bool _authorHovered = false;
  bool _menuFocused = false;
  bool _menuOpen = false;
  bool _addingWatchLater = false;
  int _addGeneration = 0;
  VideoCardInteractions? _interactions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final interactions = VideoCardInteractionScope.maybeOf(context)
        ?.interactions;
    if (_interactions != interactions) {
      _interactions = interactions;
      _addGeneration++;
      _addingWatchLater = false;
    }
  }

  @override
  void didUpdateWidget(VideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.video.id != oldWidget.video.id) {
      _addGeneration++;
      _addingWatchLater = false;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) =>
        _buildCard(context, constraints.maxWidth),
  );

  Widget _buildCard(BuildContext context, double cardWidth) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final video = widget.video;
    final playLabel = _videoCountLabel(video.playCount, widget.playCountText);
    final danmakuLabel = _videoCountLabel(
      video.danmakuCount,
      widget.danmakuCountText,
    );
    final textScaler = MediaQuery.textScalerOf(context);
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: _titleFontSize,
      fontWeight: FontWeight.w500,
      height: 1.4,
    );
    final highlighted = (_hovered || _focused) && !_authorHovered;
    final progress = widget.progress;
    return AnimatedContainer(
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
          onTap: widget.feedback == null ? widget.onTap : null,
          hoverColor: Colors.transparent,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: switch (widget.feedback) {
                  final feedback? => VideoCardFeedbackCover(
                    feedback: feedback,
                    background: video.coverUrl.isEmpty
                        ? _coverFallback(context)
                        : AppCoverImage(
                            url: video.coverUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => _coverFallback(context),
                          ),
                  ),
                  null => VideoCardCover(
                    video: video,
                    showWatchLaterButton: widget.showWatchLaterButton,
                    focused: _focused,
                    hovered: _hovered,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (video.coverUrl.isNotEmpty)
                            AppCoverImage(
                              url: video.coverUrl,
                              fit: BoxFit.cover,
                              excludeFromSemantics: true,
                              errorBuilder: (_, _, _) =>
                                  _coverFallback(context),
                              frameBuilder: (_, child, frame, _) =>
                                  frame != null
                                  ? child
                                  : _coverFallback(context),
                            )
                          else
                            _coverFallback(context),
                          Align(
                            alignment: Alignment.bottomCenter,
                            child: SizedBox(
                              width: double.infinity,
                              height: textScaler.scale(36) + 20,
                              child: const DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Color(0xC4000000),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            left: 7,
                            right: 7,
                            bottom: 7,
                            child: Semantics(
                              label:
                                  '观看 $playLabel，'
                                  '弹幕 $danmakuLabel，'
                                  '时长 ${durationLabel(video.duration)}',
                              excludeSemantics: true,
                              child: _CoverMetadata(
                                video: video,
                                cardWidth: cardWidth,
                                playLabel: playLabel,
                                danmakuLabel: danmakuLabel,
                              ),
                            ),
                          ),
                          if (progress != null)
                            Align(
                              alignment: Alignment.bottomLeft,
                              child: LinearProgressIndicator(
                                value: progress.clamp(0.0, 1.0),
                                minHeight: 3,
                                backgroundColor: Colors.transparent,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                },
              ),
              Padding(
                padding: const EdgeInsets.only(top: 9, bottom: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reserve two scaled lines so author rows align across cards.
                    SizedBox(
                      width: double.infinity,
                      height: textScaler.scale(_titleFontSize) * 1.4 * 2 + 2,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: HighlightedText(
                              video.title,
                              query: widget.highlightQuery,
                              maxLines: 2,
                              style: titleStyle?.copyWith(
                                color: highlighted
                                    ? scheme.primary
                                    : scheme.onSurface,
                              ),
                            ),
                          ),
                          if (widget.feedback == null)
                            if (widget.menu case final menu?) _menuButton(menu),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    _AuthorMetadata(
                      video: video,
                      onOpenUser: widget.feedback == null
                          ? widget.onOpenUser
                          : null,
                      hovered: _authorHovered,
                      onHover: (value) =>
                          setState(() => _authorHovered = value),
                      showUpBadge: widget.showUpBadge,
                      reason: widget.showRecommendationReason
                          ? video.recommendationReason
                          : null,
                      publishText: widget.publishText,
                      publishTooltip: widget.publishTooltip,
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

  Widget _menuButton(VideoCardMenu menu) {
    final touchPlatform = switch (Theme.of(context).platform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
    final visible =
        _hovered || _focused || _menuFocused || _menuOpen || touchPlatform;
    final busy = menu.busy || _addingWatchLater;
    return Focus(
      skipTraversal: true,
      onFocusChange: (focused) => setState(() => _menuFocused = focused),
      child: Opacity(
        opacity: visible ? 1 : 0,
        child: IgnorePointer(
          ignoring: !visible,
          child: PopupMenuButton<VideoCardMenuAction>(
            key: const ValueKey('video-card-title-menu'),
            tooltip: busy ? '操作中' : '更多操作',
            enabled: !busy,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 156, maxWidth: 240),
            position: PopupMenuPosition.under,
            color: Theme.of(context).colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(
                color: Theme.of(context).colorScheme.outlineVariant
                    .withValues(alpha: .6),
              ),
            ),
            onOpened: () => setState(() => _menuOpen = true),
            onCanceled: () {
              if (mounted) setState(() => _menuOpen = false);
            },
            onSelected: (action) {
              if (!mounted) return;
              setState(() => _menuOpen = false);
              if (action == VideoCardMenuAction.watchLater) {
                _addWatchLater();
              } else {
                menu.onSelected?.call(action);
              }
            },
            icon: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.more_vert, size: 20),
            iconSize: 20,
            style: IconButton.styleFrom(
              minimumSize: const Size(28, 28),
              maximumSize: const Size(28, 28),
              padding: EdgeInsets.zero,
            ),
            itemBuilder: (_) => [
              for (final action in menu.actions)
                PopupMenuItem(
                  value: action,
                  child: Row(
                    children: [
                      Icon(switch (action) {
                        VideoCardMenuAction.notInterested =>
                          Icons.not_interested_outlined,
                        VideoCardMenuAction.watchLater =>
                          Icons.watch_later_outlined,
                        VideoCardMenuAction.removeWatchLater =>
                          Icons.delete_outline,
                      }, size: 19),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(switch (action) {
                          VideoCardMenuAction.notInterested => '不感兴趣',
                          VideoCardMenuAction.watchLater => '稍后再看',
                          VideoCardMenuAction.removeWatchLater => '删除',
                        }),
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

  Future<void> _addWatchLater() async {
    if (!WorkspaceActivity.isActive(context)) return;
    final scope = VideoCardInteractionScope.maybeOf(context);
    if (scope == null || _addingWatchLater) return;
    final id = widget.video.id;
    final generation = ++_addGeneration;
    setState(() => _addingWatchLater = true);
    final result = await scope.interactions.addWatchLater(id);
    if (!mounted ||
        generation != _addGeneration ||
        widget.video.id != id ||
        scope.interactions !=
            VideoCardInteractionScope.maybeOf(context)?.interactions) {
      return;
    }
    setState(() => _addingWatchLater = false);
    final message = switch (result) {
      WatchLaterResult.added || WatchLaterResult.alreadyAdded => '已加入稍后再看',
      WatchLaterResult.signIn => '请先登录后再添加稍后再看',
      WatchLaterResult.uncertain => '添加结果暂时无法确认，请在稍后再看列表核对',
      WatchLaterResult.failed => '添加失败，请稍后重试',
      WatchLaterResult.busy || WatchLaterResult.cancelled => null,
    };
    if (message != null && WorkspaceActivity.isActive(context)) {
      scope.onNotice(context, message);
    }
  }

  Widget _coverFallback(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Icon(
      Icons.image_outlined,
      size: 36,
      color: Theme.of(context).colorScheme.onSurfaceVariant
          .withValues(alpha: 0.6),
    ),
  );
}

final class _CoverMetadata extends StatelessWidget {
  const _CoverMetadata({
    required this.video,
    required this.cardWidth,
    required this.playLabel,
    required this.danmakuLabel,
  });

  final VideoSummary video;
  final double cardWidth;
  final String playLabel;
  final String danmakuLabel;

  static const _regularFontSize = 12.0;
  static const _style = TextStyle(
    color: Colors.white,
    fontSize: _regularFontSize,
    fontWeight: FontWeight.w400,
    shadows: [Shadow(blurRadius: 2, color: Colors.black)],
  );
  static const _iconSize = 13.0;
  static const _iconGap = 3.0;
  static const _countGap = 8.0;
  static const _durationGap = 8.0;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // Use the whole card width so padding does not shift typography tiers.
      final fontSize = switch (cardWidth) {
        < 180 => 10.0,
        < 240 => 11.0,
        _ => _regularFontSize,
      };
      final sizeFactor = fontSize / _regularFontSize;
      final style = _style.copyWith(fontSize: fontSize);
      final iconSize = _iconSize * sizeFactor;
      final iconGap = _iconGap * sizeFactor;
      final countGap = _countGap * sizeFactor;
      final durationGap = _durationGap * sizeFactor;
      final timeLabel = durationLabel(video.duration);
      double textWidth(String label) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: DefaultTextStyle.of(context).style.merge(style),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: 1,
        )..layout();
        final width = painter.width;
        painter.dispose();
        return width;
      }

      // Measure the actual labels, icons and gaps before moving time below counts.
      final countsWidth =
          textWidth(playLabel) +
          textWidth(danmakuLabel) +
          2 * (iconSize + iconGap) +
          countGap;
      final countsFit = countsWidth <= constraints.maxWidth;
      final stacked =
          countsWidth + durationGap + textWidth(timeLabel) >
          constraints.maxWidth;
      Widget count(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: iconSize),
          SizedBox(width: iconGap),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: style,
            ),
          ),
        ],
      );

      final play = count(BiliIcons.playCount, playLabel);
      final danmaku = count(BiliIcons.danmaku, danmakuLabel);
      final counts = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          countsFit ? play : Flexible(child: play),
          SizedBox(width: countGap),
          countsFit ? danmaku : Flexible(child: danmaku),
        ],
      );
      final duration = Text(
        timeLabel,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            counts,
            SizedBox(height: 2 * sizeFactor),
            Align(alignment: Alignment.centerRight, child: duration),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: counts),
          SizedBox(width: durationGap),
          duration,
        ],
      );
    },
  );
}

final class _AuthorMetadata extends StatelessWidget {
  const _AuthorMetadata({
    required this.video,
    required this.onOpenUser,
    required this.hovered,
    required this.onHover,
    required this.showUpBadge,
    required this.reason,
    required this.publishText,
    required this.publishTooltip,
  });
  final VideoSummary video;
  final ValueChanged<UserId>? onOpenUser;
  final bool hovered;
  final ValueChanged<bool> onHover;
  final bool showUpBadge;
  final String? reason;
  final String publishText;
  final String? publishTooltip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final id = video.authorId;
    final openUser = onOpenUser;
    final date = video.publishedAt?.toLocal();
    final dateText = date == null
        ? publishText
        : date.year == DateTime.now().year
        ? '${date.month}-${date.day}'
        : '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final reasonText = reason?.trim() ?? '';
    final author = MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: InkWell(
        onTap: id != null && id.isValid && openUser != null
            ? () => openUser(id)
            : null,
        hoverColor: Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showUpBadge) ...[
              const BiliUpBadge(size: 16),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                video.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: hovered ? theme.colorScheme.primary : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    final badge = DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFF7F50)
            .withValues(alpha: theme.brightness == Brightness.dark ? .18 : .1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        child: Text(
          reasonText,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFFFF7F50)),
        ),
      ),
    );
    final published = Text(
      dateText,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodySmall,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          children: [
            if (reasonText.isNotEmpty) ...[
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .35,
                ),
                child: badge,
              ),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Align(alignment: Alignment.centerLeft, child: author),
            ),
            if (dateText.isNotEmpty) ...[
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: constraints.maxWidth * .4,
                ),
                child: publishTooltip == null
                    ? published
                    : Tooltip(message: publishTooltip, child: published),
              ),
            ],
          ],
        );
      },
    );
  }
}
