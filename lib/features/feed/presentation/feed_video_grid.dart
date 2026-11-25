import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../domain/recommendation_card.dart';
import '../application/recommendation_reporter.dart';

import '../../../core/platform/external_links.dart';
import '../../../core/network/api_requests.dart';
import '../../playback/application/recommendation_playback_registry.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../domain/video.dart';
import '../../../domain/course_address.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/video_card.dart';
import '../../../shared/ui/workspace_link.dart';
import '../application/feed_controller.dart';
import '../application/recommendation_publication_time.dart';
import '../domain/home_channel.dart';

/// The grid observes list membership; each mounted card owns its feedback view.
final class FeedVideoGrid extends ConsumerWidget {
  const FeedVideoGrid({
    super.key,
    required this.items,
    required this.channel,
    required this.onReject,
    required this.onUndo,
    this.previousStartIndex,
  });

  final List<VideoSummary> items;
  final HomeChannel channel;
  final ValueChanged<VideoSummary> onReject;
  final ValueChanged<VideoId> onUndo;
  final int? previousStartIndex;

  Widget _grid(int start, int end, RecommendationReporter? reporter) =>
      SliverResponsiveCardGrid.withColumns(
        itemCount: end - start,
        positionedBuilder: (context, offset, columns) {
          final index = start + offset;
          return _FeedVideoCard(
            key: ValueKey((items[index].id, index)),
            video: items[index],
            reporter: reporter,
            position: index + 1,
            row: (start + columns - 1) ~/ columns + offset ~/ columns + 1,
            column: offset % columns + 1,
            recommended: channel == HomeChannel.recommended,
            onReject: onReject,
            onUndo: onUndo,
          );
        },
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reporter =
        channel == HomeChannel.recommended &&
            WorkspaceActivity.isActive(context) &&
            ModalRoute.isCurrentOf(context) != false
        ? ref.watch(recommendationReporterProvider)
        : null;
    final active = reporter != null && ref.watch(_foregroundProvider);
    final reporting = active ? reporter : null;
    final boundary = previousStartIndex;
    if (boundary == null || boundary < 0 || boundary >= items.length) {
      return _grid(0, items.length, reporting);
    }
    return SliverMainAxisGroup(
      slivers: [
        if (boundary > 0) _grid(0, boundary, reporting),
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Row(
              children: [
                Expanded(child: Divider()),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('上次看到这里'),
                ),
                Expanded(child: Divider()),
              ],
            ),
          ),
        ),
        _grid(boundary, items.length, reporting),
      ],
    );
  }
}

final _foregroundProvider = NotifierProvider.autoDispose<_Foreground, bool>(
  _Foreground.new,
);

final class _Foreground extends Notifier<bool> {
  @override
  bool build() {
    final listener = AppLifecycleListener(
      onStateChange: (value) {
        state = value == AppLifecycleState.resumed;
      },
    );
    ref.onDispose(listener.dispose);
    final current = WidgetsBinding.instance.lifecycleState;
    return current == null || current == AppLifecycleState.resumed;
  }
}

typedef _FeedbackState = ({bool rejected, bool busy, bool uncertain});

final class _FeedVideoCard extends ConsumerStatefulWidget {
  const _FeedVideoCard({
    super.key,
    required this.video,
    required this.reporter,
    required this.position,
    required this.row,
    required this.column,
    required this.recommended,
    required this.onReject,
    required this.onUndo,
  });

  final VideoSummary video;
  final RecommendationReporter? reporter;
  final int position, row, column;
  final bool recommended;
  final ValueChanged<VideoSummary> onReject;
  final ValueChanged<VideoId> onUndo;

  @override
  ConsumerState<_FeedVideoCard> createState() => _FeedVideoCardState();
}

final class _FeedVideoCardState extends ConsumerState<_FeedVideoCard> {
  VideoCard? _card;
  _FeedbackState? _feedback;
  DateTime? _publicationTime;

  void _report(RecommendationInteraction interaction) {
    final card = widget.video.recommendationCard;
    if (card != null) {
      widget.reporter?.record(
        card,
        interaction,
        position: widget.position,
        row: widget.row,
        column: widget.column,
      );
    }
  }

