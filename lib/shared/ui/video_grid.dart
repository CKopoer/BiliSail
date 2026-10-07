import '../../domain/user.dart';

import 'package:flutter/material.dart';

import '../../domain/video.dart';
import 'responsive_card_grid.dart';
import 'video_card.dart';

final class VideoGrid extends StatelessWidget {
  const VideoGrid({
    super.key,
    required this.items,
    required this.onOpen,
    this.progressFor,
    this.onOpenUser,
    this.showUpBadge = false,
    this.showRecommendationReason = false,
    this.highlightQuery = '',
    this.menuFor,
    this.feedbackFor,
  }) : assert(onOpen != null),
       _onOpenIndex = null,
       progressAt = null,
       publishTextAt = null,
       publishTooltipAt = null;

  /// Entries such as history can share a BVID while identifying different parts.
  const VideoGrid.indexed({
    super.key,
    required this.items,
    required ValueChanged<int> onOpen,
    this.progressAt,
    this.publishTextAt,
    this.publishTooltipAt,
    this.onOpenUser,
    this.showUpBadge = false,
    this.showRecommendationReason = false,
    this.highlightQuery = '',
    this.menuFor,
    this.feedbackFor,
  }) : onOpen = null,
       progressFor = null,
       _onOpenIndex = onOpen;

  final ValueChanged<UserId>? onOpenUser;
  final List<VideoSummary> items;
  final ValueChanged<VideoId>? onOpen;
  final double? Function(VideoId id)? progressFor;
  final ValueChanged<int>? _onOpenIndex;
  final double? Function(int index)? progressAt;
  final String Function(int index)? publishTextAt;
  final String Function(int index)? publishTooltipAt;
  final bool showUpBadge;
  final bool showRecommendationReason;
  final String highlightQuery;
  final VideoCardMenu? Function(VideoSummary)? menuFor;
  final VideoCardFeedback? Function(VideoSummary)? feedbackFor;

  @override
  Widget build(BuildContext context) => ResponsiveCardGrid(
    children: [
      for (var index = 0; index < items.length; index++)
        _cardAt(context, index),
    ],
  );

  Widget _cardAt(BuildContext context, int index) => VideoCard(
    key: ValueKey((items[index].id, index)),
    video: items[index],
    onTap: () => _onOpenIndex != null
        ? _onOpenIndex(index)
        : onOpen?.call(items[index].id),
    onOpenUser: onOpenUser,
    showUpBadge: showUpBadge,
    showRecommendationReason: showRecommendationReason,
    highlightQuery: highlightQuery,
    publishText: publishTextAt?.call(index) ?? '',
    publishTooltip: publishTooltipAt?.call(index),
    menu: menuFor?.call(items[index]),
    feedback: feedbackFor?.call(items[index]),
    progress: progressAt?.call(index) ?? progressFor?.call(items[index].id),
  );
}

/// The same video-card policy, with only viewport/cache rows mounted.
final class SliverVideoGrid extends VideoGrid {
  const SliverVideoGrid({
    super.key,
    required super.items,
    required super.onOpen,
    super.progressFor,
    super.onOpenUser,
    super.showUpBadge,
    super.showRecommendationReason,
    super.highlightQuery,
    super.menuFor,
    super.feedbackFor,
  });

  const SliverVideoGrid.indexed({
    super.key,
    required super.items,
    required super.onOpen,
    super.progressAt,
    super.publishTextAt,
    super.publishTooltipAt,
    super.onOpenUser,
    super.showUpBadge,
    super.showRecommendationReason,
    super.highlightQuery,
    super.menuFor,
    super.feedbackFor,
  }) : super.indexed();

  @override
  Widget build(BuildContext context) =>
      SliverResponsiveCardGrid(itemCount: items.length, itemBuilder: _cardAt);
}
