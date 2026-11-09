import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/presentation/workspace_activity.dart';
import '../../../domain/app_failure.dart';
import '../../../domain/user.dart';
import '../../../domain/video.dart';
import '../../../shared/ui/network_avatar.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/sliver_dynamic_post_list.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_card.dart';
import '../application/dynamic_topic_controller.dart';

class DynamicTopicScreen extends ConsumerWidget {
  const DynamicTopicScreen({
    super.key,
    required this.id,
    this.onOpenUser,
    this.onOpenVideo,
    this.onOpenLink,
    this.onLogin,
  });
  final String id;
  final ValueChanged<UserId>? onOpenUser;
  final ValueChanged<VideoSummary>? onOpenVideo;
  final ValueChanged<Uri>? onOpenLink;
  final VoidCallback? onLogin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (id.length > 128 || !RegExp(r'^[1-9][0-9]*$').hasMatch(id)) {
      return const StateView.empty(message: '话题地址无效');
    }
    final state = ref.watch(dynamicTopicProvider(id));
    final controller = ref.read(dynamicTopicProvider(id).notifier);
    final detail = state.detail;
    final theme = Theme.of(context);
    final active = WorkspaceActivity.isActive(context);
    return PagedScrollViewport(
      key: ValueKey((id, state.sort)),
      keepScrollOffset: false,
      active: active,
      contentVersion: state,
      canLoadMore:
          state.hasMore &&
          !state.loading &&
          !state.foldLoading &&
          state.error == null,
      onLoadMore: controller.loadMore,
      builder: (scrollController) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          key: PageStorageKey('dynamic-topic-$id'),
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 780),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.tag),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                detail?.name ?? '话题',
                                style: theme.textTheme.titleLarge,
                              ),
                            ),
                            IconButton(
                              tooltip: '刷新话题',
                              onPressed: state.loading
                                  ? null
                                  : controller.refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                          ],
                        ),
                        if (detail != null) ...[
                          if (detail.description.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            SelectableText(detail.description),
                          ],
                          const SizedBox(height: 10),
                          Text(
                            '${compactCount(detail.viewCount)}浏览 · ${compactCount(detail.discussCount)}讨论',
                            style: theme.textTheme.bodySmall,
                          ),
                          if (detail.creatorName.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            InkWell(
                              onTap:
                                  detail.creatorId == null || onOpenUser == null
                                  ? null
                                  : () => onOpenUser!(detail.creatorId!),
                              child: Row(
                                children: [
                                  NetworkAvatar(
                                    url: detail.creatorAvatar,
                                    name: detail.creatorName,
                                    radius: 14,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      '${detail.creatorName} 发起',
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                        if (state.sorts.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              for (final sort in state.sorts)
                                ChoiceChip(
                                  label: Text(sort.name),
                                  selected: state.sort == sort.id,
                                  onSelected: (_) =>
                                      controller.selectSort(sort.id),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (state.posts.isNotEmpty)
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                sliver: SliverDynamicPostList(
                  posts: state.posts,
                  onOpenUser: onOpenUser,
                  onOpenVideo: onOpenVideo,
                  onOpenLink: onOpenLink,
                  onLogin: onLogin,
                ),
              ),
            if (state.loading)
              const SliverToBoxAdapter(child: StateView.loading())
            else if (state.error != null)
              SliverToBoxAdapter(
                child: StateView.error(
                  message: state.error is AppFailure
                      ? (state.error! as AppFailure).message
                      : '话题加载失败，请重试',
                  onAction: controller.retry,
                ),
              )
            else if (state.posts.isEmpty && state.foldDescription.isEmpty)
              const SliverToBoxAdapter(
                child: StateView.empty(message: '话题下暂时没有动态'),
              ),
            if (state.foldDescription.isNotEmpty)
              SliverToBoxAdapter(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        if (state.foldError != null) const Text('折叠内容加载失败，请重试'),
                        OutlinedButton.icon(
                          onPressed: state.foldLoading || state.loading
                              ? null
                              : controller.loadFolded,
                          icon: state.foldLoading
                              ? const SizedBox.square(
                                  dimension: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.expand_more),
                          label: Text(state.foldDescription),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            if (state.hasMore && !state.loading && state.error == null)
              SliverToBoxAdapter(
                child: Center(
                  child: TextButton(
                    onPressed: controller.loadMore,
                    child: const Text('加载更多动态'),
                  ),
                ),
              ),
            if (!state.hasMore &&
                !state.loading &&
                state.error == null &&
                state.posts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    state.posts.length >= DynamicTopicController.maximumPosts
                        ? '已显示500条动态，可刷新查看'
                        : '没有更多动态了',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
