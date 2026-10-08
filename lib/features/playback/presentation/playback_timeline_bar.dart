import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../shared/ui/storyboard_thumbnail.dart';

import '../domain/playback_timeline.dart';

export '../../../shared/ui/storyboard_thumbnail.dart';

/// Hover and drag state stay local. Preview never commands the media engine.
class PlaybackTimelineBar extends StatefulWidget {
  const PlaybackTimelineBar({
    super.key,
    required this.position,
    required this.duration,
    required this.buffered,
    required this.chapters,
    required this.sourceGeneration,
    required this.playerBoundsKey,
    required this.onSeek,
    required this.onPreviewRequest,
    this.storyboard,
    this.storyboardLoading = false,
    this.storyboardMessage,
    this.onMenuChanged,
  });
  final Duration position, duration, buffered;
  final List<VideoChapter> chapters;
  final int sourceGeneration;
  final GlobalKey playerBoundsKey;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPreviewRequest;
  final VideoStoryboard? storyboard;
  final bool storyboardLoading;
  final String? storyboardMessage;
  final ValueChanged<bool>? onMenuChanged;

  @override
  State<PlaybackTimelineBar> createState() => _PlaybackTimelineBarState();
}

class _PlaybackTimelineBarState extends State<PlaybackTimelineBar> {
  final _overlay = OverlayPortalController();
  final _link = LayerLink();
  final _barKey = GlobalKey();
  Duration? _preview;
  double? _drag;
  bool _hovering = false;
  double? _layoutWidth;

