import 'package:material_ui/material_ui.dart' hide SearchController;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/app_failure.dart';
import '../../../shared/ui/paged_scroll_viewport.dart';
import '../../../shared/ui/responsive_card_grid.dart';
import '../../../shared/ui/state_view.dart';
import '../application/search_controller.dart';
import '../domain/search_result.dart';
import 'search_filter_toolbar.dart';
import 'search_results.dart';

final class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, required this.query});
  final String query;
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

final class _SearchScreenState extends ConsumerState<SearchScreen> {
  List<SearchEntry>? _previousItems;
  String? _previousQuery;
  SearchCategory? _previousCategory;
  Widget? _results;

  void _clearResults() {
    _previousItems = null;
    _previousQuery = null;
    _previousCategory = null;
    _results = null;
  }

  Widget _resultSliver(
    List<SearchEntry> items,
    SearchState result,
    SearchController controller,
  ) {
    if (_results == null ||
        !identical(items, _previousItems) ||
        result.query != _previousQuery ||
        result.category != _previousCategory) {
      _previousItems = items;
      _previousQuery = result.query;
      _previousCategory = result.category;
      _results = SearchResults(
        items: items,
        query: result.query,
        category: result.category,
        onCategory: controller.selectCategory,
      );
    }
    return _results!;
  }

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
    // Only a usable current result belongs in this presentation cache. Paging
    // loading/errors retain data; whole-query replacement must release it.
    if (result.query.isEmpty ||
        result.items.asData?.value.isNotEmpty != true ||
        result.query != _previousQuery ||
        result.category != _previousCategory) {
      _clearResults();
    }
    final controller = ref.read(searchControllerProvider.notifier);
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SearchFilterToolbar(result: result),
        Expanded(
          child: PagedScrollViewport(
            keepScrollOffset: false,
            key: ValueKey((
              result.query,
              result.category,
              result.order,
              result.duration,
              result.userType,
              result.videoZone,
              result.articleZone,
              result.publicationPeriod,
              result.publicationRange,
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
            builder: (scrollController) => CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverCardGridPadding(
                  desktopInset: 28,
                  bottom: 32,
                  sliver: result.query.isEmpty
                      ? const SliverToBoxAdapter(
                          child: SizedBox(
                            height: 280,
                            child: StateView.empty(
                              message: '输入关键词开始搜索',
                              icon: Icons.search_rounded,
                            ),
                          ),
                        )
                      : result.items.when(
                          loading: () => const SliverToBoxAdapter(
                            child: SizedBox(
                              height: 300,
                              child: StateView.loading(),
                            ),
                          ),
                          error: (error, _) => SliverToBoxAdapter(
                            child: SizedBox(
                              height: 300,
                              child: StateView.error(
                                message: error is AppFailure
                                    ? error.message
                                    : '搜索失败，请重试',
                                onAction: controller.refresh,
                              ),
                            ),
                          ),
                          data: (items) => items.isEmpty
                              ? SliverToBoxAdapter(
                                  child: SizedBox(
                                    height: 280,
                                    child: StateView.empty(
                                      message:
                                          '没有找到相关${result.category == SearchCategory.all ? '内容' : result.category.label}，试试其他关键词或筛选',
                                    ),
                                  ),
                                )
                              : SliverMainAxisGroup(
                                  slivers: [
                                    _resultSliver(items, result, controller),
                                    SliverToBoxAdapter(
                                      child: Padding(
                                        padding: const EdgeInsets.only(top: 28),
                                        child: result.pageError != null
                                            ? StateView.error(
                                                message:
                                                    result.pageError
                                                        is AppFailure
                                                    ? (result.pageError
                                                              as AppFailure)
                                                          .message
                                                    : '下一页加载失败',
                                                onAction: controller.loadMore,
                                              )
                                            : result.loadingMore
                                            ? const Center(
                                                child:
                                                    CircularProgressIndicator(),
                                              )
                                            : result.hasMore
                                            ? Center(
                                                child: OutlinedButton(
                                                  onPressed:
                                                      controller.loadMore,
                                                  child: const Text('加载更多'),
                                                ),
                                              )
                                            : Center(
                                                child: Text(
                                                  '已经到底了',
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                ),
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
        ),
      ],
    );
  }
}
