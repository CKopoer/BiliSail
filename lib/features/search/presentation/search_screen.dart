import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/state_view.dart';
import '../application/search_controller.dart';
import '../domain/search_result.dart';
import 'search_results.dart';

final class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.query});
  final String query;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

final class _SearchScreenState extends ConsumerState<SearchScreen> {
  bool _showFilters = false;
  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() => Future<void>.microtask(() {
    if (mounted) {
      ref.read(searchControllerProvider.notifier).search(widget.query);
    }
  });
  @override
  void didUpdateWidget(covariant SearchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.query != widget.query) _search();
  }

  @override
  Widget build(BuildContext context) {
    final result = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = constraints.maxWidth < 600 ? 12.0 : 28.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.query.isEmpty
                        ? '在顶部输入关键词，寻找视频、番剧、直播和用户'
                        : '“${result.query}” 的搜索结果',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final category in SearchCategory.values)
                          _CategoryTab(
                            category: category,
                            selected: result.category == category,
                            count: result.counts[category],
                            onTap: () {
                              setState(() => _showFilters = false);
                              controller.selectCategory(category);
                            },
                          ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: .5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _OptionStrip(
                          children: [
                            for (final order in result.category.orders)
                              _Option(
                                label: order.label,
                                selected: result.order == order,
                                onTap: () => controller.selectOrder(order),
                              ),
                          ],
                        ),
                      ),
                      if (result.category.hasDurationFilter ||
                          result.category == SearchCategory.user) ...[
                        const SizedBox(width: 12),
                        OutlinedButton(
                          key: const ValueKey('search-more-filters'),
                          onPressed: () =>
                              setState(() => _showFilters = !_showFilters),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            visualDensity: VisualDensity.compact,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                result.duration != SearchDuration.any
                                    ? result.duration.label
                                    : result.userType != SearchUserType.any
                                    ? result.userType.label
                                    : '更多筛选',
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                _showFilters
                                    ? Icons.expand_less
                                    : Icons.expand_more,
                                size: 18,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_showFilters) ...[
                    const SizedBox(height: 12),
                    _OptionStrip(
                      children: [
                        if (result.category.hasDurationFilter)
                          for (final duration in SearchDuration.values)
                            _Option(
                              label: duration.label,
                              selected: result.duration == duration,
                              onTap: () => controller.selectDuration(duration),
                            ),
                        if (result.category == SearchCategory.user)
                          for (final type in SearchUserType.values)
                            _Option(
                              label: type.label,
                              selected: result.userType == type,
                              onTap: () => controller.selectUserType(type),
                            ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Expanded(
              child: PagedScrollViewport(
                keepScrollOffset: false,
                key: ValueKey((
                  result.query,
                  result.category,
                  result.order,
                  result.duration,
                  result.userType,
                )),
                active: result.query.isNotEmpty,
                canLoadMore:
                    result.hasMore &&
                    !result.loadingMore &&
                    result.pageError == null &&
                    result.items.hasValue,
                contentVersion: (
                  result.items.asData?.value.length,
                  result.loadingMore,
                  result.hasMore,
                  result.pageError,
                ),
                onLoadMore: controller.loadMore,
                onRefresh: result.query.isEmpty ? null : controller.refresh,
                refreshTooltip: '刷新搜索结果',
                builder: (scrollController) => ListView(
                  controller: scrollController,
                  padding: EdgeInsets.fromLTRB(padding, 8, padding, 32),
                  children: [
                    result.query.isEmpty
                        ? const SizedBox(
                            height: 280,
                            child: StateView.empty(
                              message: '输入关键词开始搜索',
                              icon: Icons.search_rounded,
                            ),
                          )
                        : result.items.when(
                            loading: () => const SizedBox(
                              height: 300,
                              child: StateView.loading(),
                            ),
                            error: (error, _) => SizedBox(
                              height: 300,
                              child: StateView.error(
                                message: error is AppFailure
                                    ? error.message
                                    : '搜索失败，请重试',
                                onAction: controller.refresh,
                              ),
                            ),
                            data: (items) => items.isEmpty
                                ? SizedBox(
                                    height: 280,
                                    child: StateView.empty(
                                      message:
                                          '没有找到相关${result.category == SearchCategory.all ? '内容' : result.category.label}，试试其他关键词或筛选',
                                    ),
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      SearchResults(
                                        items: items,
                                        query: result.query,
                                        category: result.category,
                                        onCategory: controller.selectCategory,
                                      ),
                                      const SizedBox(height: 28),
                                      if (result.pageError != null)
                                        StateView.error(
                                          message:
                                              result.pageError is AppFailure
                                              ? (result.pageError as AppFailure)
                                                    .message
                                              : '下一页加载失败',
                                          onAction: controller.loadMore,
                                        )
                                      else if (result.loadingMore)
                                        const Center(
                                          child: CircularProgressIndicator(),
                                        )
                                      else if (result.hasMore)
                                        Center(
                                          child: OutlinedButton(
                                            onPressed: controller.loadMore,
                                            child: const Text('加载更多'),
                                          ),
                                        )
                                      else
                                        Center(
                                          child: Text(
                                            '已经到底了',
                                            style: theme.textTheme.bodySmall,
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

final class _CategoryTab extends StatelessWidget {
  const _CategoryTab({
    required this.category,
    required this.selected,
    required this.onTap,
    this.count,
  });
  final SearchCategory category;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          key: ValueKey('search-category-${category.name}'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 12, 15, 14),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  category.label,
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: selected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (count case final int total) ...[
                  const SizedBox(width: 5),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      total > 99 ? '99+' : '$total',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

final class _Option extends StatelessWidget {
  const _Option({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: selected ? scheme.primary : scheme.onSurface,
          backgroundColor: selected
              ? scheme.primary.withValues(alpha: .09)
              : Colors.transparent,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      ),
    );
  }
}

/// Keep controls accessible on short windows and at large text scales.
final class _OptionStrip extends StatelessWidget {
  const _OptionStrip({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          children[i],
        ],
      ],
    ),
  );
}