  @override
  void didUpdateWidget(covariant PlaybackTimelineBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sourceGeneration != widget.sourceGeneration ||
        widget.duration <= Duration.zero) {
      _preview = null;
      _drag = null;
      _hovering = false;
      // OverlayPortal cannot change visibility during a widget update/build.
      // Clearing the position removes the preview content in this frame.
      if (_overlay.isShowing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _preview == null) _overlay.hide();
        });
      }
    }
  }

  void _show(Duration position) {
    if (widget.duration <= Duration.zero) return;
    setState(() => _preview = position);
    _overlay.show();
    widget.onPreviewRequest();
  }

  void _hide() {
    if (_drag != null) return;
    _overlay.hide();
    setState(() => _preview = null);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.duration.inMilliseconds.toDouble();
    final enabled = total > 0;
    final value = (_drag ?? widget.position.inMilliseconds.toDouble()).clamp(
      0.0,
      enabled ? total : 1.0,
    );
    final chapters = normalizeChapters(widget.chapters, widget.duration);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (_layoutWidth != width) {
          _layoutWidth = width;
          if (_preview != null) {
            // Recompute edge clamping after the player's new layout settles.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _preview != null) setState(() {});
            });
          }
        }
        final trackWidth = math.max(0.0, width - 16);
        return OverlayPortal(
          controller: _overlay,
          overlayChildBuilder: (context) => _buildPreview(context, trackWidth),
          child: CompositedTransformTarget(
            link: _link,
            child: MouseRegion(
              onEnter: (_) => _hovering = true,
              onHover: enabled
                  ? (event) {
                      if (_drag != null || trackWidth <= 0) return;
                      final horizontalFraction =
                          ((event.localPosition.dx - 8) / trackWidth).clamp(
                            0.0,
                            1.0,
                          );
                      final fraction =
                          Directionality.of(context) == TextDirection.rtl
                          ? 1 - horizontalFraction
                          : horizontalFraction;
                      _show(Duration(milliseconds: (fraction * total).round()));
                    }
                  : null,
              onExit: (_) {
                _hovering = false;
                _hide();
              },
              child: Column(
                key: _barKey,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chapters.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 20,
                      child: Stack(
                        children: [
                          for (final chapter in chapters)
                            _chapterLabel(context, chapter, total, trackWidth),
                          Positioned(
                            right: 4,
                            top: 0,
                            bottom: 0,
                            child: SizedBox(
                              width: 24,
                              child: PopupMenuButton<VideoChapter>(
                                key: const ValueKey('playback-chapters-menu'),
                                tooltip: '视频章节',
                                padding: EdgeInsets.zero,
                                icon: const Icon(
                                  Icons.segment,
                                  color: Colors.white70,
                                  size: 17,
                                ),
                                onOpened: () {
                                  _hide();
                                  widget.onMenuChanged?.call(true);
                                },
                                onCanceled: () =>
                                    widget.onMenuChanged?.call(false),
                                onSelected: (chapter) {
                                  widget.onMenuChanged?.call(false);
                                  if (mounted) widget.onSeek(chapter.start);
                                },
                                itemBuilder: (_) => [
                                  for (final chapter in chapters)
                                    PopupMenuItem(
                                      value: chapter,
                                      child: SizedBox(
                                        width: 240,
                                        child: Row(
                                          children: [
                                            Text(
                                              formatPlaybackTime(chapter.start),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                chapter.title,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  SizedBox(
                    height: 22,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        trackShape: ChapterSliderTrackShape(
                          chapters: chapters,
                          total: widget.duration,
                          buffered: widget.buffered,
                          hovered: _preview,
                        ),
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 5,
                        ),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Listener(
                        onPointerCancel: (_) {
                          _drag = null;
                          _hide();
                        },
                        child: Slider(
                          key: const ValueKey('playback-timeline-slider'),
                          padding: EdgeInsets.zero,
                          min: 0,
                          max: enabled ? total : 1,
                          value: value,
                          semanticFormatterCallback: (value) =>
                              formatPlaybackTime(
                                Duration(milliseconds: value.round()),
                              ),
                          onChangeStart: enabled
                              ? (value) {
                                  _drag = value;
                                  _show(Duration(milliseconds: value.round()));
                                }
                              : null,
                          onChanged: enabled
                              ? (value) {
                                  _drag = value;
                                  _show(Duration(milliseconds: value.round()));
                                }
                              : null,
                          onChangeEnd: enabled
                              ? (value) {
                                  final position = Duration(
                                    milliseconds: value.round(),
                                  );
                                  setState(() => _drag = null);
                                  widget.onSeek(position);
                                  if (!_hovering) _hide();
                                }
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _chapterLabel(
    BuildContext context,
    VideoChapter chapter,
    double total,
    double width,
  ) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final start = width * chapter.start.inMilliseconds / total;
    final end = width * chapter.end.inMilliseconds / total;
    final left = rtl ? width - end : start;
    final available = math.min(end - start, width - 24 - left);
    const style = TextStyle(color: Colors.white70, fontSize: 11);
    final text = TextPainter(
      text: TextSpan(text: chapter.title, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final fits = text.width + 12 <= available && text.height <= 18;
    text.dispose();
    if (!fits) {
      return const SizedBox.shrink();
    }
    return Positioned(
      left: 8 + left,
      width: available,
      top: 2,
      child: ExcludeSemantics(
        child: Text(
          chapter.title,
          style: style,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  Widget _buildPreview(BuildContext context, double trackWidth) {
    final position = _preview;
    final target = _barKey.currentContext?.findRenderObject();
    final bounds = widget.playerBoundsKey.currentContext?.findRenderObject();
    if (position == null ||
        target is! RenderBox ||
        bounds is! RenderBox ||
        !target.hasSize ||
        !bounds.hasSize ||
        bounds.size.width < 80) {
      return const SizedBox.shrink();
    }
    final origin = target.localToGlobal(Offset.zero);
    final player = bounds.localToGlobal(Offset.zero);
    final availableHeight = origin.dy - player.dy - 8;
    final textScale = MediaQuery.textScalerOf(context).scale(12) / 12;
    if (availableHeight < 28 * textScale) return const SizedBox.shrink();
    final width = math.min(184.0, bounds.size.width - 16);
    final fraction = position.inMilliseconds / widget.duration.inMilliseconds;
    final x =
        8 +
        trackWidth *
            (Directionality.of(context) == TextDirection.rtl
                ? 1 - fraction
                : fraction);
    final left = (origin.dx + x - width / 2).clamp(
      player.dx + 8,
      player.dx + bounds.size.width - width - 8,
    );
    final chapters = normalizeChapters(widget.chapters, widget.duration);
    final chapter = chapterAt(chapters, position);
    final frame = widget.storyboard?.frameAt(position);
    final storyboard = widget.storyboard;
    final footer = chapter == null ? 28.0 * textScale : 52.0 * textScale;
    final showTitle = chapter != null && availableHeight >= footer;
    final imageHeight = (availableHeight - footer).clamp(0.0, 104.0);
    final showImage = frame != null && imageHeight >= 36;
    return Positioned(
      left: 0,
      top: 0,
      child: CompositedTransformFollower(
        link: _link,
        showWhenUnlinked: false,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: Offset(left - origin.dx, -8),
        child: IgnorePointer(
          child: Material(
            key: const ValueKey('playback-seek-preview'),
            color: const Color(0xff262626),
            elevation: 6,
            borderRadius: BorderRadius.circular(6),
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showImage && storyboard != null)
                    StoryboardThumbnail(
                      storyboard: storyboard,
                      frame: frame,
                      width: width,
                      height: math.min(
                        imageHeight,
                        width / storyboard.aspectRatio,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: Row(
                      children: [
                        Text(
                          formatPlaybackTime(position),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                        if (!showImage && widget.storyboardLoading) ...[
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              '加载预览…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                        if (!showImage && widget.storyboardMessage != null) ...[
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Icon(
                              Icons.image_not_supported_outlined,
                              color: Colors.white54,
                              size: 14,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showTitle)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          chapter.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChapterSliderTrackShape extends SliderTrackShape {
  const ChapterSliderTrackShape({
    required this.chapters,
    required this.total,
    required this.buffered,
    this.hovered,
  });
  final List<VideoChapter> chapters;
  final Duration total, buffered;
  final Duration? hovered;

  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) => Rect.fromLTWH(
    offset.dx + 8,
    offset.dy + (parentBox.size.height - 3) / 2,
    math.max(0, parentBox.size.width - 16),
    3,
  );

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
    required TextDirection textDirection,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    if (rect.width <= 0) return;
    final canvas = context.canvas;
    final duration = total.inMilliseconds;
    final boundaries = <double>{0, 1};
    if (duration > 0) {
      for (final chapter in chapters) {
        boundaries.add(
          (chapter.start.inMilliseconds / duration).clamp(0.0, 1.0),
        );
        boundaries.add((chapter.end.inMilliseconds / duration).clamp(0.0, 1.0));
      }
    }
    final ordered = boundaries.toList()..sort();
    final rtl = textDirection == TextDirection.rtl;
    final position =
        ((rtl ? rect.right - thumbCenter.dx : thumbCenter.dx - rect.left) /
                rect.width)
            .clamp(0.0, 1.0);
    final bufferedFraction = duration <= 0
        ? 0.0
        : (buffered.inMilliseconds / duration).clamp(0.0, 1.0);
    final hovering = hovered;
    final hoveredFraction = hovering == null || duration <= 0
        ? null
        : hovering.inMilliseconds / duration;
    final paint = Paint();
    for (var i = 0; i + 1 < ordered.length; i++) {
      final start = ordered[i], end = ordered[i + 1];
      final left = rect.left + rect.width * (rtl ? 1 - end : start);
      final right = rect.left + rect.width * (rtl ? 1 - start : end);
      final gap = chapters.isEmpty ? 0.0 : math.min(2.0, (right - left) / 3);
      final hoveredSegment =
          hoveredFraction != null &&
          hoveredFraction >= start &&
          hoveredFraction < end;
      final segment = Rect.fromLTRB(
        left + (i == 0 ? 0 : gap / 2),
        rect.top - (hoveredSegment ? 1 : 0),
        right - (i == ordered.length - 2 ? 0 : gap / 2),
        rect.bottom + (hoveredSegment ? 1 : 0),
      );
      canvas.save();
      canvas.clipRRect(
        RRect.fromRectAndRadius(segment, const Radius.circular(1.5)),
      );
      canvas.drawRect(
        segment,
        paint..color = sliderTheme.inactiveTrackColor ?? Colors.white24,
      );
      final bufferedX =
          rect.left +
          rect.width * (rtl ? 1 - bufferedFraction : bufferedFraction);
      canvas.drawRect(
        Rect.fromLTRB(
          rtl ? bufferedX : rect.left,
          segment.top,
          rtl ? rect.right : bufferedX,
          segment.bottom,
        ),
        paint..color = Colors.white38,
      );
      final playedX = rect.left + rect.width * (rtl ? 1 - position : position);
      canvas.drawRect(
        Rect.fromLTRB(
          rtl ? playedX : rect.left,
          segment.top,
          rtl ? rect.right : playedX,
          segment.bottom,
        ),
        paint..color = sliderTheme.activeTrackColor ?? const Color(0xffdf6589),
      );
      canvas.restore();
    }
  }
}

String formatPlaybackTime(Duration position) {
  final seconds = position.inSeconds;
  final hours = seconds ~/ 3600;
  final minutes = (seconds ~/ 60 % 60).toString().padLeft(2, '0');
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$remainder' : '$minutes:$remainder';
}

/// The two-pixel collapsed track keeps the same chapter boundaries.
class ChapterBoundaryPainter extends CustomPainter {
  const ChapterBoundaryPainter({
    required this.chapters,
    required this.duration,
    required this.textDirection,
  });
  final List<VideoChapter> chapters;
  final Duration duration;
  final TextDirection textDirection;
  @override
  void paint(Canvas canvas, Size size) {
    if (duration <= Duration.zero) return;
    final boundaries = <Duration>{
      for (final chapter in chapters) ...[chapter.start, chapter.end],
    };
    final paint = Paint()..color = Colors.black;
    for (final boundary in boundaries) {
      if (boundary <= Duration.zero || boundary >= duration) continue;
      final fraction = boundary.inMilliseconds / duration.inMilliseconds;
      final x =
          size.width *
          (textDirection == TextDirection.rtl ? 1 - fraction : fraction);
      canvas.drawRect(Rect.fromLTWH(x - 1, 0, 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant ChapterBoundaryPainter oldDelegate) =>
      chapters != oldDelegate.chapters ||
      duration != oldDelegate.duration ||
      textDirection != oldDelegate.textDirection;
}
