import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/content_section_tabs.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/smooth_scroll_behavior.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_grid.dart';
import '../application/feed_controller.dart';
import '../domain/feed_repository.dart';
import '../domain/popular_feed.dart';

class PopularFeed extends ConsumerStatefulWidget {
  const PopularFeed({
    super.key,
    required this.active,
    this.initialSection,
    this.onSectionChanged,
    this.swipeEnabled = true,
  });

  final bool active;
  final String? initialSection;
  final ValueChanged<String>? onSectionChanged;
  final bool swipeEnabled;

  @override
  ConsumerState<PopularFeed> createState() => _PopularFeedState();
}

class _PopularFeedState extends ConsumerState<PopularFeed> {
  late PopularSection _selected = PopularSection.fromLabel(
    widget.initialSection,
  );
  late final _progress = TabPagingProgress(_selected.index.toDouble());
  bool _wasActive = false;

  void _activate() {
    Future<void>.microtask(() {
      if (mounted && widget.active && WorkspaceActivity.isActive(context)) {
        ref
            .read(feedControllerProvider.notifier)
            .selectPopularSection(_selected);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncActivity();
  }

  void _syncActivity({bool force = false}) {
    final active = widget.active && WorkspaceActivity.isActive(context);
    if (active && (force || !_wasActive)) _activate();
    _wasActive = active;
  }

  @override
  void didUpdateWidget(PopularFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final changed =
        oldWidget.initialSection != widget.initialSection && widget.active;
    if (changed) {
      _selected = PopularSection.fromLabel(widget.initialSection);
    }
    _syncActivity(force: changed);
  }

  void _select(PopularSection section) {
    if (!widget.active ||
        !WorkspaceActivity.isActive(context) ||
        section == _selected) {
      return;
    }
    setState(() => _selected = section);
    ref.read(feedControllerProvider.notifier).selectPopularSection(section);
    widget.onSectionChanged?.call(section.label);
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: widget.active && WorkspaceActivity.isActive(context),
      child: Column(
        children: [
          ContentSectionTabs<PopularSection>(
            entries: [
              for (final section in PopularSection.values)
                (section, section.label),
            ],
            value: _selected,
            onSelected: _select,
            scrollKey: const ValueKey('home-section-strip-popular'),
            itemKey: (section) => ValueKey('home-section-${section.label}'),
          ),
          Expanded(
            child: RetainedTabView<PopularSection>(
              tabs: PopularSection.values,
              value: _selected,
              onChanged: _select,
              progress: _progress,
              swipeEnabled: widget.swipeEnabled,
              viewKey: const ValueKey('popular-section-pages'),
              pageBuilder: (context, section, active) => _PopularPane(
                section: section,
                active: active && widget.active,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }
}

class _PopularPane extends ConsumerStatefulWidget {
  const _PopularPane({required this.section, required this.active});
  final PopularSection section;
  final bool active;

  @override
  ConsumerState<_PopularPane> createState() => _PopularPaneState();
}

class _PopularPaneState extends ConsumerState<_PopularPane> {
  final _storage = PageStorageBucket();
  final _weekStorage = <int, PageStorageBucket>{};
  bool _regionFallbackPending = false;
  List<VideoSummary>? _gridItems;
  SliverVideoGrid? _grid;
  PopularSection get section => widget.section;

  void _openVideo(VideoId id) => context.go('/video/${id.value}');

  Widget _itemsSliver(AsyncValue<List<VideoSummary>> value) {
    final items = value.asData?.value;
    if (!identical(items, _gridItems)) {
      _gridItems = items;
      _grid = null;
    }
    final controller = ref.read(feedControllerProvider.notifier);
    return value.when(
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(height: 280, child: StateView.loading()),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: StateView.error(
          message: error is AppFailure ? error.message : '热门内容加载失败',
          onAction: controller.refresh,
        ),
      ),
      data: (items) => items.isEmpty
          ? const SliverToBoxAdapter(
              child: StateView.empty(message: '这里暂时没有内容'),
            )
          // Footer/activity changes must not replace the row delegate. The
          // cache owns only this pane's current immutable list and widget.
          : _grid ??= SliverVideoGrid(
              items: items,
              showRecommendationReason: section == PopularSection.weekly,
              onOpen: _openVideo,
              onOpenUser: (id) => context.go('/user/${id.value}'),
            ),
    );
  }

  bool _needsRegionFallback() {
    if (!mounted || !widget.active || !WorkspaceActivity.isActive(context)) {
      return false;
    }
    final regions = ref.read(rankingCategoriesProvider).asData?.value;
    final current = ref.read(feedControllerProvider);
    return current.popular &&
        current.popularSection == PopularSection.ranking &&
        regions != null &&
        current.categoryId != '0' &&
        !regions.any((region) => region.id == current.categoryId);
  }

  void _reconcileRegion() {
    if (_regionFallbackPending || !_needsRegionFallback()) return;
    _regionFallbackPending = true;
    Future<void>.microtask(() {
      _regionFallbackPending = false;
      if (_needsRegionFallback()) {
        ref.read(feedControllerProvider.notifier).selectCategory('0');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final pageActive = widget.active && WorkspaceActivity.isActive(context);
    final controller = ref.watch(feedControllerProvider.notifier);
    final feed = ref.watch(
      feedControllerProvider.select(
        (current) =>
            controller.stateForPopularSection(section, current: current),
      ),
    );
    final categories = section == PopularSection.ranking
        ? ref.watch(rankingCategoriesProvider)
        : null;
    if (section == PopularSection.ranking) {
      ref.listen(rankingCategoriesProvider, (_, _) => _reconcileRegion());
      // A paused hidden pane can resume after the directory already changed.
      _reconcileRegion();
    }
    final content = Column(
      children: [
        if (section == PopularSection.weekly && feed.weeklyIssues.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: DropdownButton<int>(
              key: const ValueKey('popular-week-selector'),
              value: feed.weeklyIssue,
              isExpanded: true,
              menuMaxHeight: 320,
              items: [
                for (final week in feed.weeklyIssues)
                  DropdownMenuItem(
                    value: week.number,
                    child: Text(
                      week.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: pageActive
                  ? (number) {
                      if (number != null) controller.selectPopularWeek(number);
                    }
                  : null,
            ),
          ),
        if (section == PopularSection.ranking)
          Align(
            alignment: Alignment.centerLeft,
            child: ScrollConfiguration(
              behavior: const SmoothScrollBehavior(horizontalMouseWheel: true),
              child: SingleChildScrollView(
                key: const ValueKey('popular-ranking-regions'),
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    for (final category in [
                      const VideoCategory(id: '0', name: '全站'),
                      ...?categories?.asData?.value,
                    ])
                      TextButton(
                        key: ValueKey('home-section-${category.id}'),
                        onPressed: pageActive
                            ? () => controller.selectCategory(category.id)
                            : null,
                        style: TextButton.styleFrom(
                          foregroundColor: feed.categoryId == category.id
                              ? Theme.of(context).colorScheme.primary
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        child: Text(category.name),
                      ),
                  ],
                ),
              ),
            ),
          ),
        Expanded(
          child: PagedScrollViewport(
            key: ValueKey(('popular', section, feed.weeklyIssue)),
            active: pageActive,
            canLoadMore:
                feed.hasMore &&
                !feed.loadingMore &&
                feed.pageError == null &&
                feed.items.asData != null,
            contentVersion: feed.items,
            onLoadMore: () async {
              final current = ref.read(feedControllerProvider);
              if (pageActive &&
                  current.popular &&
                  current.popularSection == section) {
                await controller.loadMore();
              }
            },
            onRefresh: controller.refresh,
            refreshTooltip: '刷新视频',
            builder: (scrollController) => RefreshIndicator(
              onRefresh: controller.refresh,
              child: CustomScrollView(
                key: PageStorageKey(
                  'popular-${section.name}-${feed.weeklyIssue}',
                ),
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  if (categories?.hasError == true)
                    SliverToBoxAdapter(
                      child: StateView.error(
                        message: '分区列表加载失败',
                        onAction: () =>
                            ref.invalidate(rankingCategoriesProvider),
                      ),
                    ),
                  SliverCardGridPadding(sliver: _itemsSliver(feed.items)),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: feed.loadingMore
                          ? const Center(child: CircularProgressIndicator())
                          : feed.pageError != null
                          ? StateView.error(
                              message: '更多内容加载失败',
                              onAction: controller.loadMore,
                            )
                          : feed.hasMore
                          ? Center(
                              child: OutlinedButton(
                                onPressed: controller.loadMore,
                                child: const Text('加载更多'),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
    var storage = _storage;
    final issue = feed.weeklyIssue;
    if (section == PopularSection.weekly && issue != null) {
      storage = _weekStorage.remove(issue) ?? PageStorageBucket();
      _weekStorage[issue] = storage;
      while (_weekStorage.length > FeedController.maximumCachedWeeks + 1) {
        _weekStorage.remove(_weekStorage.keys.first);
      }
    }
    return TickerMode(
      enabled: pageActive,
      child: PageStorage(bucket: storage, child: content),
    );
  }
}
