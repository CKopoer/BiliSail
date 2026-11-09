import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../domain/video.dart';
import '../../../domain/recommendation_source.dart';
import '../../../shared/ui/app_dialog.dart';
import '../../../shared/ui/app_notice.dart';
import '../../video/domain/video_actions_repository.dart';
import '../../../core/presentation/workspace_activity.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/retained_tab_view.dart';
import '../../../shared/ui/content_section_tabs.dart';
import '../../../shared/ui/dynamic_compose_dialog.dart';
import '../application/dynamic_authors_controller.dart';
import '../application/home_controller.dart';
import '../application/feed_controller.dart';
import '../application/app_recommendation_identity.dart';
import '../domain/home_channel.dart';
import 'home_content.dart';
import 'home_channel_swipe.dart';
import 'popular_feed.dart';
import 'feed_video_grid.dart';
import 'dynamic_author_filter.dart';

typedef _FeedContent = ({
  HomeChannel channel,
  bool selected,
  AsyncValue<List<VideoSummary>> items,
  String? categoryId,
  bool hasMore,
  bool loadingMore,
  bool refreshing,
  int? previousStartIndex,
  Object? pageError,
});

typedef _ChannelPageConfiguration = ({
  bool active,
  String? initialSection,
  bool signedIn,
  bool hasLogin,
  bool showLiveSectionTabs,
  bool swipeEnabled,
  bool hasSectionCallback,
});

final class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({
    super.key,
    this.channel = HomeChannel.recommended,
    this.isSignedIn = false,
    this.onLogin,
    this.initialSection,
    this.onChannelChanged,
    this.animateChannelSelection,
    this.channelGroups,
    this.showLiveSectionTabs = true,
    this.onSectionChanged,
  });
  final HomeChannel channel;
  final bool isSignedIn;
  final VoidCallback? onLogin;
  final String? initialSection;
  final ValueChanged<HomeChannel>? onChannelChanged;
  final TabSelectionAnimation<HomeChannel>? animateChannelSelection;
  final List<List<HomeChannel>>? channelGroups;
  final bool showLiveSectionTabs;
  final ValueChanged<String>? onSectionChanged;
  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

final class _FeedScreenState extends ConsumerState<FeedScreen> {
  final _pages = <HomeChannel, (_ChannelPageConfiguration, Widget)>{};

  void _login() => widget.onLogin?.call();

  void _sectionChanged(HomeChannel channel, String section) {
    if (widget.channel == channel) widget.onSectionChanged?.call(section);
  }

  @override
  void initState() {
    super.initState();
    _selectChannel();
  }

