import '../../domain/user.dart';
import 'bili_icons.dart';
import 'app_network_image.dart';
import 'bili_badges.dart';
import 'highlighted_text.dart';

import 'package:flutter/material.dart';

import '../../domain/video.dart';

String compactCount(int? count) {
  if (count == null) return '—';
  if (count >= 100000000) return '${(count / 100000000).toStringAsFixed(1)}亿';
  if (count >= 10000) return '${(count / 10000).toStringAsFixed(1)}万';
  return '$count';
}

String durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
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
  });

  final ValueChanged<UserId>? onOpenUser;
  final VideoSummary video;
  final VoidCallback onTap;
  final double? progress;
  final bool showUpBadge;
  final bool showRecommendationReason;
  final String highlightQuery;
  // Dynamic feeds may supply abbreviated counts rather than exact numbers.
  final String playCountText;
  final String danmakuCountText;
  final String publishText;

  @override
  State<VideoCard> createState() => _VideoCardState();
}

final class _VideoCardState extends State<VideoCard> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final video = widget.video;
    final textScaler = MediaQuery.textScalerOf(context);
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.4,
    );
    final highlighted = _hovered || _focused;
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
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: widget.onTap,
          hoverColor: Colors.transparent,
          onHover: (value) => setState(() => _hovered = value),
          onFocusChange: (value) => setState(() => _focused = value),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (video.coverUrl.isNotEmpty)
                        AppNetworkImage(
                          url: video.coverUrl,
                          cacheWidth: 640,
                          fit: BoxFit.cover,
                          excludeFromSemantics: true,
                          errorBuilder: (_, _, _) => _coverFallback(context),
                          frameBuilder: (_, child, frame, _) =>
                              frame != null ? child : _coverFallback(context),
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
                                colors: [Colors.transparent, Color(0xC4000000)],
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
                              '观看 ${widget.playCountText.isEmpty ? compactCount(video.playCount) : widget.playCountText}，'
                              '弹幕 ${widget.danmakuCountText.isEmpty ? compactCount(video.danmakuCount) : widget.danmakuCountText}，'
                              '时长 ${durationLabel(video.duration)}',
                          excludeSemantics: true,
                          child: _CoverMetadata(
                            video: video,
                            playCountText: widget.playCountText,
                            danmakuCountText: widget.danmakuCountText,
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
              Padding(
                padding: const EdgeInsets.only(top: 9, bottom: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Reserve two scaled lines so author rows align across cards.
                    SizedBox(
                      height: textScaler.scale(14) * 1.4 * 2 + 2,
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
                    const SizedBox(height: 6),
                    _AuthorMetadata(
                      video: video,
                      onOpenUser: widget.onOpenUser,
                      showUpBadge: widget.showUpBadge,
                      reason: widget.showRecommendationReason
                          ? video.recommendationReason
                          : null,
                      publishText: widget.publishText,
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
    required this.playCountText,
    required this.danmakuCountText,
  });

  final VideoSummary video;
  final String playCountText;
  final String danmakuCountText;

  static const _style = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w400,
    shadows: [Shadow(blurRadius: 2, color: Colors.black)],
  );

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final stacked =
          MediaQuery.textScalerOf(context).scale(11) > 16 ||
          constraints.maxWidth < 210;
      final counts = Row(
        children: [
          Flexible(
            child: _count(
              BiliIcons.playCount,
              playCountText.isEmpty
                  ? compactCount(video.playCount)
                  : playCountText,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: _count(
              BiliIcons.danmaku,
              danmakuCountText.isEmpty
                  ? compactCount(video.danmakuCount)
                  : danmakuCountText,
            ),
          ),
        ],
      );
      final duration = Text(
        durationLabel(video.duration),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _style,
      );
      if (stacked) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            counts,
            const SizedBox(height: 2),
            Align(alignment: Alignment.centerRight, child: duration),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: counts),
          const SizedBox(width: 8),
          duration,
        ],
      );
    },
  );

  Widget _count(IconData icon, String count) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, color: Colors.white, size: 13),
      const SizedBox(width: 3),
      Flexible(
        child: Text(
          count,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _style,
        ),
      ),
    ],
  );
}

final class _AuthorMetadata extends StatelessWidget {
  const _AuthorMetadata({
    required this.video,
    required this.onOpenUser,
    required this.showUpBadge,
    required this.reason,
    required this.publishText,
  });
  final VideoSummary video;
  final ValueChanged<UserId>? onOpenUser;
  final bool showUpBadge;
  final String? reason;
  final String publishText;

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
    final author = InkWell(
      onTap: id != null && id.isValid && openUser != null
          ? () => openUser(id)
          : null,
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
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
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
        // Keep the author readable with large fonts instead of squeezing three labels.
        if (MediaQuery.textScalerOf(context).scale(12) > 18 ||
            constraints.maxWidth < 260) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              author,
              if (reasonText.isNotEmpty || dateText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (reasonText.isNotEmpty) ...[
                      Flexible(child: badge),
                      const SizedBox(width: 6),
                    ],
                    if (dateText.isNotEmpty) Flexible(child: published),
                  ],
                ),
              ],
            ],
          );
        }
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
                child: published,
              ),
            ],
          ],
        );
      },
    );
  }
}
