import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/app_notice.dart';
import '../../../shared/ui/video_card.dart';
import '../../video/domain/video_actions_repository.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_grid.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../application/feed_controller.dart';
import '../domain/home_channel.dart';
import 'home_content.dart';

final class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({
    super.key,
    this.channel = HomeChannel.recommended,
    this.isSignedIn = false,
    this.onLogin,
    this.initialSection,
  });
  final HomeChannel channel;
  final bool isSignedIn;
  final VoidCallback? onLogin;
  final String? initialSection;
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

final class _FeedScreenState extends ConsumerState<FeedScreen> {
  final Map<HomeChannel, String> _sections = {};
  final Set<(HomeChannel, String)> _visitedSections = {};
  (List<VideoSummary>, HomeChannel, Set<VideoId>, Set<VideoId>, Set<VideoId>)?
  _gridVersion;
  Widget? _grid;

  Widget _videoItemsSliver(FeedState feed, HomeChannel channel) {
    Widget status(Widget child) =>
        SliverToBoxAdapter(child: SizedBox(height: 300, child: child));
    if (feed.channel != channel || feed.items.asData == null) {
      _gridVersion = null;
      _grid = null;
    }
    if (feed.channel != channel) return status(const StateView.loading());
    return feed.items.when(
      loading: () => status(const StateView.loading()),
      error: (error, _) => status(
        StateView.error(
          message: error is AppFailure ? error.message : '视频加载失败，请稍后重试',
          onAction: _refreshFeed,
        ),
      ),
      data: (items) {
        final controller = ref.read(feedControllerProvider.notifier);
        final version = (
          items,
          channel,
          feed.rejected,
          feed.rejecting,
          feed.uncertainRestorations,
        );
        // Pagination flags belong to the footer. Keep the same grid widget
        // while its data/actions are unchanged so its visible rows stay built.
        final previous = _gridVersion;
        if (previous == null ||
            !identical(previous.$1, items) ||
            previous.$2 != channel ||
            !setEquals(previous.$3, feed.rejected) ||
            !setEquals(previous.$4, feed.rejecting) ||
            !setEquals(previous.$5, feed.uncertainRestorations)) {
          _gridVersion = version;
          _grid = SliverVideoGrid(
            items: items,
            onOpen: (id) => context.go('/video/${id.value}'),
            onOpenUser: (id) => context.go('/user/${id.value}'),
            showRecommendationReason: channel == HomeChannel.recommended,
            feedbackFor: channel == HomeChannel.recommended
                ? (video) => feed.rejected.contains(video.id)
                      ? VideoCardFeedback(
                          busy: feed.rejecting.contains(video.id),
                          onUndo: feed.uncertainRestorations.contains(video.id)
                              ? null
                              : () => _undoRecommendationFeedback(video.id),
                        )
                      : null
                : null,
            menuFor: channel == HomeChannel.recommended
                ? (video) => VideoCardMenu(
                    actions: const [
                      VideoCardMenuAction.notInterested,
                      VideoCardMenuAction.watchLater,
                    ],
                    busy: feed.rejecting.contains(video.id),
                    onSelected: (action) {
                      if (action == VideoCardMenuAction.notInterested) {
                        _rejectRecommendation(video);
                      }
                    },
                  )
                : null,
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            if (items.isEmpty)
              status(const StateView.empty(message: '这里暂时没有视频'))
            else
              ?_grid,
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 20),
                child: Center(
                  child: feed.pageError != null
                      ? StateView.error(
                          message: feed.pageError is AppFailure
                              ? (feed.pageError as AppFailure).message
                              : '加载更多失败',
                          onAction: controller.loadMore,
                        )
                      : feed.loadingMore
                      ? const Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        )
                      : feed.hasMore
                      ? OutlinedButton(
                          onPressed: controller.loadMore,
                          child: const Text('加载更多'),
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _content({
    required Widget videoFeed,
    required HomeChannel channel,
    required String? section,
  }) {
    final current = (channel, section ?? '');
    if (!channel.hasVideoFeed) _visitedSections.add(current);
    final visited = _visitedSections.toList(growable: false);
    return IndexedStack(
      index: channel.hasVideoFeed ? 0 : visited.indexOf(current) + 1,
      children: [
        videoFeed,
        for (final entry in visited)
          HomeContent(
            key: ValueKey(entry),
            channel: entry.$1,
            section: entry.$2,
            active: !channel.hasVideoFeed && entry == current,
            isSignedIn: widget.isSignedIn,
            onLogin: widget.onLogin,
          ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _selectInitialSection();
    _selectChannel();
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.channel != widget.channel) {
      _selectInitialSection();
    }
    if (oldWidget.channel != widget.channel) _selectChannel();
  }

  void _selectChannel() {
    Future<void>.microtask(() {
      if (mounted) {
        ref.read(feedControllerProvider.notifier).selectChannel(widget.channel);
      }
    });
  }

  void _selectInitialSection() {
    final section = widget.initialSection;
    if (section != null && widget.channel.sections.contains(section)) {
      _sections[widget.channel] = section;
    }
  }

  Future<void> _refreshFeed() {
    if (widget.channel == HomeChannel.ranking) {
      ref.invalidate(rankingCategoriesProvider);
    }
    return ref.read(feedControllerProvider.notifier).refresh();
  }

  Future<void> _rejectRecommendation(VideoSummary video) async {
    if (!widget.isSignedIn) {
      showAppNotice(context, '请先登录后再反馈推荐');
      return;
    }
    final controller = ref.read(feedControllerProvider.notifier);
    try {
      await controller.rejectRecommendation(video);
    } on UnknownWriteOutcome {
      if (mounted &&
          widget.channel == HomeChannel.recommended &&
          WorkspaceActivity.isActive(context)) {
        showAppNotice(context, '反馈结果暂时无法确认，请刷新列表核对');
      }
    } on AppFailure catch (failure) {
      if (mounted &&
          widget.channel == HomeChannel.recommended &&
          WorkspaceActivity.isActive(context) &&
          failure.kind != AppFailureKind.cancelled) {
        showAppNotice(context, failure.message);
      }
    }
  }

  Future<void> _undoRecommendationFeedback(VideoId id) async {
    final controller = ref.read(feedControllerProvider.notifier);
    try {
      await controller.undoRecommendationFeedback(id);
    } on UnknownWriteOutcome {
      if (mounted &&
          widget.channel == HomeChannel.recommended &&
          WorkspaceActivity.isActive(context)) {
        showAppNotice(context, '撤销结果暂时无法确认，请稍后刷新核对');
      }
    } on AppFailure catch (failure) {
      if (mounted &&
          widget.channel == HomeChannel.recommended &&
          WorkspaceActivity.isActive(context) &&
          failure.kind != AppFailureKind.cancelled) {
        showAppNotice(context, failure.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentFeed = ref.watch(feedControllerProvider);
    final controller = ref.read(feedControllerProvider.notifier);
    final channel = widget.channel;
    final feed = controller.stateForChannel(channel);
    final section = _sections[channel] ?? channel.sections.firstOrNull;
    final categories = switch (channel) {
      HomeChannel.categories => ref.watch(feedCategoriesProvider),
      HomeChannel.ranking => ref.watch(rankingCategoriesProvider),
      _ => null,
    };
    if (channel == HomeChannel.ranking) {
      ref.listen(rankingCategoriesProvider, (_, next) {
        final regions = next.asData?.value;
        final current = ref.read(feedControllerProvider);
        final id = current.categoryId;
        if (regions != null &&
            current.channel == HomeChannel.ranking &&
            id != null &&
            id != '0' &&
            !regions.any((region) => region.id == id)) {
          controller.selectCategory('0');
        }
      });
    }
    final entries = <(String, String)>[
      if (channel == HomeChannel.ranking) ('0', '全站'),
      if (categories != null)
        for (final category in categories.asData?.value ?? const [])
          (category.id, category.name)
      else
        for (final label in channel.sections) (label, label),
    ];
    return Stack(
      children: [
        Column(
          children: [
            if (entries.isNotEmpty)
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: const SmoothScrollBehavior(
                          horizontalMouseWheel: true,
                        ),
                        child: SingleChildScrollView(
                          key: ValueKey('home-section-strip-${channel.name}'),
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final entry in entries)
                                Padding(
                                  padding: const EdgeInsets.only(right: 4),
                                  child: TextButton(
                                    key: ValueKey('home-section-${entry.$1}'),
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          (categories != null
                                              ? feed.categoryId == entry.$1
                                              : section == entry.$1)
                                          ? Theme.of(context)
                                                .colorScheme
                                                .primary
                                          : Theme.of(context)
                                                .colorScheme
                                                .onSurfaceVariant,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                      ),
                                      textStyle: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(fontSize: 13),
                                    ),
                                    onPressed: () {
                                      if (categories != null) {
                                        controller.selectCategory(entry.$1);
                                      } else {
                                        setState(
                                          () => _sections[channel] = entry.$1,
                                        );
                                      }
                                    },
                                    child: Text(entry.$2),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: _content(
                channel: channel,
                section: section,
                videoFeed: PagedScrollViewport(
                  key: ValueKey(('video-feed', channel)),
                  active: channel.hasVideoFeed,
                  canLoadMore:
                      currentFeed.channel == channel &&
                      feed.hasMore &&
                      !feed.loadingMore &&
                      feed.items.asData != null &&
                      feed.pageError == null,
                  contentVersion: feed,
                  onLoadMore: () async {
                    // Channel selection is deferred; never paginate the old
                    // controller query from the restored channel's layout.
                    final current = ref.read(feedControllerProvider);
                    if (current.channel == channel &&
                        current.pageError == null) {
                      await controller.loadMore();
                    }
                  },
                  onRefresh: _refreshFeed,
                  refreshTooltip: '刷新视频',
                  builder: (scrollController) => RefreshIndicator(
                    onRefresh: _refreshFeed,
                    child: CustomScrollView(
                      key: PageStorageKey('feed-${channel.name}'),
                      controller: scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (categories?.hasError == true)
                          SliverToBoxAdapter(
                            child: StateView.error(
                              message: '分区列表加载失败',
                              onAction: () {
                                if (channel == HomeChannel.ranking) {
                                  ref.invalidate(rankingCategoriesProvider);
                                } else {
                                  ref.invalidate(feedCategoriesProvider);
                                }
                              },
                            ),
                          ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                          sliver: _videoItemsSliver(feed, channel),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
