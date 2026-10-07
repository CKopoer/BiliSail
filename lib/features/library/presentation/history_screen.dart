import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/state_view.dart';
import '../../../shared/ui/video_grid.dart';
import '../application/library_controller.dart';

final class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  static String _watchedAt(DateTime value) {
    final date = value.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '观看于 ${date.year}-${two(date.month)}-${two(date.day)} ${two(date.hour)}:${two(date.minute)}';
  }

  static String _watchDate(DateTime value) {
    final date = value.toLocal();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return date.year == DateTime.now().year
        ? '$month-$day'
        : '${date.year}-$month-$day';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final controller = ref.read(historyProvider.notifier);
    return PagedScrollViewport(
      active: true,
      canLoadMore:
          history.hasMore && !history.loadingMore && history.pageError == null,
      contentVersion: history.items,
      onLoadMore: controller.loadMore,
      onRefresh: controller.refresh,
      refreshTooltip: '刷新云端观看历史',
      builder: (scrollController) => RefreshIndicator(
        onRefresh: controller.refresh,
        child: CustomScrollView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 84),
              sliver: SliverMainAxisGroup(
                slivers: [
                  SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '观看历史',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 7),
                        Text(
                          '当前账号的云端观看记录',
                          style: TextStyle(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 18),
                      ],
                    ),
                  ),
                  const _HistoryEntriesSliver(),
                  SliverToBoxAdapter(
                    child: Column(
                      children: [
                        if (history.loadingMore)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                        if (history.pageError case final error?)
                          Padding(
                            padding: const EdgeInsets.all(16),
                            child: StateView.error(
                              message: error is AppFailure
                                  ? error.message
                                  : '更多历史加载失败',
                              onAction: controller.loadMore,
                            ),
                          ),
                        if (history.limitReached)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('已显示最近 500 条云端记录'),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Paging status changes affect the footer without rebuilding unchanged cards.
final class _HistoryEntriesSliver extends ConsumerWidget {
  const _HistoryEntriesSliver();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(historyProvider.select((state) => state.items));
    final controller = ref.read(historyProvider.notifier);
    return items.when(
      loading: () => const SliverToBoxAdapter(
        child: SizedBox(height: 300, child: StateView.loading()),
      ),
      error: (error, _) => SliverToBoxAdapter(
        child: SizedBox(
          height: 300,
          child: StateView.error(
            message: error is AppFailure ? error.message : '历史记录加载失败',
            onAction: controller.refresh,
          ),
        ),
      ),
      data: (entries) => entries.isEmpty
          ? const SliverToBoxAdapter(
              child: SizedBox(
                height: 280,
                child: StateView.empty(message: '还没有云端观看记录'),
              ),
            )
          : SliverVideoGrid.indexed(
              onOpenUser: (id) => context.go('/user/${id.value}'),
              items: [for (final entry in entries) entry.video],
              onOpen: (index) => context.go(entries[index].location.toString()),
              publishTextAt: (index) =>
                  HistoryScreen._watchDate(entries[index].watchedAt),
              publishTooltipAt: (index) =>
                  HistoryScreen._watchedAt(entries[index].watchedAt),
              progressAt: (index) {
                final entry = entries[index];
                if (entry.part.duration.inMilliseconds <= 0) {
                  return null;
                }
                return (entry.position.inMilliseconds /
                        entry.part.duration.inMilliseconds)
                    .clamp(0, 1);
              },
            ),
    );
  }
}