  Future<void> _open() async {
    if (widget.reporter != null) {
      // A tap may precede the next coalesced visibility callback.
      _report(RecommendationInteraction.exposure);
      _report(RecommendationInteraction.click);
    }
    final target = widget.video.recommendationTarget;
    String attributedRoute(String route, {String? episode}) {
      final attribution = widget.video.recommendationPlayback;
      final epoch = ref.read(sessionEpochProvider)();
      final videoId = target?.kind == RecommendationTargetKind.video
          ? target?.id ?? ''
          : widget.video.id.value;
      if (attribution == null ||
          !attribution.matches(videoId, epoch, episode: episode)) {
        return route;
      }
      final routeId = ref
          .read(recommendationPlaybackRegistryProvider)
          .capture(attribution);
      return Uri.parse(route)
          .replace(queryParameters: {'recommendation': routeId})
          .toString();
    }

    if (target == null) {
      context.openWorkspaceLink(
        attributedRoute('/video/${widget.video.id.value}'),
      );
      return;
    }
    final route = switch (target.kind) {
      RecommendationTargetKind.video => '/video/${target.id}',
      RecommendationTargetKind.episode => '/pgc/episode/${target.id}',
      RecommendationTargetKind.season => '/pgc/season/${target.id}',
      RecommendationTargetKind.live => '/live/${target.id}',
      _ => null,
    };
    if (route != null) {
      context.openWorkspaceLink(
        attributedRoute(
          route,
          episode: target.kind == RecommendationTargetKind.episode
              ? target.id
              : null,
        ),
      );
      return;
    }
    final url = target.url;
    final course = CourseAddress.parse(url);
    if (course != null) {
      context.openWorkspaceLink(course.location);
      return;
    }
    if (WorkspaceLinkScope.openingInBackground) return;
    if (url == null) {
      showAppNotice(context, '暂不支持打开此推荐类型');
      return;
    }
    var opened = false;
    try {
      opened = await ref.read(externalLinkOpenerProvider)(url);
    } on PlatformException {
      opened = false;
    }
    if (mounted && !opened) showAppNotice(context, '无法打开此推荐，请稍后重试');
  }

  @override
  void didUpdateWidget(_FeedVideoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.video, widget.video) ||
        oldWidget.recommended != widget.recommended) {
      _card = null;
      _publicationTime = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.recommended &&
        widget.video.id.isValid &&
        widget.video.publishedAt == null &&
        WorkspaceActivity.isActive(context)) {
      final date = ref
          .watch(recommendationPublicationTimeProvider(widget.video.id))
          .asData
          ?.value;
      if (_publicationTime != date) {
        _publicationTime = date;
        _card = null;
      }
    }
    var feedback = (rejected: false, busy: false, uncertain: false);
    if (widget.recommended) {
      final controller = ref.watch(feedControllerProvider.notifier);
      feedback = ref.watch(
        feedControllerProvider.select((current) {
          final state = controller.stateForChannel(
            HomeChannel.recommended,
            current: current,
          );
          return (
            rejected: state.rejected.contains(widget.video.id),
            busy: state.rejecting.contains(widget.video.id),
            uncertain: state.uncertainRestorations.contains(widget.video.id),
          );
        }),
      );
    }
    if (_feedback != feedback) {
      _feedback = feedback;
      _card = null;
    }
    // Sliver delegates update when a page is appended. Reuse the heavy card
    // only for unchanged immutable data; cache lifetime is the mounted tile,
    // not the entire loaded feed. Inherited theme/activity still reach it.
    final child = _card ??= VideoCard(
      key: ValueKey(widget.video.id),
      video: widget.video,
      onTap: _open,
      onOpenUser: (id) => context.openWorkspaceLink('/user/${id.value}'),
      showRecommendationReason: widget.recommended,
      publishedAt: _publicationTime,
      feedback: feedback.rejected
          ? VideoCardFeedback(
              busy: feedback.busy,
              onUndo: feedback.uncertain
                  ? null
                  : () => widget.onUndo(widget.video.id),
            )
          : null,
      menu: widget.recommended
          ? VideoCardMenu(
              actions: [
                VideoCardMenuAction.notInterested,
                if (widget.video.id.isValid) VideoCardMenuAction.watchLater,
              ],
              busy: feedback.busy,
              // Read current callbacks and data, even after a parent update
              // that deliberately reused this card (for example login state).
              onSelected: (action) {
                if (action == VideoCardMenuAction.notInterested) {
                  widget.onReject(widget.video);
                }
              },
            )
          : null,
    );
    final card = widget.video.recommendationCard;
    final reporter = widget.reporter;
    if (card == null || !widget.recommended) return child;
    final observe =
        reporter != null && !feedback.rejected && !reporter.seen(card);
    return VisibilityDetector(
      key: ValueKey((this, card)),
      onVisibilityChanged: observe
          ? (info) {
              if (mounted &&
                  identical(widget.video.recommendationCard, card) &&
                  identical(widget.reporter, reporter) &&
                  info.visibleFraction >= 0.5) {
                _report(RecommendationInteraction.exposure);
                // Stop observing this response card for its remaining lifetime.
                if (reporter.seen(card)) setState(() {});
              }
            }
          : null,
      child: child,
    );
  }
}