  @override
  void didUpdateWidget(FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel != widget.channel) _selectChannel();
  }

  void _selectChannel() {
    Future<void>.microtask(() {
      if (mounted) {
        if (widget.channel != HomeChannel.popular &&
            widget.channel != HomeChannel.ranking) {
          ref
              .read(feedControllerProvider.notifier)
              .selectChannel(widget.channel);
        }
      }
    });
  }

  Widget _page(BuildContext context, HomeChannel channel, bool active) {
    final initialSection =
        (channel == HomeChannel.popular || channel == HomeChannel.ranking) &&
            widget.channel == HomeChannel.ranking
        ? '排行榜'
        : channel == widget.channel
        ? widget.initialSection
        : null;
    final configuration = (
      active: active,
      initialSection: initialSection,
      signedIn: widget.isSignedIn,
      hasLogin: widget.onLogin != null,
      showLiveSectionTabs: widget.showLiveSectionTabs,
      swipeEnabled: widget.onChannelChanged == null,
      hasSectionCallback: widget.onSectionChanged != null,
    );
    // Primary destinations keep their selected inner tab. Reuse its widget
    // when only the enclosing WorkspaceActivity changes; inherited account,
    // layout and visibility updates still reach the mounted descendants.
    final cached = _pages[channel];
    final retainPage = widget.onChannelChanged != null;
    if (retainPage && cached != null && cached.$1 == configuration) {
      return cached.$2;
    }
    final ValueChanged<String>? onSectionChanged =
        widget.onSectionChanged != null
        ? (section) => _sectionChanged(channel, section)
        : null;
    final Widget page;
    if (channel == HomeChannel.popular || channel == HomeChannel.ranking) {
      page = PopularFeed(
        active: active,
        swipeEnabled: widget.onChannelChanged == null,
        initialSection: initialSection,
        onSectionChanged: onSectionChanged,
      );
    } else {
      page = _HomeChannelPage(
        channel: channel,
        active: active,
        initialSection: initialSection,
        isSignedIn: widget.isSignedIn,
        onLogin: widget.onLogin == null ? null : _login,
        showLiveSectionTabs: widget.showLiveSectionTabs,
        onSectionChanged: onSectionChanged,
      );
    }
    if (retainPage) _pages[channel] = (configuration, page);
    return page;
  }

  @override
  Widget build(BuildContext context) {
    final onChanged = widget.onChannelChanged;
    final content = onChanged == null
        ? _page(context, widget.channel, true)
        : HomeChannelSwipe(
            channel: widget.channel,
            onChanged: onChanged,
            animateSelection: widget.animateChannelSelection,
            channelGroups: widget.channelGroups,
            pageBuilder: _page,
          );
    return DynamicFeedLayout(
      visible:
          widget.channel == HomeChannel.dynamic ||
          widget.channel == HomeChannel.videoDynamic,
      isSignedIn: widget.isSignedIn,
      child: content,
    );
  }
}

final class _HomeChannelPage extends ConsumerStatefulWidget {
  const _HomeChannelPage({
    required this.channel,
    required this.active,
    required this.isSignedIn,
    this.onLogin,
    this.initialSection,
    this.showLiveSectionTabs = true,
    this.onSectionChanged,
  });

  final HomeChannel channel;
  final bool active;
  final bool isSignedIn;
  final VoidCallback? onLogin;
  final String? initialSection;
  final bool showLiveSectionTabs;
  final ValueChanged<String>? onSectionChanged;

  @override
  ConsumerState<_HomeChannelPage> createState() => _HomeChannelPageState();
}

final class _HomeChannelPageState extends ConsumerState<_HomeChannelPage> {
  final Map<HomeChannel, String> _sections = {};
  final Set<(HomeChannel, String)> _visitedSections = {};
  (List<VideoSummary>, HomeChannel, int?)? _gridVersion;
  Widget? _grid;

  Future<void> _refreshDynamic() async {
    final scope = ref.read(homeRepositoryProvider).accountScope;
    final query = (
      channel: HomeChannel.dynamic,
      section: _sections[HomeChannel.dynamic] ?? '全部',
      scope: scope,
      folderId: null,
    );
    final author = ref.read(dynamicAuthorsProvider(scope)).selected?.id;
    final provider = author == null
        ? homeControllerProvider(query)
        : dynamicAuthorFeedProvider((query: query, authorId: author));
    await Future.wait([
      ref.read(provider.notifier).refresh(),
      ref.read(dynamicAuthorsProvider(scope).notifier).refresh(),
    ]);
  }

  Widget _videoItemsSliver(_FeedContent feed, HomeChannel channel) {
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
        final version = (items, channel, feed.previousStartIndex);
        // Pagination flags belong to the footer. Keep the same grid widget
        // while its data/actions are unchanged so its visible rows stay built.
        final previous = _gridVersion;
        if (previous == null ||
            !identical(previous.$1, items) ||
            previous.$2 != channel ||
            previous.$3 != feed.previousStartIndex) {
          _gridVersion = version;
          _grid = FeedVideoGrid(
            items: items,
            channel: channel,
            previousStartIndex: feed.previousStartIndex,
            onReject: _rejectRecommendation,
            onUndo: _undoRecommendationFeedback,
          );
        }
        return SliverMainAxisGroup(
          slivers: [
            if (feed.refreshing)
              const SliverToBoxAdapter(child: LinearProgressIndicator()),
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
        // Non-video channels own their HomeContent viewport. Keeping an empty
        // recommendation viewport underneath it adds scroll/layout work.
        if (channel.hasVideoFeed) videoFeed else const SizedBox.shrink(),
        for (final entry in visited)
          HomeContent(
            key: ValueKey(entry),
            channel: entry.$1,
            section: entry.$2,
            active: widget.active && !channel.hasVideoFeed && entry == current,
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
  }

  @override
  void didUpdateWidget(_HomeChannelPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSection != widget.initialSection ||
        oldWidget.channel != widget.channel) {
      _selectInitialSection();
    }
  }

  void _selectInitialSection() {
    final section =
        widget.channel == HomeChannel.live &&
            (widget.initialSection == '全部分区' ||
                widget.onSectionChanged != null &&
                    widget.initialSection == null)
        ? '推荐直播'
        : widget.initialSection;
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
      RecommendationFeedbackReason? reason;
      final feedback = video.recommendationFeedback;
      final query = ref.read(recommendationQueryKeyProvider);
      if (feedback?.source == RecommendationSource.app) {
        final reasons =
            feedback?.reasons ?? const <RecommendationFeedbackReason>[];
        if (reasons.isEmpty) {
          if (mounted) showAppNotice(context, '此推荐暂未提供可用的反馈原因');
          return;
        }
        reason = await showAppDialog<RecommendationFeedbackReason>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('不感兴趣'),
            children: [
              for (final item in reasons)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(item),
                  child: Text(item.name),
                ),
            ],
          ),
        );
        if (!mounted ||
            reason == null ||
            query != ref.read(recommendationQueryKeyProvider)) {
          return;
        }
      }
      await controller.rejectRecommendation(video, reason: reason);
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
    final controller = ref.watch(feedControllerProvider.notifier);
    final channel = widget.channel;
    final feed = channel.hasVideoFeed
        ? ref.watch(
            feedControllerProvider.select((current) {
              final state = controller.stateForChannel(
                channel,
                current: current,
              );
              // Feedback is observed by its mounted card. It does not change
              // list membership, pagination or the viewport's geometry.
              return (
                channel: state.channel,
                selected: current.channel == channel,
                items: state.items,
                categoryId: state.categoryId,
                hasMore: state.hasMore,
                loadingMore: state.loadingMore,
                refreshing: state.refreshing,
                previousStartIndex: state.previousStartIndex,
                pageError: state.pageError,
              );
            }),
          )
        : (
            channel: channel,
            selected: false,
            items: const AsyncData<List<VideoSummary>>([]),
            categoryId: null,
            hasMore: false,
            loadingMore: false,
            refreshing: false,
            previousStartIndex: null,
            pageError: null,
          );
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
    final sectionTabs = ContentSectionTabs<String>(
      entries: entries,
      value: categories != null ? feed.categoryId : section,
      scrollKey: ValueKey('home-section-strip-${channel.name}'),
      itemKey: (id) => ValueKey('home-section-$id'),
      onSelected: (id) {
        if (categories != null) {
          controller.selectCategory(id);
        } else {
          setState(() => _sections[channel] = id);
          if (widget.active && WorkspaceActivity.isActive(context)) {
            widget.onSectionChanged?.call(id);
          }
        }
      },
    );
    return Stack(
      children: [
        Column(
          children: [
            if (entries.isNotEmpty &&
                channel != HomeChannel.videoDynamic &&
                (channel != HomeChannel.live || widget.showLiveSectionTabs))
              if (channel == HomeChannel.dynamic && widget.isSignedIn)
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 804),
                    child: DynamicComposeToolbar(
                      onLogin: widget.onLogin,
                      onPublished: _refreshDynamic,
                      child: sectionTabs,
                    ),
                  ),
                )
              else
                sectionTabs,
            Expanded(
              child: _content(
                channel: channel,
                section: section,
                videoFeed: PagedScrollViewport(
                  key: ValueKey(('video-feed', channel)),
                  active: widget.active && channel.hasVideoFeed,
                  canLoadMore:
                      widget.active &&
                      feed.selected &&
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
                        SliverCardGridPadding(
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
